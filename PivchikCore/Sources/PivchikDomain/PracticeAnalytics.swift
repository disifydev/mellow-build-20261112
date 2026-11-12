import Foundation

/// Аналитика одной практики (§7). Причинность не утверждается: это только наблюдаемые изменения.
public struct PracticeStats: Sendable, Equatable {
    public let practiceID: UUID
    /// Все сессии (любой статус).
    public let sessionCount: Int
    /// Сессии с обеими оценками, кроме прерванных, — выборка для расчётов.
    public let pairedCount: Int
    public let improvedCount: Int
    /// Доля сессий со снижением > 0 среди парных; nil без выборки.
    public let improvedShare: Double?
    public let meanChange: Double?
    public let medianChange: Double?
    /// Медианная фактическая длительность, секунды (только практики с таймером).
    public let medianDuration: TimeInterval?
    /// Средняя скорость снижения, баллов в минуту (таймер, длительность ≥ 1 мин, обе оценки).
    public let speedPerMinute: Double?
    public let speedSampleCount: Int
    public let feltEasier: Int
    public let feltSame: Int
    public let feltHarder: Int
    /// Все изменения before − after — для показа распределения.
    public let changes: [Int]

    /// При выборке меньше 3 доли и средние не показываются («пока мало данных»).
    public var hasEnoughData: Bool { pairedCount >= PracticeAnalytics.minimumSample }
}

public enum PracticeAnalytics {
    public static let minimumSample = 3
    static let minimumSpeedDuration: TimeInterval = 60

    public static func stats(snapshot: Snapshot, from: Date? = nil, to: Date? = nil,
                             historyIDs: Set<UUID> = []) -> [UUID: PracticeStats] {
        let sessions = snapshot.sessions.filter { s in
            guard !s.meta.isDeleted, s.status != .running else { return false }
            if let from, s.startedAt < from { return false }
            if let to, s.startedAt >= to { return false }
            if !historyIDs.isEmpty && historyIDs.isDisjoint(with: s.historyIDs) { return false }
            return true
        }
        var result: [UUID: PracticeStats] = [:]
        for (practiceID, items) in Dictionary(grouping: sessions, by: { $0.practiceID }) {
            result[practiceID] = stats(practiceID: practiceID, sessions: items)
        }
        return result
    }

    static func stats(practiceID: UUID, sessions: [PracticeSessionRecord]) -> PracticeStats {
        let paired = sessions.filter { $0.status != .interrupted && $0.change != nil }
        let changes = paired.compactMap { $0.change }
        let doubles = changes.map(Double.init)
        let improved = changes.filter { $0 > 0 }.count

        let durations = sessions.filter { $0.practiceType.isTimed && $0.status != .interrupted }
            .compactMap { $0.activeDuration }.filter { $0 > 0 }

        let speeds: [Double] = paired.compactMap { s in
            guard s.practiceType.isTimed, let change = s.change, let d = s.activeDuration, d >= minimumSpeedDuration else { return nil }
            return Double(change) / (d / 60)
        }

        return PracticeStats(practiceID: practiceID, sessionCount: sessions.count, pairedCount: paired.count,
                             improvedCount: improved,
                             improvedShare: paired.isEmpty ? nil : Double(improved) / Double(paired.count),
                             meanChange: Stats.mean(doubles), medianChange: Stats.median(doubles),
                             medianDuration: Stats.median(durations), speedPerMinute: Stats.mean(speeds),
                             speedSampleCount: speeds.count,
                             feltEasier: sessions.filter { $0.feltResult == .easier }.count,
                             feltSame: sessions.filter { $0.feltResult == .same }.count,
                             feltHarder: sessions.filter { $0.feltResult == .harder }.count,
                             changes: changes)
    }
}

/// Аналитика разговоров (§7).
public struct ConversationStats: Sendable, Equatable {
    public let count: Int
    public let pairedCount: Int
    public let meanChange: Double?
    public let medianChange: Double?
    public let withInsights: Int
    public let countByHistory: [UUID: Int]
}

public enum ConversationAnalytics {
    /// Оценки разговора: собственные, а если их нет — из привязанной практики.
    public static func ratings(for conversation: ConversationRecord, sessions: [PracticeSessionRecord]) -> (before: Int?, after: Int?) {
        if conversation.before != nil || conversation.after != nil { return (conversation.before, conversation.after) }
        let linked = sessions.filter { !$0.meta.isDeleted && $0.conversationID == conversation.id && ($0.before != nil || $0.after != nil) }
            .sorted { $0.startedAt < $1.startedAt }
        return (linked.first?.before, linked.last?.after)
    }

    public static func stats(snapshot: Snapshot, from: Date? = nil, to: Date? = nil) -> ConversationStats {
        let items = snapshot.conversations.filter { c in
            guard !c.meta.isDeleted else { return false }
            if let from, c.occurredAt < from { return false }
            if let to, c.occurredAt >= to { return false }
            return true
        }
        var changes: [Double] = []
        var byHistory: [UUID: Int] = [:]
        for c in items {
            let r = ratings(for: c, sessions: snapshot.sessions)
            if let b = r.before, let a = r.after { changes.append(Double(b - a)) }
            for h in Set(c.historyIDs) { byHistory[h, default: 0] += 1 }
        }
        return ConversationStats(count: items.count, pairedCount: changes.count, meanChange: Stats.mean(changes),
                                 medianChange: Stats.median(changes),
                                 withInsights: items.filter { !($0.insights ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
                                 countByHistory: byHistory)
    }
}

/// Аналитика историй (§7).
public enum HistoryAnalytics {
    /// Повторение истории: число уникальных связанных эпизодов, начавшихся в периоде. Отметки и замеры не считаются.
    public static func recurrence(historyID: UUID, snapshot: Snapshot, from: Date? = nil, to: Date? = nil) -> Int {
        episodes(historyID: historyID, snapshot: snapshot, from: from, to: to).count
    }

    public static func episodes(historyID: UUID, snapshot: Snapshot, from: Date? = nil, to: Date? = nil) -> [EpisodeRecord] {
        var seen = Set<UUID>()
        return snapshot.episodes.filter { e in
            guard !e.meta.isDeleted, e.historyIDs.contains(historyID) else { return false }
            if let from, e.startedAt < from { return false }
            if let to, e.startedAt >= to { return false }
            return seen.insert(e.id).inserted
        }.sorted { $0.startedAt < $1.startedAt }
    }

    /// Самые частые значения (причины, симптомы, теги) с числом упоминаний, по убыванию.
    public static func frequencies(_ values: [String]) -> [(value: String, count: Int)] {
        var counts: [String: (display: String, count: Int)] = [:]
        for raw in values {
            let display = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { continue }
            let key = display.lowercased()
            counts[key] = (display: counts[key]?.display ?? display, count: (counts[key]?.count ?? 0) + 1)
        }
        return counts.values.map { (value: $0.display, count: $0.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.value < $1.value }
    }

    public static func topCauses(snapshot: Snapshot) -> [(value: String, count: Int)] {
        frequencies(snapshot.episodes.filter { !$0.meta.isDeleted }.compactMap { $0.cause })
    }

    public static func topSymptoms(snapshot: Snapshot) -> [(value: String, count: Int)] {
        frequencies(snapshot.episodes.filter { !$0.meta.isDeleted }.flatMap { $0.bodySymptoms })
    }
}
