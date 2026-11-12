import Foundation

/// Измерение — любая добровольная оценка 0…10 с моментом времени (§7).
public struct AnxietyMeasurement: Sendable, Hashable {
    public enum Source: String, Sendable, Hashable {
        case checkIn, episodePeak, practiceBefore, practiceAfter, conversationBefore, conversationAfter
    }

    public let date: Date
    public let zoneID: String
    public let value: Int
    public let source: Source
    public let sourceID: UUID
    public let isRetrospective: Bool
    public let dayPart: DayPart?
    public let tags: [String]
    public let historyIDs: [UUID]

    public var day: LocalDay { LocalDay(date: date, zoneID: zoneID) }

    /// Время суток: пометка пользователя либо по часу записи (утро 5–11, день 12–17, вечер — остальное).
    public var effectiveDayPart: DayPart {
        if let dayPart { return dayPart }
        let hour = LocalDay.calendar(zoneID: zoneID).component(.hour, from: date)
        switch hour {
        case 5..<12: return .morning
        case 12..<18: return .day
        default: return .evening
        }
    }
}

public enum MeasurementCollector {
    /// Собирает измерения из снимка. Удалённые записи пропускаются.
    /// Оценки разговора не учитываются, если к нему привязана практика со своими оценками, —
    /// чтобы одно и то же состояние не считалось дважды.
    public static func collect(from snapshot: Snapshot) -> [AnxietyMeasurement] {
        var out: [AnxietyMeasurement] = []

        for c in snapshot.checkIns where !c.meta.isDeleted && AnxietyScale.isValid(c.anxiety) {
            out.append(AnxietyMeasurement(date: c.observedAt, zoneID: c.zoneID, value: c.anxiety, source: .checkIn, sourceID: c.id,
                                   isRetrospective: c.isRetrospective, dayPart: c.dayPart, tags: c.tags, historyIDs: c.historyIDs))
        }

        for e in snapshot.episodes where !e.meta.isDeleted {
            guard let peak = e.peak, AnxietyScale.isValid(peak) else { continue }
            out.append(AnxietyMeasurement(date: e.startedAt, zoneID: e.zoneID, value: peak, source: .episodePeak, sourceID: e.id,
                                   isRetrospective: e.isRetrospective, dayPart: nil, tags: e.tags, historyIDs: e.historyIDs))
        }

        var conversationsRatedByPractice = Set<UUID>()
        for s in snapshot.sessions where !s.meta.isDeleted {
            if let cid = s.conversationID, s.before != nil || s.after != nil { conversationsRatedByPractice.insert(cid) }
            if let before = s.before, AnxietyScale.isValid(before) {
                out.append(AnxietyMeasurement(date: s.startedAt, zoneID: s.zoneID, value: before, source: .practiceBefore, sourceID: s.id,
                                       isRetrospective: s.isRetrospective, dayPart: nil, tags: [], historyIDs: s.historyIDs))
            }
            if let after = s.after, AnxietyScale.isValid(after) {
                out.append(AnxietyMeasurement(date: s.endedAt ?? s.startedAt, zoneID: s.zoneID, value: after, source: .practiceAfter, sourceID: s.id,
                                       isRetrospective: s.isRetrospective, dayPart: nil, tags: [], historyIDs: s.historyIDs))
            }
        }

        for c in snapshot.conversations where !c.meta.isDeleted && !conversationsRatedByPractice.contains(c.id) {
            if let before = c.before, AnxietyScale.isValid(before) {
                out.append(AnxietyMeasurement(date: c.occurredAt, zoneID: c.zoneID, value: before, source: .conversationBefore, sourceID: c.id,
                                       isRetrospective: c.isRetrospective, dayPart: nil, tags: [], historyIDs: c.historyIDs))
            }
            if let after = c.after, AnxietyScale.isValid(after) {
                out.append(AnxietyMeasurement(date: c.occurredAt, zoneID: c.zoneID, value: after, source: .conversationAfter, sourceID: c.id,
                                       isRetrospective: c.isRetrospective, dayPart: nil, tags: [], historyIDs: c.historyIDs))
            }
        }

        return out.sorted { $0.date < $1.date }
    }
}

/// Фильтр графиков «Прогресса»: истории, теги, время суток (§7). Пустой набор = без ограничения.
public struct MeasurementFilter: Sendable, Equatable {
    public var historyIDs: Set<UUID>
    public var tags: Set<String>
    public var dayParts: Set<DayPart>

    public init(historyIDs: Set<UUID> = [], tags: Set<String> = [], dayParts: Set<DayPart> = []) {
        self.historyIDs = historyIDs; self.tags = tags; self.dayParts = dayParts
    }

    public var isEmpty: Bool { historyIDs.isEmpty && tags.isEmpty && dayParts.isEmpty }

    public func matches(_ m: AnxietyMeasurement) -> Bool {
        if !historyIDs.isEmpty && historyIDs.isDisjoint(with: m.historyIDs) { return false }
        if !tags.isEmpty && tags.isDisjoint(with: m.tags) { return false }
        if !dayParts.isEmpty && !dayParts.contains(m.effectiveDayPart) { return false }
        return true
    }
}

enum Stats {
    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted(), mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }
}
