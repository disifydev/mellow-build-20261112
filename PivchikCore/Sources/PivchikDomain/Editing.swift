import Foundation

// MARK: Надгробия

/// Запись, от которой после удаления можно оставить «надгробие»: id, даты и пометку удаления.
/// Весь текст пользователя стирается; надгробие нужно, чтобы импорт старой копии не вернул запись.
public protocol Tombstonable: Record, Equatable {
    func tombstoned() -> Self
}

extension CheckInRecord: Tombstonable {
    public func tombstoned() -> CheckInRecord {
        CheckInRecord(meta: meta, observedAt: meta.createdAt, zoneID: "", anxiety: 0)
    }
}

extension EpisodeRecord: Tombstonable {
    public func tombstoned() -> EpisodeRecord {
        EpisodeRecord(meta: meta, startedAt: meta.createdAt, zoneID: "")
    }
}

extension DayReflectionRecord: Tombstonable {
    public func tombstoned() -> DayReflectionRecord {
        DayReflectionRecord(meta: meta, localDate: "", zoneID: "")
    }
}

extension HistoryRecord: Tombstonable {
    public func tombstoned() -> HistoryRecord {
        HistoryRecord(meta: meta, title: "", startedAt: meta.createdAt, status: .archived)
    }
}

extension StatusChangeRecord: Tombstonable {
    public func tombstoned() -> StatusChangeRecord {
        StatusChangeRecord(meta: meta, historyID: historyID, fromStatus: .active, toStatus: .active, changedAt: meta.createdAt)
    }
}

extension ConversationRecord: Tombstonable {
    public func tombstoned() -> ConversationRecord {
        ConversationRecord(meta: meta, occurredAt: meta.createdAt, zoneID: "")
    }
}

extension PracticeDefinitionRecord: Tombstonable {
    public func tombstoned() -> PracticeDefinitionRecord {
        PracticeDefinitionRecord(meta: meta, type: type, title: "", isBuiltIn: isBuiltIn, sortOrder: sortOrder)
    }
}

extension PracticeSessionRecord: Tombstonable {
    public func tombstoned() -> PracticeSessionRecord {
        PracticeSessionRecord(meta: meta, practiceID: practiceID, practiceType: practiceType, startedAt: meta.createdAt, zoneID: "",
                              status: .interrupted)
    }
}

extension InsightRecord: Tombstonable {
    public func tombstoned() -> InsightRecord {
        InsightRecord(meta: meta, text: "")
    }
}

extension GoalRecord: Tombstonable {
    public func tombstoned() -> GoalRecord {
        GoalRecord(meta: meta, title: "", state: .dropped)
    }
}

extension GoalStepRecord: Tombstonable {
    public func tombstoned() -> GoalStepRecord {
        GoalStepRecord(meta: meta, goalID: goalID, title: "")
    }
}

extension SmallWinRecord: Tombstonable {
    public func tombstoned() -> SmallWinRecord {
        SmallWinRecord(meta: meta, text: "", occurredAt: meta.createdAt, zoneID: "")
    }
}

extension AchievementRecord: Tombstonable {
    public func tombstoned() -> AchievementRecord {
        AchievementRecord(meta: meta, type: type, earnedAt: meta.createdAt)
    }
}

extension FutureLetterRecord: Tombstonable {
    public func tombstoned() -> FutureLetterRecord {
        FutureLetterRecord(meta: meta, body: "", unlockAt: meta.createdAt)
    }
}

extension SettingsRecord: Tombstonable {
    public func tombstoned() -> SettingsRecord {
        SettingsRecord(meta: meta)
    }
}

// MARK: Обход всех списков снимка

/// Посетитель всех пятнадцати списков снимка — чтобы общие правила не повторять для каждого вида записей.
public protocol SnapshotVisitor {
    mutating func visit<R: Tombstonable>(_ list: inout [R])
}

public extension Snapshot {
    mutating func visitAll<V: SnapshotVisitor>(_ v: inout V) {
        v.visit(&checkIns); v.visit(&episodes); v.visit(&dayReflections); v.visit(&histories); v.visit(&statusChanges)
        v.visit(&conversations); v.visit(&practices); v.visit(&sessions); v.visit(&insights); v.visit(&goals)
        v.visit(&goalSteps); v.visit(&smallWins); v.visit(&achievements); v.visit(&letters); v.visit(&settings)
    }

    /// Все идентификаторы записей (включая удалённые).
    var allIDs: Set<UUID> {
        struct Collect: SnapshotVisitor {
            var ids = Set<UUID>()
            mutating func visit<R: Tombstonable>(_ list: inout [R]) { for r in list { ids.insert(r.id) } }
        }
        var c = Collect()
        var copy = self
        copy.visitAll(&c)
        return c.ids
    }

    /// Удалённые записи превращаются в надгробия. `ids == nil` — все удалённые.
    func purgingDeleted(ids: Set<UUID>? = nil) -> Snapshot {
        struct Purge: SnapshotVisitor {
            let ids: Set<UUID>?
            mutating func visit<R: Tombstonable>(_ list: inout [R]) {
                for i in list.indices where list[i].meta.isDeleted && (ids?.contains(list[i].id) ?? true) {
                    list[i] = list[i].tombstoned()
                }
            }
        }
        var s = self
        var p = Purge(ids: ids)
        s.visitAll(&p)
        return s
    }

