import SwiftUI
import PivchikDomain

/// Перенос чипов по строкам.
struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? CGFloat.greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if x > 0 && x + size.width > maxW {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            widest = max(widest, x - spacing)
        }
        let width = proposal.width ?? widest
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if x > 0 && x + size.width > maxW {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
                      proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

/// Точка графика «бусины»: день или период. `average == nil` — данных нет (пробел, а не ноль).
struct BeadPoint: Identifiable {
    let id: Int
    let label: String
    let title: String
    let average: Double?
    let peak: Int?
    let episodes: Int
    let count: Int
    let category: DayCategory?
    let byReflection: Bool
    let retro: Int

    var hasData: Bool { average != nil }

    /// Точка одного дня из статистики ядра.
    static func day(_ index: Int, _ day: LocalDay, _ stats: DayStats?) -> BeadPoint {
        BeadPoint(id: index, label: day.weekdayShort, title: "\(day.weekdayShort), \(day.longTitle)",
                  average: stats?.average, peak: stats?.maximum, episodes: stats?.episodeCount ?? 0,
                  count: stats?.count ?? 0, category: stats?.category, byReflection: stats?.basis == .reflection,
                  retro: stats?.retrospectiveCount ?? 0)
    }

    /// Точка периода (неделя, месяц) из сводки ядра.
    static func period(_ index: Int, label: String, title: String, summary: PeriodSummary, thresholds: DayThresholds) -> BeadPoint {
        var category: DayCategory? = nil
        if let avg = summary.averageOfDays, let peak = summary.peak {
            category = DayAnalytics.category(average: avg, maximum: peak, thresholds: thresholds)
        }
        return BeadPoint(id: index, label: label, title: title, average: summary.averageOfDays, peak: summary.peak,
                         episodes: summary.episodeCount, count: summary.measurementCount, category: category,
                         byReflection: false, retro: 0)
    }
}

enum BeadSeries: Hashable {
    case average, peak, episodes
}

func categoryColor(_ category: DayCategory?) -> Color {
    switch category {
    case .some(.anxious): return Theme.pink
    case .some(.calm): return Theme.mint
    default: return Color.white
    }
}

/// График «бусины»: чем тревожнее день, тем бусина крупнее и выше.
struct BeadsChart: View {
    @Environment(\.palette) private var pal
    let points: [BeadPoint]
    let series: BeadSeries
    @Binding var selected: Int?

    var body: some View {
        GeometryReader { geo in
            let n = max(points.count, 1)
            let step = geo.size.width / CGFloat(n)
            ZStack(alignment: .topLeading) {
                ForEach(points) { p in
                    bead(p, x: step * (CGFloat(p.id) + 0.5), step: step)
                }
            }
            .frame(width: geo.size.width, height: 156, alignment: .topLeading)
        }
        .frame(height: 156)
    }

    private func value(_ p: BeadPoint) -> Double {
        switch series {
        case .average: return p.average ?? 0
        case .peak: return Double(p.peak ?? 0)
        case .episodes: return Double(p.episodes)
        }
    }

    private func radius(_ p: BeadPoint, step: CGFloat) -> CGFloat {
        let v = CGFloat(value(p))
        let raw: CGFloat = series == .episodes ? 11 + min(v, 4) * 5 : 10 + v * 1.85
        return min(raw, max(7, step / 2 - 1.5))
    }

    private func centerY(_ p: BeadPoint) -> CGFloat {
        series == .episodes ? 78 : 116 - CGFloat(value(p)) * 9.2
    }

    private func text(_ p: BeadPoint) -> String {
        series == .average ? Fmt.num(value(p)) : String(Int(value(p)))
    }

    @ViewBuilder
    private func bead(_ p: BeadPoint, x: CGFloat, step: CGFloat) -> some View {
        let isSel = selected == p.id
        Text(p.label).txt(step < 30 ? 9.5 : 12.5, .semibold)
            .foregroundStyle(pal.fg.opacity(0.62))
            .lineLimit(1).fixedSize()
            .position(x: x, y: 146)
            .accessibilityHidden(true)
        if p.hasData {
            let r = radius(p, step: step) + (isSel ? 3 : 0)
            let y = centerY(p)
            Rectangle().fill(pal.fg.opacity(0.16))
                .frame(width: 1, height: max(0, 132 - y))
                .position(x: x, y: (132 + y) / 2)
            Circle().fill(categoryColor(p.category))
                .frame(width: r * 2, height: r * 2)
                .shadow(color: Color(hex: 0x3C1E6E).opacity(0.22), radius: 5, x: 0, y: 5)
                .overlay(alignment: .topLeading) {
                    Circle().fill(Color.white.opacity(0.75))
                        .frame(width: r * 0.52, height: r * 0.52)
                        .offset(x: r * 0.44, y: r * 0.4)
                }
                .overlay {
                    Text(text(p)).txt(r > 16 ? 14 : (r > 11 ? 11.5 : 9), .bold)
                        .foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
                }
                .position(x: x, y: y)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: series)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSel)
        } else {
            Circle().strokeBorder(pal.fg.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                .frame(width: min(26, step - 4), height: min(26, step - 4))
                .position(x: x, y: 78)
        }
        Color.clear
            .frame(width: max(24, min(48, step)), height: 120)
            .contentShape(Rectangle())
            .position(x: x, y: 70)
            .onTapGesture { selected = isSel ? nil : p.id }
            .accessibilityElement()
            .accessibilityLabel(describe(p))
            .accessibilityAddTraits(.isButton)
    }

    private func describe(_ p: BeadPoint) -> String {
        guard let avg = p.average, let peak = p.peak else { return "\(p.title): записей нет" }
        return "\(p.title): средняя \(Fmt.num(avg)), пик \(peak), эпизодов \(p.episodes)"
    }
}

