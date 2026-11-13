import Foundation
import PivchikDomain

/// Период отчёта.
enum ReportPeriod: Hashable, CaseIterable {
    case week, month, quarter, custom

    var title: String {
        switch self {
        case .week: return "Неделя"
        case .month: return "Месяц"
        case .quarter: return "3 месяца"
        case .custom: return "Свой"
        }
    }

    /// Готовые периоды: последние 7, 30 или 90 дней включая сегодня.
    func range(today: LocalDay) -> (from: LocalDay, to: LocalDay) {
        switch self {
        case .week: return (today.adding(days: -6), today)
        case .month: return (today.adding(days: -29), today)
        case .quarter: return (today.adding(days: -89), today)
        case .custom: return (today.adding(days: -29), today)
        }
    }
}

/// Строка эпизода для отчёта и сводки.
struct ReportEpisode: Identifiable {
    let id: UUID
    let date: Date
    let peak: Int?
    let duration: TimeInterval?
    let cause: String?
    let thoughts: String?
    let symptoms: [String]
    let coping: String?
    let insight: String?
    let stories: [String]
    let retro: Bool
}

struct ReportStory {
    let title: String
    let status: String
    let episodesInPeriod: Int
    let episodesTotal: Int
}

struct ReportPractice {
    let title: String
    let stats: PracticeStats
}

struct ReportConversation {
    let date: Date
    let summary: String?
    let before: Int?
    let after: Int?
    let text: String?
}

/// Всё содержимое отчёта за период. Собирается только из записей пользователя и расчётов PivchikDomain.
struct ReportData {
    let from: LocalDay
    let to: LocalDay
    let summary: PeriodSummary
    let points: [BeadPoint]
    let causes: [(value: String, count: Int)]
    let symptoms: [(value: String, count: Int)]
    let episodes: [ReportEpisode]
    let stories: [ReportStory]
    let practices: [ReportPractice]
    let conversations: [ReportConversation]
    let conversationStats: ConversationStats
    let insights: [String]

    var periodTitle: String {
        if from.year == to.year {
            return "\(from.longTitle) — \(Fmt.dayMonthYear.string(from: to.noon))"
        }
        return "\(Fmt.dayMonthYear.string(from: from.noon)) — \(Fmt.dayMonthYear.string(from: to.noon))"
    }