    /// Отмена: записи с указанными id возвращаются в состояние из `previous`.
    /// Записи, которых в `previous` не было, убираются (их создало отменяемое действие).
    func restoring(_ ids: Set<UUID>, from previous: Snapshot) -> Snapshot {
        struct Restore: SnapshotVisitor {
            let ids: Set<UUID>
            let old: [UUID: Any]
            mutating func visit<R: Tombstonable>(_ list: inout [R]) {
                list = list.compactMap { r in
                    guard ids.contains(r.id) else { return r }
                    return old[r.id] as? R
                }
            }
        }
        struct Index: SnapshotVisitor {
            let ids: Set<UUID>
            var old: [UUID: Any] = [:]
            mutating func visit<R: Tombstonable>(_ list: inout [R]) {
                for r in list where ids.contains(r.id) { old[r.id] = r }
            }
        }
        var prev = previous
        var index = Index(ids: ids)
        prev.visitAll(&index)
        var s = self
        var r = Restore(ids: ids, old: index.old)
        s.visitAll(&r)
        return s
    }
}

// MARK: Удаление

public enum Deletion {
    /// Мягкое удаление с каскадом: выводы эпизода или разговора, победа итога дня, этапы цели.
    /// Возвращает новый снимок и все затронутые id (для отмены).
    public static func delete(_ ids: Set<UUID>, in snapshot: Snapshot, now: Date) -> (snapshot: Snapshot, affected: Set<UUID>) {
        var s = snapshot
        var all = ids
        for x in s.insights where !x.meta.isDeleted { if let src = x.sourceID, ids.contains(src) { all.insert(x.id) } }
        for w in s.smallWins where !w.meta.isDeleted { if let r = w.dayReflectionID, ids.contains(r) { all.insert(w.id) } }
        for st in s.goalSteps where !st.meta.isDeleted && ids.contains(st.goalID) { all.insert(st.id) }
        struct Mark: SnapshotVisitor {
            let ids: Set<UUID>
            let now: Date
            var affected = Set<UUID>()
            mutating func visit<R: Tombstonable>(_ list: inout [R]) {
                for i in list.indices where ids.contains(list[i].id) && !list[i].meta.isDeleted {
                    list[i].meta.deletedAt = now
                    list[i].meta.updatedAt = now
                    affected.insert(list[i].id)
                }
            }
        }
        var m = Mark(ids: all, now: now)
        s.visitAll(&m)
        return (s, m.affected)
    }

    /// Удаление истории. `withRecords == false`: записи остаются, связи с историей убираются, цели становятся общими.
    /// `withRecords == true`: удаляются и все записи, привязанные к истории (с каскадом).
    public static func deleteHistory(_ historyID: UUID, withRecords: Bool, in snapshot: Snapshot, now: Date)
        -> (snapshot: Snapshot, affected: Set<UUID>) {
        var ids: Set<UUID> = [historyID]
        for c in snapshot.statusChanges where c.historyID == historyID { ids.insert(c.id) }
        if withRecords {
            for x in snapshot.checkIns where x.historyIDs.contains(historyID) { ids.insert(x.id) }
            for x in snapshot.episodes where x.historyIDs.contains(historyID) { ids.insert(x.id) }
            for x in snapshot.conversations where x.historyIDs.contains(historyID) { ids.insert(x.id) }
            for x in snapshot.sessions where x.historyIDs.contains(historyID) { ids.insert(x.id) }
            for x in snapshot.insights where x.historyIDs.contains(historyID) { ids.insert(x.id) }
            for x in snapshot.smallWins where x.historyIDs.contains(historyID) { ids.insert(x.id) }
            for x in snapshot.goals where x.historyID == historyID { ids.insert(x.id) }
            return delete(ids, in: snapshot, now: now)
        }
        var (s, affected) = delete(ids, in: snapshot, now: now)
        func unlink<R: Record>(_ list: inout [R], _ links: WritableKeyPath<R, [UUID]>) {
            for i in list.indices where !list[i].meta.isDeleted && list[i][keyPath: links].contains(historyID) {
                list[i][keyPath: links].removeAll { $0 == historyID }
                list[i].meta.updatedAt = now
                affected.insert(list[i].id)
            }
        }
        unlink(&s.checkIns, \.historyIDs)
        unlink(&s.episodes, \.historyIDs)
        unlink(&s.conversations, \.historyIDs)
        unlink(&s.sessions, \.historyIDs)
        unlink(&s.insights, \.historyIDs)
        unlink(&s.smallWins, \.historyIDs)
        for i in s.goals.indices where !s.goals[i].meta.isDeleted && s.goals[i].historyID == historyID {
            s.goals[i].historyID = nil
            s.goals[i].meta.updatedAt = now
            affected.insert(s.goals[i].id)
        }
        return (s, affected)
    }
}

// MARK: Итог дня: перенос на другой день

