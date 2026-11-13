import SwiftUI
import PivchikDomain

/// Тепловая карта по месяцам: каждый день окрашен как спокойный, обычный, тревожный или без записей.
/// Нажатие на день показывает его итоги. Статистику (с фильтром) передаёт экран «Прогресс».
struct HeatMapCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    let months: [LocalDay]
    let stats: [LocalDay: DayStats]
    @Binding var selected: LocalDay?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                H("Календарь")
                Spacer()
                Cap("нажми на день")
            }
            if let day = selected {
                BeadInfo(point: BeadPoint.day(0, day, stats[day]), isDay: true)
            }
            ForEach(months, id: \.self) { m in
                month(m)
            }
            DayLegend()
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 4).strokeBorder(pal.fg2, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                    .frame(width: 10, height: 10)
                Text("без записей").txt(12.5).foregroundStyle(pal.fg3)
            }
        }
        .card()
    }

    private func month(_ first: LocalDay) -> some View {
        let count = first.daysInMonth
        let lead = max(0, LocalDay.range(from: first.weekStart, to: first).count - 1)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        let withData = (0..<count).filter { stats[first.adding(days: $0)] != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Lab(Fmt.capitalized(Fmt.month.string(from: first.noon)) + (first.year != store.today.year ? " \(first.year)" : ""))
                Spacer()
                Cap(withData == 0 ? "записей нет" : "\(Fmt.count(withData, "день", "дня", "дней")) с записями")
            }
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { n in
                    Text(n).txt(10.5, .semibold).foregroundStyle(pal.fg3)
                }
                ForEach(0..<lead, id: \.self) { _ in
                    Color.clear.frame(height: 30)
                }
                ForEach(0..<count, id: \.self) { i in
                    cell(first.adding(days: i))
                }
            }
        }
    }

    private func cell(_ day: LocalDay) -> some View {
        let s = stats[day]
        let future = day > store.today
        let isSel = selected == day
        return Button {
            selected = isSel ? nil : day
            Haptics.tick(store.settings.hapticsEnabled)
        } label: {
            ZStack {
                if let s {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color(s.category))
                } else if !future {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(pal.fg2, style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                }
                Text("\(day.day)").txt(11.5, .semibold).monospacedDigit()
                    .foregroundStyle(s != nil ? Theme.ink : (future ? pal.fg2 : pal.fg3))
            }
            .frame(height: 30)
            .overlay {
                if isSel {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(pal.fg, lineWidth: 2).padding(-2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel("\(day.longTitle), \(s?.category.title ?? (future ? "ещё впереди" : "без записей"))")
    }

    private func color(_ c: DayCategory) -> Color {
        switch c {
        case .calm: return Theme.mint
        case .anxious: return Theme.pink
        case .regular: return Color.white.opacity(0.8)
        }
    }
}
