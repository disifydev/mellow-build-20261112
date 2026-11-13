import Foundation
import SwiftUI
import PivchikDomain

/// Единственное хранилище приложения: один JSON-файл (снимок) в Application Support.
/// Вся аналитика считается ядром PivchikDomain по `active` — снимку без удалённых записей.
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: Snapshot
    /// Текущий уровень на дуге главного экрана (от него зависит фон).
    @Published var level: Int
    /// Необязательный вход через Apple (см. AppleAccount.swift).
    @Published var appleUserID: String? = nil
    @Published var appleName: String? = nil

    private(set) var active: Snapshot
    private(set) var dayStats: [LocalDay: DayStats]
    private(set) var diary: [DiaryItem]

    let isDemo: Bool
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(demo: Bool) {
        isDemo = demo
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = dir.appendingPathComponent("mellow.json")

        AppStore.removeExportFiles()
        var s = Snapshot()
        if demo {
            DemoData.fill(&s, now: Date())
        } else {
            s = AppStore.load(from: fileURL)
        }
        AppStore.normalize(&s)
        let achievementsBefore = s.achievements.count
        AppStore.award(&s)
        let awardedAtLaunch = s.achievements.count != achievementsBefore

        let a = s.active()
        let th = AppStore.thresholds(in: a)
        snapshot = s
        active = a
        dayStats = DayAnalytics.dayStats(snapshot: a, thresholds: th)
        diary = DiaryItem.build(from: a)
        level = 3
        level = lastLevelToday() ?? 3
        if awardedAtLaunch { scheduleSave() }
        if Features.appleSignIn { loadAppleAccount() }
    }

    // MARK: Время и пояс

    var zone: String { TimeZone.current.identifier }
    var today: LocalDay { LocalDay(date: Date(), zoneID: zone) }

    func meta() -> RecordMeta { RecordMeta(createdAt: Date()) }

    // MARK: Чтение

    var settings: SettingsRecord {
        MergeRules.dedupeSettings(active.settings).kept.first ?? SettingsRecord(meta: RecordMeta(createdAt: Date()), theme: AppStore.eveningTheme)
    }

    var thresholds: DayThresholds { settings.thresholds.normalized }

    static let eveningTheme = "eveningDark"
    var darkEvening: Bool { settings.theme == AppStore.eveningTheme }

    var palette: Palette {
        let tod = Launch.tod ?? TimeOfDay.current(date: Date(), darkEvening: darkEvening)
        return Palette.make(level: level, tod: tod)
    }

    var practices: [PracticeDefinitionRecord] {
        active.practices.sorted { $0.sortOrder < $1.sortOrder }
    }

    func practice(_ type: PracticeType) -> PracticeDefinitionRecord? {
        practices.first { $0.type == type }
    }

    func practice(id: UUID) -> PracticeDefinitionRecord? {
        active.practices.first { $0.id == id }
    }

    var histories: [HistoryRecord] {
        active.histories.sorted { $0.startedAt < $1.startedAt }
    }

    func history(_ id: UUID) -> HistoryRecord? {
        active.histories.first { $0.id == id }
    }

    func historyIndex(_ id: UUID) -> Int {
        histories.firstIndex { $0.id == id } ?? 0
    }

    func historyTitles(_ ids: [UUID]) -> [String] {
        ids.compactMap { history($0)?.title }
    }

    var wins: [SmallWinRecord] {
        active.smallWins.sorted { $0.occurredAt > $1.occurredAt }
    }

    var hasAnyMeasurement: Bool { !dayStats.isEmpty }

    func reflection(on day: LocalDay) -> DayReflectionRecord? {
        MergeRules.mergeDayReflections(active.dayReflections.filter { $0.localDate == day.description }).kept.first
    }

    private func lastLevelToday() -> Int? {
        let day = today
        return active.checkIns
            .filter { LocalDay(date: $0.observedAt, zoneID: $0.zoneID) == day }
            .max { $0.observedAt < $1.observedAt }?.anxiety
    }

    /// Сводка периода из ядра.
    func summary(from: LocalDay, to: LocalDay) -> PeriodSummary {
        DayAnalytics.summary(from: from, to: to, stats: dayStats)
    }

    /// Статистика дней с фильтром «Прогресса» (истории, теги, время суток). Пустой фильтр — общая статистика.
    func dayStats(filter: MeasurementFilter) -> [LocalDay: DayStats] {
        if filter.isEmpty { return dayStats }
        return DayAnalytics.dayStats(snapshot: active, thresholds: thresholds, filter: filter)
    }

    /// Все теги из отметок и эпизодов — для фильтров.
    var allTags: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in active.checkIns.flatMap({ $0.tags }) + active.episodes.flatMap({ $0.tags }) where !seen.contains(t.lowercased()) {
            seen.insert(t.lowercased())
            out.append(t)
        }
        return out
    }

    /// Начало дня в текущем поясе — граница периода для аналитики по датам.
    func startDate(_ day: LocalDay) -> Date { day.startDate(zoneID: zone) }

    // MARK: Изменения

    func mutate(_ change: (inout Snapshot) -> Void) {
        var s = snapshot
        change(&s)
        apply(s)
    }

    private func apply(_ new: Snapshot) {
        var s = new
        AppStore.award(&s)
        let a = s.active()
        active = a
        dayStats = DayAnalytics.dayStats(snapshot: a, thresholds: AppStore.thresholds(in: a))
        diary = DiaryItem.build(from: a)
        snapshot = s
        scheduleSave()
    }

    func softDelete<R: Record>(_ keyPath: WritableKeyPath<Snapshot, [R]>, id: UUID) {
        update(keyPath, id: id) { $0.meta.deletedAt = Date() }
    }

    func update<R: Record>(_ keyPath: WritableKeyPath<Snapshot, [R]>, id: UUID, _ change: (inout R) -> Void) {
        mutate { s in
            guard let i = s[keyPath: keyPath].firstIndex(where: { $0.meta.id == id }) else { return }
            change(&s[keyPath: keyPath][i])
            s[keyPath: keyPath][i].meta.updatedAt = Date()
        }
    }

    func updateSettings(_ change: (inout SettingsRecord) -> Void) {
        var current = settings
        change(&current)
        current.meta.updatedAt = Date()
        let updated = current
        mutate { s in
            if let i = s.settings.firstIndex(where: { $0.meta.id == updated.meta.id }) {
                s.settings[i] = updated
            } else {
                s.settings.append(updated)
            }
        }
    }

    // MARK: Создание записей

    @discardableResult
    func addCheckIn(anxiety: Int, note: String?, at date: Date = Date(), tags: [String] = [], historyIDs: [UUID] = []) -> UUID {
        let m = meta()
        let rec = CheckInRecord(meta: m, observedAt: date, zoneID: zone,
                                isRetrospective: RetrospectiveRule.isRetrospective(eventAt: date, createdAt: m.createdAt),
                                anxiety: AnxietyScale.clamp(anxiety), note: note?.nilIfEmpty, tags: tags, historyIDs: historyIDs)
        mutate { $0.checkIns.append(rec) }
        return rec.meta.id
    }

    func addEpisode(_ episode: EpisodeRecord) {
        var rec = episode
        rec.isRetrospective = RetrospectiveRule.isRetrospective(eventAt: rec.startedAt, createdAt: rec.meta.createdAt)
        let insight = rec.insights?.nilIfEmpty
        let m = meta()
        mutate { s in
            s.episodes.append(rec)
            if let insight {
                s.insights.append(InsightRecord(meta: m, text: insight, historyIDs: rec.historyIDs, sourceKind: .episode, sourceID: rec.meta.id))
            }
        }
    }

    func addConversation(_ conversation: ConversationRecord) {
        var rec = conversation
        rec.isRetrospective = RetrospectiveRule.isRetrospective(eventAt: rec.occurredAt, createdAt: rec.meta.createdAt)
        let insight = rec.insights?.nilIfEmpty
        let m = meta()
        mutate { s in
            s.conversations.append(rec)
            if let insight {
                s.insights.append(InsightRecord(meta: m, text: insight, historyIDs: rec.historyIDs, sourceKind: .conversation, sourceID: rec.meta.id))
            }
        }
    }

    /// Итог дня: один на календарный день. Непустая победа попадает и в общий список побед.
    func saveReflection(day: LocalDay, overall: Int?, helped: String, hard: String, victory: String, summary: String) {
        let existing = reflection(on: day)
        let zoneID = zone
        let m = meta()
        let winMeta = meta()
        mutate { s in
            var id = m.id
            if let existing, let i = s.dayReflections.firstIndex(where: { $0.meta.id == existing.meta.id }) {
                id = existing.meta.id
                s.dayReflections[i].overallAnxiety = overall
                s.dayReflections[i].helped = helped.nilIfEmpty
                s.dayReflections[i].hard = hard.nilIfEmpty
                s.dayReflections[i].victory = victory.nilIfEmpty
                s.dayReflections[i].summary = summary.nilIfEmpty
                s.dayReflections[i].meta.updatedAt = Date()
            } else {
                s.dayReflections.append(DayReflectionRecord(meta: m, localDate: day.description, zoneID: zoneID, overallAnxiety: overall,
                                                            helped: helped.nilIfEmpty, hard: hard.nilIfEmpty,
                                                            victory: victory.nilIfEmpty, summary: summary.nilIfEmpty))
            }
            guard let text = victory.nilIfEmpty else { return }
            if let w = s.smallWins.firstIndex(where: { $0.dayReflectionID == id && !$0.meta.isDeleted }) {
                s.smallWins[w].text = text
                s.smallWins[w].meta.updatedAt = Date()
            } else {
                let at = day == LocalDay(date: Date(), zoneID: zoneID) ? Date() : day.noon
                s.smallWins.append(SmallWinRecord(meta: winMeta, text: text, occurredAt: at, zoneID: zoneID,
                                                  isRetrospective: RetrospectiveRule.isRetrospective(eventAt: at, createdAt: winMeta.createdAt),
                                                  dayReflectionID: id))
            }
        }
    }

    func addWin(_ text: String, historyIDs: [UUID] = []) {
        guard let t = text.nilIfEmpty else { return }
        let rec = SmallWinRecord(meta: meta(), text: t, occurredAt: Date(), zoneID: zone, historyIDs: historyIDs)
        mutate { $0.smallWins.append(rec) }
    }

    @discardableResult
    func addHistory(title: String, details: String?, startedAt: Date) -> UUID {
        let rec = HistoryRecord(meta: meta(), title: title, details: details?.nilIfEmpty, startedAt: startedAt)
        mutate { $0.histories.append(rec) }
        return rec.meta.id
    }

    /// Смена статуса истории: каждое изменение остаётся в хронологии.
    func setStatus(_ status: HistoryStatus, historyID: UUID) {
        guard let h = history(historyID), h.status != status else { return }
        let change = StatusChangeRecord(meta: meta(), historyID: historyID, fromStatus: h.status, toStatus: status, changedAt: Date())
        mutate { s in
            guard let i = s.histories.firstIndex(where: { $0.meta.id == historyID }) else { return }
            s.histories[i].status = status
            s.histories[i].meta.updatedAt = Date()
            s.statusChanges.append(change)
        }
    }

    @discardableResult
    func addGoal(title: String, historyID: UUID?) -> UUID {
        let rec = GoalRecord(meta: meta(), title: title, historyID: historyID)
        mutate { $0.goals.append(rec) }
        return rec.meta.id
    }

    func addGoalStep(goalID: UUID, title: String) {
        let order = active.goalSteps.filter { $0.goalID == goalID }.count
        let rec = GoalStepRecord(meta: meta(), goalID: goalID, title: title, order: order)
        mutate { $0.goalSteps.append(rec) }
    }

    /// Отметить этап цели. Когда все этапы выполнены, цель считается выполненной.
    func toggleStep(_ id: UUID) {
        mutate { s in
            guard let i = s.goalSteps.firstIndex(where: { $0.meta.id == id }) else { return }
            s.goalSteps[i].isDone.toggle()
            s.goalSteps[i].doneAt = s.goalSteps[i].isDone ? Date() : nil
            s.goalSteps[i].meta.updatedAt = Date()
            let goalID = s.goalSteps[i].goalID
            let steps = s.goalSteps.filter { $0.goalID == goalID && !$0.meta.isDeleted }
            guard let g = s.goals.firstIndex(where: { $0.meta.id == goalID }) else { return }
            let allDone = !steps.isEmpty && steps.allSatisfy { $0.isDone }
            if allDone && s.goals[g].state == .active {
                s.goals[g].state = .done
                s.goals[g].completedAt = Date()
                s.goals[g].meta.updatedAt = Date()
            } else if !allDone && s.goals[g].state == .done {
                s.goals[g].state = .active
                s.goals[g].completedAt = nil
                s.goals[g].meta.updatedAt = Date()
            }
        }
    }

    func addReturned(sourceID: UUID?) {
        let rec = AchievementRecord(meta: meta(), type: .returnedToActivity, earnedAt: Date(), sourceID: sourceID)
        mutate { s in
            let exists = s.achievements.contains { !$0.meta.isDeleted && $0.type == .returnedToActivity && $0.sourceID == sourceID && sourceID != nil }
            if !exists { s.achievements.append(rec) }
        }
    }

    @discardableResult
    func addLetter(body: String, unlockAt: Date) -> UUID {
        let rec = FutureLetterRecord(meta: meta(), body: body, unlockAt: unlockAt)
        mutate { $0.letters.append(rec) }
        return rec.meta.id
    }

    // MARK: Резервная копия

    func backupData() throws -> Data {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return try BackupCodec.encode(BackupFile(exportedAt: Date(), appVersion: version, data: snapshot))
    }

    func previewImport(_ data: Data) throws -> (merged: Snapshot, summary: ImportSummary) {
        let file = try BackupCodec.decode(data)
        return BackupMerger.merge(current: snapshot, incoming: file.data)
    }

    func applyImport(_ merged: Snapshot) {
        var s = merged
        AppStore.normalize(&s)
        apply(s)
    }

    /// Полное удаление всех данных. Встроенные практики создаются заново.
    func wipe() {
        saveTask?.cancel()
        AppStore.removeExportFiles()
        AppStore.removeFiles(in: fileURL.deletingLastPathComponent(), prefix: "mellow-broken-")
        var s = Snapshot()
        AppStore.normalize(&s)
        level = 3
        apply(s)
    }

    // MARK: Файл

    /// Временные файлы экспорта: удаляются после закрытия листа экспорта, при запуске и при удалении всех данных.
    static func removeExportFiles() {
        let tmp = FileManager.default.temporaryDirectory
        removeFiles(in: tmp, prefix: "mellow-backup-")
        removeFiles(in: tmp, prefix: "mellow-report-", suffix: ".pdf")
    }

    private static func removeFiles(in dir: URL, prefix: String, suffix: String = ".json") {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(suffix) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private static func load(from url: URL) -> Snapshot {
        guard let data = try? Data(contentsOf: url) else { return Snapshot() }
        if let file = try? BackupCodec.decode(data) { return file.data }
        // Файл не читается: не затираем его, а откладываем в сторону.
        let aside = url.deletingLastPathComponent().appendingPathComponent("mellow-broken-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return Snapshot()
    }

    private func scheduleSave() {
        guard !isDemo else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Запись на диск: атомарно, через временный файл.
    func saveNow() {
        guard !isDemo else { return }
        saveTask?.cancel()
        do {
            let data = try backupData()
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Mellow: не удалось сохранить данные: \(error)")
        }
    }

    // MARK: Приведение снимка в порядок

    private static func thresholds(in a: Snapshot) -> DayThresholds {
        (MergeRules.dedupeSettings(a.settings).kept.first?.thresholds ?? DayThresholds.default).normalized
    }

    /// Встроенные практики, настройки, дубли, брошенные сессии.
    private static func normalize(_ s: inout Snapshot) {
        let now = Date()
        // Сессия, которая «ещё идёт» после перезапуска, была прервана.
        for i in s.sessions.indices where s.sessions[i].status == .running {
            s.sessions[i].status = .interrupted
            s.sessions[i].meta.updatedAt = now
        }
        // Дубли встроенных практик после импорта.
        let removed = Set(MergeRules.dedupeBuiltInPractices(s.practices.filter { !$0.meta.isDeleted }).removedIDs)
        for i in s.practices.indices where removed.contains(s.practices[i].meta.id) {
            s.practices[i].meta.deletedAt = now
            s.practices[i].meta.updatedAt = now
        }
        for type in PracticeType.allCases {
            let exists = s.practices.contains { !$0.meta.isDeleted && $0.isBuiltIn && $0.type == type }
            if exists { continue }
            let info = type.info
            var settings = PracticeSettings()
            settings.pattern = type.defaultPattern
            s.practices.append(PracticeDefinitionRecord(meta: RecordMeta(createdAt: now), type: type, title: info.title,
                                                        settings: settings, isBuiltIn: true, sortOrder: info.sortOrder))
        }
        if !s.settings.contains(where: { !$0.meta.isDeleted }) {
            s.settings.append(SettingsRecord(meta: RecordMeta(createdAt: now), theme: eveningTheme))
        }
    }

    /// Автоматические достижения — за действия, не за отсутствие тревоги.
    private static func award(_ s: inout Snapshot) {
        let a = s.active()
        var have = Set<String>()
        for x in a.achievements {
            have.insert(x.type.rawValue + "|" + (x.type.isRepeatable ? (x.sourceID?.uuidString ?? "") : ""))
        }
        let now = Date()
        func give(_ type: AchievementType, _ source: UUID? = nil) {
            let key = type.rawValue + "|" + (type.isRepeatable ? (source?.uuidString ?? "") : "")
            guard !have.contains(key) else { return }
            have.insert(key)
            s.achievements.append(AchievementRecord(meta: RecordMeta(createdAt: now), type: type, earnedAt: now, sourceID: source))
        }
        if !a.checkIns.isEmpty { give(.firstCheckIn) }
        if !a.episodes.isEmpty { give(.firstEpisode) }
        if !a.histories.isEmpty { give(.firstHistory) }
        if !a.insights.isEmpty { give(.firstInsight) }
        if !a.conversations.isEmpty { give(.firstConversation) }
        if !a.dayReflections.isEmpty { give(.firstDayReflection) }
        if !a.letters.isEmpty { give(.firstLetter) }
        if a.goals.contains(where: { $0.state == .done }) { give(.firstGoalDone) }
        let done = a.sessions.filter { $0.status == .completed || $0.status == .endedEarly }.sorted { $0.startedAt < $1.startedAt }
        if let first = done.first {
            give(.firstPractice)
            var seen = Set<UUID>([first.practiceID])
            for x in done where !seen.contains(x.practiceID) {
                seen.insert(x.practiceID)
                give(.triedNewPractice, x.practiceID)
            }
        }
        for h in a.histories where h.status == .resolved { give(.historyResolved, h.meta.id) }
    }
}