public enum ReflectionMove {
    public enum Resolution: Sendable { case replace, merge }

    /// Итог, который уже есть в целевом дне (кроме переносимого).
    public static func conflict(moving id: UUID, to day: LocalDay, in snapshot: Snapshot) -> DayReflectionRecord? {
        snapshot.dayReflections.first { !$0.meta.isDeleted && $0.id != id && $0.localDate == day.description }
    }

    /// Склейка двух текстов: без пустых и без повторов.
    public static func mergeText(_ a: String?, _ b: String?) -> String? {
        let parts = [a, b].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var out: [String] = []
        for p in parts where !out.contains(p) { out.append(p) }
        return out.isEmpty ? nil : out.joined(separator: "\n")
    }

    /// Переносит итог на другой день. При конфликте: `replace` — старый итог дня удаляется,
    /// `merge` — тексты переносимого добавляются к итогу целевого дня, а переносимый удаляется.
    /// Победа, созданная из итога, переезжает вместе с ним. `winDate` — новый момент для этой победы.
    public static func move(_ id: UUID, to day: LocalDay, resolution: Resolution, winDate: Date, in snapshot: Snapshot, now: Date)
        -> (snapshot: Snapshot, affected: Set<UUID>) {
        guard let i = snapshot.dayReflections.firstIndex(where: { $0.id == id && !$0.meta.isDeleted }) else { return (snapshot, []) }
        var s = snapshot
        var affected: Set<UUID> = []
        let target = conflict(moving: id, to: day, in: s)
        func moveWins(from source: UUID, to dest: UUID) {
            for w in s.smallWins.indices where !s.smallWins[w].meta.isDeleted && s.smallWins[w].dayReflectionID == source {
                s.smallWins[w].dayReflectionID = dest
                s.smallWins[w].occurredAt = winDate
                s.smallWins[w].meta.updatedAt = now
                affected.insert(s.smallWins[w].id)
            }
        }
        if let target, resolution == .merge, let t = s.dayReflections.firstIndex(where: { $0.id == target.id }) {
            let src = s.dayReflections[i]
            s.dayReflections[t].overallAnxiety = src.overallAnxiety ?? s.dayReflections[t].overallAnxiety
            s.dayReflections[t].helped = mergeText(s.dayReflections[t].helped, src.helped)
            s.dayReflections[t].hard = mergeText(s.dayReflections[t].hard, src.hard)
            s.dayReflections[t].victory = mergeText(s.dayReflections[t].victory, src.victory)
            s.dayReflections[t].summary = mergeText(s.dayReflections[t].summary, src.summary)
            s.dayReflections[t].meta.updatedAt = now
            s.dayReflections[t].meta.editedAt = now
            affected.insert(target.id)
            // Победа целевого дня остаётся одна: её текст — объединённая победа.
            if let tw = s.smallWins.firstIndex(where: { !$0.meta.isDeleted && $0.dayReflectionID == target.id }) {
                if let text = s.dayReflections[t].victory {
                    s.smallWins[tw].text = text
                    s.smallWins[tw].meta.updatedAt = now
                    affected.insert(s.smallWins[tw].id)
                }
                // Победа переносимого итога удалится каскадом вместе с ним.
            } else {
                moveWins(from: id, to: target.id)
                for w in s.smallWins.indices where !s.smallWins[w].meta.isDeleted && s.smallWins[w].dayReflectionID == target.id {
                    if let text = s.dayReflections[t].victory { s.smallWins[w].text = text }
                }
            }
            let (d, a) = Deletion.delete([id], in: s, now: now)
            return (d, affected.union(a))
        }
        if let target {
            let (d, a) = Deletion.delete([target.id], in: s, now: now)
            s = d
            affected.formUnion(a)
        }
        s.dayReflections[i].localDate = day.description
        s.dayReflections[i].meta.updatedAt = now
        s.dayReflections[i].meta.editedAt = now
        affected.insert(id)
        moveWins(from: id, to: id)
        return (s, affected)
    }
}

// MARK: Время по умолчанию для записи задним числом

public enum DefaultTime {
    /// Момент внутри выбранного дня: текущее время суток, перенесённое в этот день, но не позже `now`.
    /// Для будущего дня — `now`.
    public static func inDay(_ day: LocalDay, zoneID: String, now: Date) -> Date {
        let today = LocalDay(date: now, zoneID: zoneID)
        if day >= today { return now }
        let cal = LocalDay.calendar(zoneID: zoneID)
        let c = cal.dateComponents([.hour, .minute], from: now)
        let start = day.startDate(zoneID: zoneID)
        let candidate = cal.date(bySettingHour: c.hour ?? 12, minute: c.minute ?? 0, second: 0, of: start) ?? start
        // Если в этот день нет такого времени (перевод часов) — последняя минута дня.
        guard LocalDay(date: candidate, zoneID: zoneID) == day else {
            return day.adding(days: 1).startDate(zoneID: zoneID).addingTimeInterval(-60)
        }
        return min(candidate, now)
    }

    /// Дату нельзя ставить в будущее.
    public static func clampToNow(_ date: Date, now: Date) -> Date { min(date, now) }
}
