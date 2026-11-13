import Foundation
import PivchikDomain

/// Плашка «Удалено · Отменить».
struct UndoToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// Удаление, которое ещё можно отменить: прежний снимок и все затронутые записи.
struct PendingUndo {
    let previous: Snapshot
    let affected: Set<UUID>
}

/// Черновик эпизода: что было введено до закрытия листа без сохранения.
struct EpisodeDraft: Codable, Equatable {
    var peak: Int
    var start: Date
    var ongoing: Bool
    var end: Date
    var cause: String
    var thoughts: String
    var symptoms: [String]
    var stories: [UUID]
    var tags: [String]
    var customTag: String
    var coping: String
    var insight: String
}

/// Правка, перенос и удаление записей. Удаление сначала мягкое (можно отменить 5 секунд),
/// потом от записи остаётся только надгробие без текста.
extension AppStore {
    /// Сколько секунд держится «Отменить». Для снимка экрана с плашкой — дольше.
    static var undoSeconds: Double { Launch.screen == "diary-undo" ? 600 : 5 }

    // MARK: Удаление с отменой

    func delete(_ ids: Set<UUID>, label: String? = nil) {
        guard !ids.isEmpty else { return }
        commitPendingDelete()
        let before = snapshot
        let (d, affected) = Deletion.delete(ids, in: before, now: Date())
        finishDelete(d, before: before, affected: affected, count: ids.count, label: label)
    }