/// Подпись под графиком для выбранной точки.
struct BeadInfo: View {
    @Environment(\.palette) private var pal
    let point: BeadPoint?
    var isDay: Bool = true

    var body: some View {
        Group {
            if let p = point {
                if let avg = p.average, let peak = p.peak {
                    Text(p.title).foregroundColor(pal.fg).bold()
                        + Text(detail(p, avg: avg, peak: peak)).foregroundColor(pal.fg3)
                } else {
                    Text(p.title).foregroundColor(pal.fg).bold()
                        + Text(" · записей нет. Это пробел, а не спокойный день.").foregroundColor(pal.fg3)
                }
            } else {
                Text("Нажми на бусину — откроется \(isDay ? "день" : "период"). Чем тревожнее, тем она крупнее.").foregroundColor(pal.fg3)
            }
        }
        .txt(12.5)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(_ p: BeadPoint, avg: Double, peak: Int) -> String {
        var parts: [String] = []
        if let c = p.category { parts.append(isDay ? "\(c.title) день" : "в целом \(c.title)") }
        parts.append("средняя \(Fmt.num(avg))")
        parts.append("пик \(peak)")
        if p.byReflection {
            parts.append("по итогу дня")
        } else {
            parts.append("отметок \(p.count)")
        }
        parts.append("эпизодов \(p.episodes)")
        if p.retro > 0 { parts.append("задним числом \(p.retro)") }
        return " · " + parts.joined(separator: " · ")
    }
}

/// Кружок дня в календаре: спокойный, обычный, тревожный, без записей, будущий.
struct DayDot: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    let day: LocalDay
    var size: CGFloat = 36
    var selected: Bool = false

    var body: some View {
        let stats = store.dayStats[day]
        let future = day > store.today
        ZStack {
            if let stats {
                Circle().fill(color(stats.category))
            } else if !future {
                Circle().strokeBorder(pal.fg2, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
            Text("\(day.day)").txt(size < 34 ? 12 : 13.5, .semibold).monospacedDigit()
                .foregroundStyle(stats != nil ? Theme.ink : (future ? pal.fg2 : pal.fg3))
        }
        .frame(width: size, height: size)
        .overlay {
            if selected {
                Circle().strokeBorder(pal.fg, lineWidth: 2).padding(-4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(day.longTitle), \(stats?.category.title ?? (future ? "ещё впереди" : "без записей"))")
    }

    private func color(_ c: DayCategory) -> Color {
        switch c {
        case .calm: return Theme.mint
        case .anxious: return Theme.pink
        case .regular: return Color.white.opacity(0.75)
        }
    }
}

/// Неделя с понедельника по воскресенье.
struct WeekStrip: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    let start: LocalDay
    var selected: LocalDay?
    var onTap: (LocalDay) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let day = start.adding(days: i)
                    VStack(spacing: 6) {
                        Text(day.weekdayShort).txt(11.5, .semibold).foregroundStyle(pal.fg3)
                        Button { onTap(day) } label: {
                            DayDot(day: day, selected: selected == day)
                        }
                        .buttonStyle(PressStyle())
                        .disabled(day > store.today)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            DayLegend()
        }
    }
}

struct DayLegend: View {
    @Environment(\.palette) private var pal

    var body: some View {
        HStack(spacing: 12) {
            item(Theme.mint, "спокойный")
            item(Color.white, "обычный")
            item(Theme.pink, "тревожный")
        }
    }

    private func item(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).txt(12.5).foregroundStyle(pal.fg3).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// Ряд точек: пики эпизодов истории по порядку.
struct Spark: View {
    let values: [Int]
    var width: CGFloat = 96
    var height: CGFloat = 34
    var color: Color = Theme.ink

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let n = max(1, values.count - 1)
                let x = 8 + (width - 16) * CGFloat(i) / CGFloat(n)
                let y = height - 7 - (height - 14) * CGFloat(v) / 10
                let r = 3 + CGFloat(v) * 0.5
                Circle().fill(color.opacity(0.35 + 0.65 * Double(i) / Double(values.count)))
                    .frame(width: r * 2, height: r * 2)
                    .position(x: x, y: y)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// Звёзды, разлетающиеся при победе.
struct StarBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var go = false

    private struct Star: Identifiable {
        let id: Int
        let dx: CGFloat
        let dy: CGFloat
        let size: CGFloat
        let rotation: Double
        let delay: Double
    }

    private let stars: [Star] = (0..<16).map { i in
        Star(id: i, dx: CGFloat.random(in: -150...150), dy: CGFloat.random(in: -200...140),
             size: CGFloat.random(in: 12...26), rotation: Double.random(in: -120...120), delay: Double.random(in: 0...0.25))
    }

    var body: some View {
        ZStack {
            ForEach(stars) { s in
                Image(systemName: "star.fill")
                    .font(.system(size: s.size))
                    .foregroundStyle(Theme.gold)
                    .scaleEffect(go ? 1.1 : 0.3)
                    .rotationEffect(.degrees(go ? s.rotation : 0))
                    .offset(x: go ? s.dx : 0, y: go ? s.dy : 0)
                    .opacity(go ? 0 : 1)
                    .animation(.easeOut(duration: 1.1).delay(s.delay), value: go)
            }
        }
        .opacity(reduceMotion ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            go = true
        }
    }
}
