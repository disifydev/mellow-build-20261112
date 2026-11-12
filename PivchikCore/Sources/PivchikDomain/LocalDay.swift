import Foundation

/// Календарный день без времени. День записи считается по часовому поясу самой записи (§7).
public struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    public init(date: Date, zoneID: String) {
        let c = LocalDay.calendar(zoneID: zoneID).dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Разбор строки ГГГГ-ММ-ДД.
    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String {
        let y = String(year), m = String(month), d = String(day)
        return String(repeating: "0", count: max(0, 4 - y.count)) + y + "-" + (m.count < 2 ? "0" + m : m) + "-" + (d.count < 2 ? "0" + d : d)
    }

    public static func < (a: LocalDay, b: LocalDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// Соседний день (смещение в днях, может быть отрицательным).
    public func adding(days: Int) -> LocalDay {
        let cal = LocalDay.calendar(zoneID: "UTC")
        let base = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        let moved = cal.date(byAdding: .day, value: days, to: base) ?? base
        return LocalDay(date: moved, zoneID: "UTC")
    }

    /// Все дни от `from` до `to` включительно.
    public static func range(from: LocalDay, to: LocalDay) -> [LocalDay] {
        guard from <= to else { return [] }
        var out: [LocalDay] = [], cur = from
        while cur <= to { out.append(cur); cur = cur.adding(days: 1) }
        return out
    }

    /// Начало дня в указанном поясе.
    public func startDate(zoneID: String) -> Date {
        LocalDay.calendar(zoneID: zoneID).date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    static func calendar(zoneID: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zoneID) ?? TimeZone(secondsFromGMT: 0)!
        return cal
    }
}

public enum RetrospectiveRule {
    /// Порог: событие раньше создания записи больше чем на 24 часа (§9).
    public static let threshold: TimeInterval = 24 * 60 * 60

    public static func isRetrospective(eventAt: Date, createdAt: Date) -> Bool {
        createdAt.timeIntervalSince(eventAt) > threshold
    }
}

public extension EpisodeRecord {
    /// Все дни, которые занимает эпизод (для календаря). Незавершённый эпизод — до `now`.
    func coveredDays(now: Date) -> [LocalDay] {
        let end = max(startedAt, endedAt ?? now)
        return LocalDay.range(from: LocalDay(date: startedAt, zoneID: zoneID), to: LocalDay(date: end, zoneID: zoneID))
    }
}
