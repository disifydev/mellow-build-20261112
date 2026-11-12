import Foundation

/// Пороги спокойного и тревожного дня. Порог спокойного всегда строго меньше порога тревожного.
public struct DayThresholds: Codable, Sendable, Hashable {
    public var calm: Int
    public var anxious: Int

    public static let `default` = DayThresholds(calm: 3, anxious: 7)

    public init(calm: Int, anxious: Int) {
        self.calm = calm; self.anxious = anxious
    }

    public var isValid: Bool {
        AnxietyScale.isValid(calm) && AnxietyScale.isValid(anxious) && calm < anxious
    }

    /// Некорректные пороги заменяются значениями по умолчанию.
    public var normalized: DayThresholds { isValid ? self : .default }
}

public enum DayCategory: String, Sendable, Codable {
    case calm, regular, anxious
}

/// Итог одного дня. Дня без записей в результатах просто нет — это пробел, а не ноль.
public struct DayStats: Sendable, Equatable {
    public enum Basis: String, Sendable {
        /// По измерениям дня.
        case measurements
        /// Измерений нет, взята общая оценка из вечернего итога («по итогу дня»).
        case reflection
    }

    public let day: LocalDay
    public let average: Double
    public let maximum: Int
    public let minimum: Int
    public let median: Double
    /// Число измерений (0, если день оценён только по вечернему итогу).
    public let count: Int
    public let retrospectiveCount: Int
    public let category: DayCategory
    public let basis: Basis
    /// Общая оценка из вечернего итога — показывается отдельной отметкой, в среднее не входит.
    public let reflectionScore: Int?
    /// Число эпизодов, начавшихся в этот день.
    public let episodeCount: Int
    public let values: [Int]
}

public enum DayAnalytics {
    /// Категория дня: тревожный имеет приоритет над спокойным (день 1, 1, 1, 8 — тревожный).
    public static func category(average: Double, maximum: Int, thresholds: DayThresholds) -> DayCategory {
        let t = thresholds.normalized
        if maximum >= t.anxious { return .anxious }
        if average <= Double(t.calm) { return .calm }
        return .regular
    }

    /// Статистика по дням, где есть хотя бы одна запись.
    public static func dayStats(snapshot: Snapshot, thresholds: DayThresholds = .default,
                                filter: MeasurementFilter = MeasurementFilter()) -> [LocalDay: DayStats] {
        let measurements = MeasurementCollector.collect(from: snapshot).filter { filter.matches($0) }
        let byDay = Dictionary(grouping: measurements, by: { $0.day })

        var episodesByDay: [LocalDay: Int] = [:]
        for e in snapshot.episodes where !e.meta.isDeleted {
            if !filter.historyIDs.isEmpty && filter.historyIDs.isDisjoint(with: e.historyIDs) { continue }
            if !filter.tags.isEmpty && filter.tags.isDisjoint(with: e.tags) { continue }
            episodesByDay[LocalDay(date: e.startedAt, zoneID: e.zoneID), default: 0] += 1
        }

        // Вечерний итог не привязан к истории/тегам/времени суток, поэтому при включённом фильтре не используется.
        var reflectionByDay: [LocalDay: Int] = [:]
        if filter.isEmpty {
            let reflections = MergeRules.mergeDayReflections(snapshot.dayReflections.filter { !$0.meta.isDeleted }).kept
            for r in reflections {
                guard let day = LocalDay(string: r.localDate), let score = r.overallAnxiety, AnxietyScale.isValid(score) else { continue }
                reflectionByDay[day] = score
            }
        }

        var result: [LocalDay: DayStats] = [:]
        for (day, items) in byDay {
            let values = items.map { $0.value }
            let doubles = values.map(Double.init)
            let average = Stats.mean(doubles) ?? 0
            let maximum = values.max() ?? 0
            result[day] = DayStats(day: day, average: average, maximum: maximum, minimum: values.min() ?? 0,
                                   median: Stats.median(doubles) ?? 0, count: values.count,
                                   retrospectiveCount: items.filter { $0.isRetrospective }.count,
                                   category: category(average: average, maximum: maximum, thresholds: thresholds),
                                   basis: .measurements, reflectionScore: reflectionByDay[day],
                                   episodeCount: episodesByDay[day] ?? 0, values: values)
        }
        for (day, score) in reflectionByDay where result[day] == nil {
            result[day] = DayStats(day: day, average: Double(score), maximum: score, minimum: score, median: Double(score),
                                   count: 0, retrospectiveCount: 0,
                                   category: category(average: Double(score), maximum: score, thresholds: thresholds),
                                   basis: .reflection, reflectionScore: score, episodeCount: episodesByDay[day] ?? 0, values: [])
        }
        return result
    }

    /// Ряд для графика: по одному элементу на каждый день интервала; nil = нет данных (пробел).
    public static func series(from: LocalDay, to: LocalDay, stats: [LocalDay: DayStats]) -> [(day: LocalDay, stats: DayStats?)] {
        LocalDay.range(from: from, to: to).map { (day: $0, stats: stats[$0]) }
    }

    /// Сводка периода для сравнения недель и месяцев.
    public static func summary(from: LocalDay, to: LocalDay, stats: [LocalDay: DayStats]) -> PeriodSummary {
        let days = LocalDay.range(from: from, to: to)
        let present = days.compactMap { stats[$0] }
        let dayAverages = present.map { $0.average }
        return PeriodSummary(from: from, to: to, totalDays: days.count, daysWithData: present.count,
                             calmDays: present.filter { $0.category == .calm }.count,
                             regularDays: present.filter { $0.category == .regular }.count,
                             anxiousDays: present.filter { $0.category == .anxious }.count,
                             measurementCount: present.reduce(0) { $0 + $1.count },
                             episodeCount: present.reduce(0) { $0 + $1.episodeCount },
                             averageOfDays: Stats.mean(dayAverages), medianOfDays: Stats.median(dayAverages),
                             peak: present.map { $0.maximum }.max())
    }
}

public struct PeriodSummary: Sendable, Equatable {
    public let from: LocalDay
    public let to: LocalDay
    public let totalDays: Int
    public let daysWithData: Int
    public let calmDays: Int
    public let regularDays: Int
    public let anxiousDays: Int
    public let measurementCount: Int
    public let episodeCount: Int
    /// Среднее и медиана дневных оценок; nil, если данных нет.
    public let averageOfDays: Double?
    public let medianOfDays: Double?
    public let peak: Int?

    public var daysWithoutData: Int { totalDays - daysWithData }
}
