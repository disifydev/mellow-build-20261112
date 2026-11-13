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
    @State private var selecting = Launch.screen == "diary-select"
    @State private var selected: Set<UUID> = []

    private var selectedDay: LocalDay { day ?? router.diaryDay ?? store.today }

    var body: some View {
        TabScroll {
            BigHeader(title: "Дневник", subtitle: selectedDay.longTitle) {
                RoundButton(icon: "square.stack.3d.up", label: "Истории") { withAnimation { router.tab = .stories } }
                RoundButton(icon: "plus", label: "Новая запись") {
                    router.composeDay = selectedDay == store.today ? nil : selectedDay
                    router.sheet = .newMenu
                }
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
        .onDisappear {
            router.diaryDay = nil
            router.composeDay = nil
        }
        .onChange(of: selectedDay) { _, _ in selected = [] }
        .onAppear {
            if Launch.screen == "diary-select" { selected = Set(items.prefix(2).map { $0.id }) }
        }
        .overlay(alignment: .bottom) {
            if selecting {
                selectionBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 86)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: selecting)
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
                Emblem(name: "PivRead", width: 64)
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
                ForEach(0..<lead, id: \.self) { i in
                    Color.clear.frame(height: 32).id("lead-\(i)")
                }
                ForEach(LocalDay.range(from: first, to: first.adding(days: count - 1)), id: \.self) { d in
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                H(searching ? "Найдено" : "Записи")
                Spacer()
                if !list.isEmpty || selecting {
                    Chip(text: selecting ? "Готово" : "Выбрать", isOn: selecting, height: 32) {
                        selecting.toggle()
                        selected = []
                    }
                }
            }
            if list.isEmpty {
                Cap(searching ? "Ничего не найдено." : (filter == .all ? "В этот день записей нет." : "Таких записей в этот день нет."))
            } else {
                let rows = searching ? Array(list.reversed()) : list
                ForEach(rows) { item in
                    SwipeToDelete(startOpen: Launch.screen == "diary-swipe" && item.id == rows.first?.id, enabled: !selecting,
                                  onTap: { tap(item) }, onDelete: { store.delete([item.id]) }) {
                        DiaryRow(item: item, showDate: searching, selecting: selecting, isSelected: selected.contains(item.id))
                    }
                    .id(item.id)
                }
                if !selecting {
                    Cap("Нажми на запись, чтобы изменить. Смахни влево, чтобы удалить.")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func tap(_ item: DiaryItem) {
        if selecting {
            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
            Haptics.tick(store.settings.hapticsEnabled)
        } else {
            router.sheet = .edit(item)
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            CTAButton(title: "Отмена", small: true) {
                selecting = false
                selected = []
            }
            .frame(width: 120)
            CTAButton(title: selected.isEmpty ? "Выбери записи" : "Удалить: \(selected.count)", icon: "trash", small: true) {
                guard !selected.isEmpty else { return }
                store.delete(selected)
                selected = []
                selecting = false
            }
            .opacity(selected.isEmpty ? 0.55 : 1)
        }
    }

    private var eveningCard: some View {
        let reflection = store.reflection(on: selectedDay)
        let done = reflection != nil
        return Button {
            router.sheet = .evening(selectedDay)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "moon").font(.system(size: 19, weight: .medium))
                VStack(alignment: .leading, spacing: 4) {
                    H("Итог дня")
                    Cap(done ? "Заполнен. Можно открыть и изменить." : "Общее состояние, что помогло, что было трудно")
                    if let edited = reflection?.meta.editedAt { Cap(Fmt.edited(edited)) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).opacity(0.6)
            }
            .card()
        }
        .buttonStyle(PressStyle())
    }
}

/// Строка ленты: время, оценка, текст, история, теги, подпись «изменено». В режиме выбора — кружок-отметка.
struct DiaryRow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    let item: DiaryItem
    var showDate: Bool = false
    var selecting: Bool = false
    var isSelected: Bool = false

    private var tint: Color {
        guard let v = item.value else { return item.kind == .win ? Theme.mint : Theme.lav }
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
            if selecting {
                ZStack {
                    Circle().fill(isSelected ? pal.on : Color.clear)
                    Circle().strokeBorder(isSelected ? Color.clear : pal.fg2, lineWidth: 1.5)
                    if isSelected {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(pal.onFg)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(.top, 10)
            } else {
                Circle().fill(tint).frame(width: 10, height: 10).padding(.top, 16)
            }
            content
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selecting && isSelected ? .isSelected : [])
        .accessibilityHint(selecting ? "Выбрать для удаления" : "Открыть и изменить")
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
                if item.retro || item.edited != nil {
                    Cap([item.retro ? "добавлено задним числом" : nil, item.edited.map { Fmt.edited($0) }].compactMap { $0 }.joined(separator: " · "))
                }
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
        }
        .card(13, radius: 22)
        .overlay {
            if selecting && isSelected {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(pal.fg.opacity(0.6), lineWidth: 2)
            }
        }
    }

    private var badge: some View {
        Group {
            if let v = item.value {
                Text("\(v)").display(18)
            } else {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(width: 40, height: 40)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))
    }

    private var icon: String {
        switch item.kind {
        case .conversation: return "bubble.left"
        case .win: return "checkmark"
        default: return "wind"
        }
    }
}