    private func finishDelete(_ new: Snapshot, before: Snapshot, affected: Set<UUID>, count: Int, label: String?) {
        guard !affected.isEmpty else { return }
        apply(new)
        pendingUndo = PendingUndo(previous: before, affected: affected)
        toast = UndoToast(text: label ?? (count > 1 ? "Удалено: \(count)" : "Удалено"))
        Haptics.tick(settings.hapticsEnabled)
        purgeTask?.cancel()
        let seconds = AppStore.undoSeconds
        purgeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.commitPendingDelete()
        }
    }

    /// «Отменить»: записи возвращаются целиком, со всеми связями.
    func undoDelete() {
        guard let p = pendingUndo else { return }
        purgeTask?.cancel()
        pendingUndo = nil
        toast = nil
        apply(snapshot.restoring(p.affected, from: p.previous))
    }

    /// Время отмены вышло: от удалённых записей остаются надгробия, напоминания писем снимаются.
    func commitPendingDelete() {
        purgeTask?.cancel()
        toast = nil
        guard let p = pendingUndo else { return }
        pendingUndo = nil
        let letters = snapshot.letters.filter { p.affected.contains($0.meta.id) && $0.meta.isDeleted }.map { $0.meta.id }
        if !isDemo { Notifier.cancelLetters(ids: letters) }
        apply(snapshot.purgingDeleted(ids: p.affected))
    }

    /// Приложение ушло в фон: отмена больше недоступна, всё сохраняется.
    func enterBackground() {
        commitPendingDelete()
        saveNow()
    }

    // MARK: Правка

    /// Правка пользователем: обновляет `updatedAt` и `editedAt` (подпись «изменено»).
    func edit<R: Record>(_ keyPath: WritableKeyPath<Snapshot, [R]>, id: UUID, _ change: (inout R) -> Void) {
        let now = Date()
        mutate { s in
            guard let i = s[keyPath: keyPath].firstIndex(where: { $0.meta.id == id && !$0.meta.isDeleted }) else { return }
            change(&s[keyPath: keyPath][i])
            s[keyPath: keyPath][i].meta.updatedAt = now
            s[keyPath: keyPath][i].meta.editedAt = now
        }
    }

    func updateCheckIn(id: UUID, anxiety: Int, note: String, date: Date, tags: [String], historyIDs: [UUID]) {
        let at = DefaultTime.clampToNow(date, now: Date())
        let zoneID = zone
        edit(\Snapshot.checkIns, id: id) { c in
            if c.observedAt != at { c.zoneID = zoneID }
            c.anxiety = AnxietyScale.clamp(anxiety)
            c.note = note.nilIfEmpty
            c.observedAt = at
            c.tags = tags
            c.historyIDs = historyIDs
            c.isRetrospective = RetrospectiveRule.isRetrospective(eventAt: at, createdAt: c.meta.createdAt)
        }
    }

    func updateEpisode(_ rec: EpisodeRecord) {
        let now = Date()
        let zoneID = zone
        mutate { s in
            guard let i = s.episodes.firstIndex(where: { $0.meta.id == rec.meta.id && !$0.meta.isDeleted }) else { return }
            let old = s.episodes[i]
            var r = rec
            r.meta = old.meta
            r.meta.updatedAt = now
            r.meta.editedAt = now
            r.startedAt = min(r.startedAt, now)
            if let end = r.endedAt { r.endedAt = min(max(end, r.startedAt), now) }
            r.zoneID = r.startedAt == old.startedAt ? old.zoneID : zoneID
            r.isRetrospective = RetrospectiveRule.isRetrospective(eventAt: r.startedAt, createdAt: r.meta.createdAt)
            s.episodes[i] = r
            AppStore.syncInsight(&s, text: r.insights, historyIDs: r.historyIDs, kind: .episode, source: r.meta.id, now: now)
        }
    }

    func updateConversation(_ rec: ConversationRecord) {
        let now = Date()
        let zoneID = zone
        mutate { s in
            guard let i = s.conversations.firstIndex(where: { $0.meta.id == rec.meta.id && !$0.meta.isDeleted }) else { return }
            let old = s.conversations[i]
            var r = rec
            r.meta = old.meta
            r.meta.updatedAt = now
            r.meta.editedAt = now
            r.occurredAt = min(r.occurredAt, now)
            r.zoneID = r.occurredAt == old.occurredAt ? old.zoneID : zoneID
            r.episodeIDs = old.episodeIDs
            r.isRetrospective = RetrospectiveRule.isRetrospective(eventAt: r.occurredAt, createdAt: r.meta.createdAt)
            s.conversations[i] = r
            AppStore.syncInsight(&s, text: r.insights, historyIDs: r.historyIDs, kind: .conversation, source: r.meta.id, now: now)
        }
    }

    /// Вывод эпизода или разговора живёт отдельной записью в «Открытиях» — правится вместе с источником.
    private static func syncInsight(_ s: inout Snapshot, text: String?, historyIDs: [UUID], kind: InsightSourceKind, source: UUID, now: Date) {
        let idx = s.insights.firstIndex { !$0.meta.isDeleted && $0.sourceID == source }
        if let t = text?.nilIfEmpty {
            if let i = idx {
                guard s.insights[i].text != t || s.insights[i].historyIDs != historyIDs else { return }
                s.insights[i].text = t
                s.insights[i].historyIDs = historyIDs
                s.insights[i].meta.updatedAt = now
                s.insights[i].meta.editedAt = now
            } else {
                s.insights.append(InsightRecord(meta: RecordMeta(createdAt: now), text: t, historyIDs: historyIDs, sourceKind: kind, sourceID: source))
            }
        } else if let i = idx {
            s.insights[i].meta.deletedAt = now
            s.insights[i].meta.updatedAt = now
            s.insights[i] = s.insights[i].tombstoned()
        }
    }

    /// Сессия практики: оценки до и после, ощущение, заметка, время, истории. Конец сдвигается вместе с началом.
    func updateSession(id: UUID, before: Int?, after: Int?, felt: FeltResult?, notes: String, start: Date, historyIDs: [UUID]) {
        let at = DefaultTime.clampToNow(start, now: Date())
        let zoneID = zone
        edit(\Snapshot.sessions, id: id) { x in
            let shift = at.timeIntervalSince(x.startedAt)
            if shift != 0 { x.zoneID = zoneID }
            x.startedAt = at
            x.endedAt = x.endedAt.map { $0.addingTimeInterval(shift) }
            x.before = before
            x.after = after
            x.feltResult = felt
            x.notes = notes.nilIfEmpty
            x.historyIDs = historyIDs
            x.isRetrospective = RetrospectiveRule.isRetrospective(eventAt: at, createdAt: x.meta.createdAt)
        }
    }

    /// Победа. Если она пришла из итога дня — текст итога обновляется тоже.
    func updateWin(id: UUID, text: String, date: Date, historyIDs: [UUID]) {
        guard let t = text.nilIfEmpty else { return }
        let at = DefaultTime.clampToNow(date, now: Date())
        let now = Date()
        let zoneID = zone
        mutate { s in
            guard let i = s.smallWins.firstIndex(where: { $0.meta.id == id && !$0.meta.isDeleted }) else { return }
            if s.smallWins[i].occurredAt != at { s.smallWins[i].zoneID = zoneID }
            s.smallWins[i].text = t
            s.smallWins[i].occurredAt = at
            s.smallWins[i].historyIDs = historyIDs
            s.smallWins[i].isRetrospective = RetrospectiveRule.isRetrospective(eventAt: at, createdAt: s.smallWins[i].meta.createdAt)
            s.smallWins[i].meta.updatedAt = now
            s.smallWins[i].meta.editedAt = now
            if let rid = s.smallWins[i].dayReflectionID, let r = s.dayReflections.firstIndex(where: { $0.meta.id == rid && !$0.meta.isDeleted }) {
                s.dayReflections[r].victory = t
                s.dayReflections[r].meta.updatedAt = now
            }
        }
    }

    // MARK: Итог дня

    /// Итог, который уже есть в другом дне (конфликт при переносе).
    func reflectionConflict(moving id: UUID, to day: LocalDay) -> DayReflectionRecord? {
        ReflectionMove.conflict(moving: id, to: day, in: snapshot)
    }

    func moveReflection(_ id: UUID, to day: LocalDay, resolution: ReflectionMove.Resolution) {
        let now = Date()
        let winDate = day == today ? now : day.noon
        let (s, _) = ReflectionMove.move(id, to: day, resolution: resolution, winDate: winDate, in: snapshot, now: now)
        apply(s)
    }

    // MARK: Истории

    func updateHistory(id: UUID, title: String, details: String, startedAt: Date) {
        guard let t = title.nilIfEmpty else { return }
        edit(\Snapshot.histories, id: id) { h in
            h.title = t
            h.details = details.nilIfEmpty
            h.startedAt = min(startedAt, Date())
        }
    }

    func deleteHistory(_ id: UUID, withRecords: Bool) {
        commitPendingDelete()
        let before = snapshot
        let (d, affected) = Deletion.deleteHistory(id, withRecords: withRecords, in: before, now: Date())
        finishDelete(d, before: before, affected: affected, count: 1,
                     label: withRecords ? "История и записи удалены" : "История удалена")
    }

    // MARK: Цели и этапы

    func renameGoal(_ id: UUID, title: String) {
        guard let t = title.nilIfEmpty else { return }
        edit(\Snapshot.goals, id: id) { $0.title = t }
    }

    func renameStep(_ id: UUID, title: String) {
        guard let t = title.nilIfEmpty else { return }
        edit(\Snapshot.goalSteps, id: id) { $0.title = t }
    }

    /// Удаление этапа: состояние цели пересчитывается (могли остаться только выполненные этапы).
    func deleteStep(_ id: UUID) {
        guard let goalID = snapshot.goalSteps.first(where: { $0.meta.id == id })?.goalID else { return }
        commitPendingDelete()
        let before = snapshot
        var (d, affected) = Deletion.delete([id], in: before, now: Date())
        if AppStore.recomputeGoal(&d, goalID: goalID, now: Date()) { affected.insert(goalID) }
        finishDelete(d, before: before, affected: affected, count: 1, label: "Этап удалён")
    }

    /// Этап выше или ниже: порядок перенумеровывается без пропусков.
    func moveStep(_ id: UUID, by offset: Int) {
        let now = Date()
        mutate { s in
            guard let goalID = s.goalSteps.first(where: { $0.meta.id == id })?.goalID else { return }
            var ordered = s.goalSteps.filter { $0.goalID == goalID && !$0.meta.isDeleted }.sorted { ($0.order, $0.meta.createdAt) < ($1.order, $1.meta.createdAt) }.map { $0.meta.id }
            guard let from = ordered.firstIndex(of: id) else { return }
            let to = min(max(0, from + offset), ordered.count - 1)
            guard to != from else { return }
            ordered.remove(at: from)
            ordered.insert(id, at: to)
            for (n, sid) in ordered.enumerated() {
                guard let i = s.goalSteps.firstIndex(where: { $0.meta.id == sid }), s.goalSteps[i].order != n else { continue }
                s.goalSteps[i].order = n
                s.goalSteps[i].meta.updatedAt = now
            }
        }
    }

    /// Цель выполнена, когда выполнены все её этапы. Возвращает true, если состояние изменилось.
    @discardableResult
    static func recomputeGoal(_ s: inout Snapshot, goalID: UUID, now: Date) -> Bool {
        let steps = s.goalSteps.filter { $0.goalID == goalID && !$0.meta.isDeleted }
        guard let g = s.goals.firstIndex(where: { $0.meta.id == goalID }) else { return false }
        let allDone = !steps.isEmpty && steps.allSatisfy { $0.isDone }
        if allDone && s.goals[g].state == .active {
            s.goals[g].state = .done
            s.goals[g].completedAt = now
            s.goals[g].meta.updatedAt = now
            return true
        } else if !allDone && s.goals[g].state == .done {
            s.goals[g].state = .active
            s.goals[g].completedAt = nil
            s.goals[g].meta.updatedAt = now
            return true
        }
        return false
    }

    // MARK: Письма

    /// Текст и дату можно менять, пока письмо не открыто. Напоминание переносится, если было включено.
    func updateLetter(_ id: UUID, body: String, unlockAt: Date) {
        guard let b = body.nilIfEmpty, let letter = active.letters.first(where: { $0.meta.id == id }), letter.openedAt == nil else { return }
        edit(\Snapshot.letters, id: id) { l in
            l.body = b
            l.unlockAt = unlockAt
        }
        if !isDemo && letter.unlockAt != unlockAt { Notifier.rescheduleLetterIfPending(id: id, at: unlockAt) }
    }

    /// Варианты тегов для форм: базовые и все уже использованные.
    func tagOptions(including extra: Set<String>) -> [String] {
        var all = ["связь", "вечер", "работа", "дорога"]
        let used = active.episodes.flatMap { $0.tags } + active.checkIns.flatMap { $0.tags }
        for t in used + extra.sorted() where !all.contains(t) { all.append(t) }
        return all
    }

    /// Выбранные теги плюс свой тег из поля.
    static func tags(_ selected: Set<String>, custom: String) -> [String] {
        var out = Array(selected).sorted()
        if let t = custom.replacingOccurrences(of: "#", with: "").nilIfEmpty, !out.contains(t) { out.append(t) }
        return out
    }

    // MARK: Черновик эпизода

    private var draftURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("mellow-episode-draft.json")
    }

    func loadEpisodeDraft() {
        guard !isDemo, let data = try? Data(contentsOf: draftURL) else { return }
        episodeDraft = try? JSONDecoder().decode(EpisodeDraft.self, from: data)
    }

    func saveEpisodeDraft(_ draft: EpisodeDraft) {
        episodeDraft = draft
        guard !isDemo, let data = try? JSONEncoder().encode(draft) else { return }
        try? FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: draftURL, options: [.atomic, .completeFileProtection])
    }

    func discardEpisodeDraft() {
        episodeDraft = nil
        try? FileManager.default.removeItem(at: draftURL)
    }
}
