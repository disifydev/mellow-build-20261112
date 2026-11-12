import SwiftUI
import PivchikDomain

struct DiaryView: View {
    enum Mode: Hashable { case day, week, month }
    enum Filter: Hashable { case all, episodes, practices, conversations, high }

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var pal
    @State private var mode: Mode = .day
    @State private var filter: Filter = .all
    @State private var day: LocalDay?
    @State private var query = ""
    @State private var pendingDelete: DiaryItem?

    private var selectedDay: LocalDay { day ?? router.diaryDay ?? store.today }

    var body: some View {
        TabScroll {
            BigHeader(title: "Дневник", subtitle: "\(selectedDay.longTitle), \(selectedDay.weekdayShort.lowercased())") {
                RoundButton(icon: "plus", label: "Новая запись") { router.sheet = .newMenu }
            }
            SegControl(items: [(Mode.day, "День"), (Mode.week, "Неделя"), (Mode.month, "Месяц")], selection: $mode)
            switch mode {
            case .day: dayTiles
            case .week: weekCard
            case .month: monthCard
            }
            searchField
            HScroll {
                chip("все", .all)
                chip("эпизоды", .episodes)
                chip("практики", .practices)
                chip("разговоры", .conversations)
                chip("≥ \(store.thresholds.anxious)", .high)
            }
            timeline.id("timeline")
            eveningCard.id("evening")
        }
        .onChange(of: router.diaryDay) { _, new in
            if let new { day = new }
        }
        .onDisappear { router.diaryDay = nil }
        .confirmationDialog("Удалить запись?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let item = pendingDelete { delete(item) }
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Запись исчезнет из дневника, а статистика пересчитается.")
        }
    }

    private func chip(_ title: String, _ value: Filter) -> some View {
        Chip(text: title, isOn: filter == value) { filter = value }
    }

    // MARK: День, неделя, месяц