    @MainActor
    static func build(store: AppStore, from: LocalDay, to: LocalDay) -> ReportData {
        let a = store.active
        let start = store.startDate(from)
        let end = store.startDate(to.adding(days: 1))
        func inRange(_ d: Date) -> Bool { d >= start && d < end }

        var titles: [UUID: String] = [:]
        for h in a.histories { titles[h.meta.id] = h.title }

        let episodes = a.episodes.filter { inRange($0.startedAt) }.sorted { $0.startedAt < $1.startedAt }
        let reportEpisodes = episodes.map { e in
            ReportEpisode(id: e.meta.id, date: e.startedAt, peak: e.peak, duration: e.duration, cause: e.cause, thoughts: e.thoughts,
                          symptoms: e.bodySymptoms, coping: e.coping, insight: e.insights,
                          stories: e.historyIDs.compactMap { titles[$0] }, retro: e.isRetrospective)
        }

        // График: до 31 дня — по дням, дальше — по неделям (сводки недель считает ядро).
        let days = LocalDay.range(from: from, to: to).count
        var points: [BeadPoint] = []
        if days <= 31 {
            points = store.dayPoints(from: from, to: to)
        } else {
            var weekEnd = to
            var weeks: [(LocalDay, LocalDay)] = []
            while weekEnd >= from && weeks.count < 14 {
                let weekStart = max(from, weekEnd.adding(days: -6))
                weeks.append((weekStart, weekEnd))
                weekEnd = weekStart.adding(days: -1)
            }
            for (i, w) in weeks.reversed().enumerated() {
                points.append(BeadPoint.period(i, label: "\(w.0.day).\(w.0.month < 10 ? "0" : "")\(w.0.month)",
                                               title: "\(w.0.shortTitle) – \(w.1.shortTitle)",
                                               summary: store.summary(from: w.0, to: w.1), thresholds: store.thresholds))
            }
        }

        let stories: [ReportStory] = store.histories.compactMap { h in
            let inPeriod = HistoryAnalytics.recurrence(historyID: h.meta.id, snapshot: a, from: start, to: end)
            let total = HistoryAnalytics.recurrence(historyID: h.meta.id, snapshot: a)
            let touched = inPeriod > 0 || a.conversations.contains { $0.historyIDs.contains(h.meta.id) && inRange($0.occurredAt) }
            guard touched || h.status == .active else { return nil }
            return ReportStory(title: h.title, status: h.status.title.lowercased(), episodesInPeriod: inPeriod, episodesTotal: total)
        }

        let stats = PracticeAnalytics.stats(snapshot: a, from: start, to: end)
        let practices = store.practices.compactMap { p -> ReportPractice? in
            guard let s = stats[p.meta.id] else { return nil }
            return ReportPractice(title: p.title, stats: s)
        }.sorted { $0.stats.sessionCount > $1.stats.sessionCount }

        let conversations = a.conversations.filter { inRange($0.occurredAt) }.sorted { $0.occurredAt < $1.occurredAt }.map { c in
            let r = ConversationAnalytics.ratings(for: c, sessions: a.sessions)
            return ReportConversation(date: c.occurredAt, summary: c.summary ?? c.insights, before: r.before, after: r.after, text: c.pastedText)
        }

        let insights = a.insights.filter { inRange($0.meta.createdAt) }.sorted { $0.meta.createdAt < $1.meta.createdAt }.map { $0.text }

        return ReportData(from: from, to: to, summary: store.summary(from: from, to: to), points: points,
                          causes: HistoryAnalytics.frequencies(episodes.compactMap { $0.cause }),
                          symptoms: HistoryAnalytics.frequencies(episodes.flatMap { $0.bodySymptoms }),
                          episodes: reportEpisodes, stories: stories, practices: practices, conversations: conversations,
                          conversationStats: ConversationAnalytics.stats(snapshot: a, from: start, to: end), insights: insights)
    }
}

/// Общие словесные описания, одинаковые в PDF и в сводке. Без оценок и выводов за человека.
enum ReportText {
    static func change(_ value: Double) -> String {
        if value > 0 { return "снижение на \(Fmt.num(value))" }
        if value < 0 { return "рост на \(Fmt.num(-value))" }
        return "без изменений"
    }

    static func practiceLine(_ p: ReportPractice) -> String {
        let s = p.stats
        var parts = [Fmt.count(s.sessionCount, "сессия", "сессии", "сессий")]
        if s.hasEnoughData {
            parts.append("легче в \(s.improvedCount) из \(s.pairedCount)")
            if let m = s.medianChange { parts.append("медиана: " + change(m)) }
            if let d = s.medianDuration { parts.append("обычно \(Fmt.duration(d))") }
        } else {
            parts.append("пока мало данных для расчёта")
        }
        return "\(p.title): " + parts.joined(separator: ", ")
    }

    static func summaryLines(_ d: ReportData) -> [String] {
        let s = d.summary
        guard s.daysWithData > 0 else { return ["За этот период записей нет."] }
        var out = ["Дней с записями: \(s.daysWithData) из \(s.totalDays). Оценок тревоги: \(s.measurementCount)."]
        out.append("Спокойных дней: \(s.calmDays), обычных: \(s.regularDays), тревожных: \(s.anxiousDays).")
        var line: [String] = []
        if let avg = s.averageOfDays { line.append("средняя по дням \(Fmt.num(avg))") }
        if let med = s.medianOfDays { line.append("медиана \(Fmt.num(med))") }
        if let peak = s.peak { line.append("наибольшая оценка \(peak)") }
        if !line.isEmpty { out.append(Fmt.capitalized(line.joined(separator: ", ")) + " (шкала 0–10).") }
        out.append("Эпизодов: \(s.episodeCount).")
        return out
    }

    static func episodeLine(_ e: ReportEpisode) -> String {
        var head = Fmt.dayMonth.string(from: e.date) + ", " + Fmt.time.string(from: e.date)
        if let p = e.peak { head += " — пик \(p)" }
        if let d = e.duration { head += ", \(Fmt.duration(d))" }
        if e.retro { head += " (добавлено задним числом)" }
        return head
    }
}
