import Foundation
import PivchikDomain

/// Русские форматы дат, чисел и склонения.
enum Fmt {
    static let ru = Locale(identifier: "ru_RU")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = ru
        f.dateFormat = format
        return f
    }

    static let time = make("HH:mm")
    static let dayMonth = make("d MMMM")
    static let dayMonthShort = make("d MMM")
    static let dayMonthYear = make("d MMMM yyyy")
    static let weekday = make("EE")
    static let month = make("LLLL")
    static let fileDate = make("yyyy-MM-dd")

    /// Число с одним знаком после запятой: 3 → «3», 3.5 → «3,5».
    static func num(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        if r == r.rounded() { return String(Int(r)) }
        return String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = abs(n) % 100
        let b = a % 10
        if a >= 11 && a <= 14 { return many }
        if b == 1 { return one }
        if b >= 2 && b <= 4 { return few }
        return many
    }

    static func count(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(n) \(plural(n, one, few, many))"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) с" }
        let m = s / 60
        if m < 60 { return "\(m) мин" }
        return "\(m / 60) ч \(m % 60) мин"
    }

    static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }

    /// «изменено 14:20» сегодня, иначе «изменено 10 нояб., 14:20».
    static func edited(_ date: Date) -> String {
        let t = time.string(from: date)
        if Cal.current.isDateInToday(date) { return "изменено \(t)" }
        return "изменено \(dayMonthShort.string(from: date)), \(t)"
    }

    /// «Сегодня, 20:14», «Вчера, 22:40», «10 нояб., 08:15».
    static func relative(_ date: Date) -> String {
        let cal = Cal.current
        let t = time.string(from: date)
        if cal.isDateInToday(date) { return "Сегодня, \(t)" }
        if cal.isDateInYesterday(date) { return "Вчера, \(t)" }
        return "\(dayMonthShort.string(from: date)), \(t)"
    }
}

/// Календарь с понедельником в начале недели.
enum Cal {
    static var current: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = TimeZone.current
        c.locale = Fmt.ru
        return c
    }
}

extension LocalDay {
    /// Полдень этого дня в текущем поясе — удобно для форматирования.
    var noon: Date {
        Cal.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    var weekdayShort: String { Fmt.capitalized(Fmt.weekday.string(from: noon)) }
    var longTitle: String { Fmt.dayMonth.string(from: noon) }
    var shortTitle: String { Fmt.dayMonthShort.string(from: noon) }

    /// Понедельник недели, в которую входит день.
    var weekStart: LocalDay {
        let wd = Cal.current.component(.weekday, from: noon)
        let shift = (wd + 5) % 7
        return adding(days: -shift)
    }

    var monthStart: LocalDay { LocalDay(year: year, month: month, day: 1) }

    var daysInMonth: Int {
        Cal.current.range(of: .day, in: .month, for: noon)?.count ?? 30
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Пустая строка превращается в nil — в записи не пишем пустые поля.
    var nilIfEmpty: String? {
        let t = trimmed
        return t.isEmpty ? nil : t
    }
}