    @ViewBuilder
    private var dayTiles: some View {
        if let s = store.dayStats[selectedDay] {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Cap("Средняя за день")
                    Num(value: Fmt.num(s.average),
                        small: s.basis == .reflection ? "по итогу дня" : Fmt.count(s.count, "отметка", "отметки", "отметок"))
                }
                .card(13)
                VStack(alignment: .leading, spacing: 6) {
                    Cap("Пик дня")
                    Num(value: "\(s.maximum)", small: s.category.title)
                }
                .card(13)
            }
        } else {
            HStack(spacing: 12) {
                CatImage(name: "PivRead", width: 64)
                Cap(selectedDay == store.today ? "Пока нет записей — можно начать с одной отметки." : "В этот день записей нет. Это пробел, а не спокойный день.")
                Spacer(minLength: 0)
            }
            .card(13)
        }
    }

    private var weekCard: some View {
        WeekStrip(start: selectedDay.weekStart, selected: selectedDay) { d in day = d }
            .card()
    }

    private var monthCard: some View {
        let first = selectedDay.monthStart
        let count = first.daysInMonth
        let lead = max(0, LocalDay.range(from: first.weekStart, to: first).count - 1)
        let withData = (0..<count).filter { store.dayStats[first.adding(days: $0)] != nil }.count
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { day = first.adding(days: -1).monthStart } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Предыдущий месяц")
                H(Fmt.capitalized(Fmt.month.string(from: first.noon)))
                Button { moveForward(first, count) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Следующий месяц")
                Spacer()
                Cap(withData == 0 ? "записей нет" : "\(Fmt.count(withData, "день", "дня", "дней")) с записями")
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { n in
                    Text(n).txt(11.5, .semibold).foregroundStyle(pal.fg3)
                }
                ForEach(0..<lead, id: \.self) { _ in
                    Color.clear.frame(height: 32)
                }
                ForEach(0..<count, id: \.self) { i in
                    let d = first.adding(days: i)
                    Button { day = d } label: {
                        DayDot(day: d, size: 32, selected: d == selectedDay)
                    }
                    .buttonStyle(.plain)
                    .disabled(d > store.today)
                }
            }
            DayLegend()
        }
        .card()
    }

    private func moveForward(_ first: LocalDay, _ count: Int) {
        let next = first.adding(days: count)
        if next <= store.today { day = next }
    }

    // MARK: Поиск и лента

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).opacity(0.6)
            TextField("", text: $query, prompt: Text("Поиск по тексту, тегам, историям").foregroundColor(pal.fg2))
                .txt(14.5)
                .submitLabel(.search)
                .accessibilityLabel("Поиск по записям")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").opacity(0.5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glass(22)
    }

    private var items: [DiaryItem] {
        let q = query.trimmed.lowercased().replacingOccurrences(of: "#", with: "")
        return store.diary.filter { item in
            if q.isEmpty {
                if item.day != selectedDay { return false }
            } else if !item.haystack.contains(q) {
                return false
            }
            switch filter {
            case .all: return true
            case .episodes: return item.kind == .episode
            case .practices: return item.kind == .session
            case .conversations: return item.kind == .conversation
            case .high: return (item.value ?? -1) >= store.thresholds.anxious
            }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        let list = items
        let searching = !query.trimmed.isEmpty
        if list.isEmpty {
            Cap(searching ? "Ничего не найдено." : (filter == .all ? "В этот день записей нет." : "Таких записей в этот день нет."))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(searching ? Array(list.reversed()) : list) { item in
                    DiaryRow(item: item, showDate: searching) { pendingDelete = item }
                }
            }
        }
    }

    private func delete(_ item: DiaryItem) {
        switch item.kind {
        case .checkIn: store.softDelete(\Snapshot.checkIns, id: item.id)
        case .episode: store.softDelete(\Snapshot.episodes, id: item.id)
        case .conversation: store.softDelete(\Snapshot.conversations, id: item.id)
        case .session: store.softDelete(\Snapshot.sessions, id: item.id)
        }
    }

    private var eveningCard: some View {
        let done = store.reflection(on: selectedDay) != nil
        return Button {
            router.sheet = .evening(selectedDay)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "moon").font(.system(size: 19, weight: .medium))
                VStack(alignment: .leading, spacing: 4) {
                    H("Итог дня")
                    Cap(done ? "Заполнен. Можно открыть и дополнить." : "Общее состояние, что помогло, что было трудно")
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).opacity(0.6)
            }
            .card()
        }
        .buttonStyle(PressStyle())
    }
}

/// Строка ленты: время, оценка, текст, история, теги, удаление.
struct DiaryRow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    let item: DiaryItem
    var showDate: Bool = false
    var onDelete: () -> Void

    private var tint: Color {
        guard let v = item.value else { return Theme.lav }
        let t = store.thresholds
        if v >= t.anxious { return Theme.pink }
        if v <= t.calm { return Theme.mint }
        return Color.white
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.time.string(from: item.date)).txt(11.5, .semibold).monospacedDigit().foregroundStyle(pal.fg3)
                if showDate {
                    Text(item.day.shortTitle).txt(10).foregroundStyle(pal.fg3).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(width: 40, alignment: .trailing)
            .padding(.top, 14)
            Circle().fill(tint).frame(width: 10, height: 10).padding(.top, 16)
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Lab(item.kind.title)
                    Spacer(minLength: 4)
                    if !item.trailing.isEmpty { Cap(item.trailing) }
                }
                Text(item.note).txt(12.5).fixedSize(horizontal: false, vertical: true)
                if item.retro { Cap("добавлено задним числом") }
                if !item.stories.isEmpty || !item.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(item.stories, id: \.self) { TagPill(text: $0) }
                        ForEach(item.tags, id: \.self) { t in
                            Text("#\(t)").txt(12.5).foregroundStyle(pal.fg3).padding(.top, 4)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Button(action: onDelete) {
                Image(systemName: "trash").font(.system(size: 14, weight: .medium)).opacity(0.45)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить запись")
        }
        .card(13, radius: 22)
    }

    private var badge: some View {
        Group {
            if let v = item.value {
                Text("\(v)").display(18)
            } else {
                Image(systemName: item.kind == .conversation ? "bubble.left" : "wind").font(.system(size: 16, weight: .semibold))
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(width: 40, height: 40)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))
    }
}
