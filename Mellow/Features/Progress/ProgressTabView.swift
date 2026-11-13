import SwiftUI
import PivchikDomain

struct ProgressTabView: View {
    enum Period: Hashable { case week, month, year, all }

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var pal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var period: Period = Launch.screen == "heatmap" ? .month : .week
    @State private var filter = MeasurementFilter()
    @State private var heatDay: LocalDay?
    @State private var selected: Int?
    @State private var spin = false

    var body: some View {
        let range = currentRange
        let summary = DayAnalytics.summary(from: range.from, to: range.to, stats: stats)
        TabScroll {
            BigHeader(title: "Прогресс", subtitle: subtitle(summary)) {
                RoundButton(icon: "doc.richtext", label: "Отчёт для психолога") { router.sheet = .report }
            }
            SegControl(items: [(Period.week, "Неделя"), (Period.month, "Месяц"), (Period.year, "Год"), (Period.all, "Всё время")], selection: $period)
            filterChips
            ChartCard(title: chartTitle, points: points, delta: period == .week && filter.isEmpty ? store.weekDelta() : nil,
                      isDay: period == .week, selected: $selected)
            if period != .week {
                HeatMapCard(months: heatMonths, stats: stats, selected: $heatDay).id("heatmap")
            }
            tiles(summary).id("tiles")
            if summary.daysWithData > 0 {
                Cap("Считаются только дни с записями. Без записей: \(Fmt.count(summary.daysWithoutData, "день", "дня", "дней")).")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            causesCard.id("causes")
            storiesCard
            practiceTiles.id("practice")
            achievements.id("achievements")
            winsCard.id("wins")
            links
            monthCard
            CTAButton(title: "Отчёт для психолога", icon: "doc.richtext") { router.sheet = .report }
            HStack(spacing: 10) {
                CTAButton(title: "Сводка для ChatGPT", small: true) { router.sheet = .summary }
                CTAButton(title: "Копия JSON", small: true) { router.sheet = .backup }
            }
        }
        .onChange(of: period) { _, _ in selected = nil; heatDay = nil }
        .onChange(of: filter) { _, _ in selected = nil }
        .onAppear {
            if Launch.screen == "progress-filter", let first = store.histories.first {
                filter.historyIDs = [first.meta.id]
            }
        }
    }

    // MARK: Фильтры

    /// Статистика дней с учётом фильтра — считает ядро (MeasurementFilter).
    private var stats: [LocalDay: DayStats] { store.dayStats(filter: filter) }

    private var filterChips: some View {
        HScroll {
            Chip(text: "все записи", isOn: filter.isEmpty) { filter = MeasurementFilter() }
            ForEach(store.histories, id: \.meta.id) { h in
                Chip(text: h.title, isOn: filter.historyIDs.contains(h.meta.id)) { toggle(&filter.historyIDs, h.meta.id) }
            }
            Chip(text: "утро", isOn: filter.dayParts.contains(.morning)) { toggle(&filter.dayParts, .morning) }
            Chip(text: "день", isOn: filter.dayParts.contains(.day)) { toggle(&filter.dayParts, .day) }
            Chip(text: "вечер", isOn: filter.dayParts.contains(.evening)) { toggle(&filter.dayParts, .evening) }
            ForEach(store.allTags, id: \.self) { t in
                Chip(text: "#\(t)", isOn: filter.tags.contains(t)) { toggle(&filter.tags, t) }
            }
        }
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    /// Месяцы для тепловой карты, новые сверху.
    private var heatMonths: [LocalDay] {
        let r = currentRange
        var out: [LocalDay] = []
        var cur = r.to.monthStart
        while cur >= r.from.monthStart && out.count < 12 {
            out.append(cur)
            cur = cur.adding(days: -1).monthStart
        }
        return out
    }

    // MARK: Период

    private var firstDay: LocalDay {
        store.dayStats.keys.min() ?? store.today
    }

    private var currentRange: (from: LocalDay, to: LocalDay) {
        let t = store.today
        switch period {
        case .week: return (t.adding(days: -6), t)
        case .month: return (t.adding(days: -29), t)
        case .year: return (t.adding(days: -364), t)
        case .all: return (min(firstDay, t), t)
        }
    }

    private var previousRange: (from: LocalDay, to: LocalDay)? {
        let t = store.today
        switch period {
        case .week: return (t.adding(days: -13), t.adding(days: -7))
        case .month: return (t.adding(days: -59), t.adding(days: -30))
        case .year: return (t.adding(days: -729), t.adding(days: -365))
        case .all: return nil
        }
    }

    private var chartTitle: String {
        switch period {
        case .week: return "Тревога за 7 дней"
        case .month: return "По неделям"
        case .year: return "По месяцам"
        case .all: return "За всё время"
        }
    }

    private func subtitle(_ s: PeriodSummary) -> String {
        guard let cur = s.averageOfDays else { return "пока без записей" }
        guard let prevRange = previousRange,
              let prev = DayAnalytics.summary(from: prevRange.from, to: prevRange.to, stats: stats).averageOfDays else { return "твои записи" }
        if cur < prev - 0.3 { return "стало тише" }
        if cur > prev + 0.3 { return "было непросто" }
        return "ровно, как раньше"
    }

    /// Неделя — по дням; месяц — по неделям; год и всё время — по месяцам. Агрегаты считает ядро.
    private var points: [BeadPoint] {
        let t = store.today
        switch period {
        case .week:
            return store.dayPoints(from: t.adding(days: -6), to: t, stats: stats)
        case .month:
            var out: [BeadPoint] = []
            for i in 0..<5 {
                let to = t.adding(days: -7 * (4 - i))
                let from = to.adding(days: -6)
                out.append(BeadPoint.period(i, label: "\(from.day)–\(to.day)", title: "\(from.shortTitle) – \(to.shortTitle)",
                                            summary: DayAnalytics.summary(from: from, to: to, stats: stats), thresholds: store.thresholds))
            }
            return out
        case .year, .all:
            var months: [LocalDay] = []
            var cur = t.monthStart
            let limit = 12
            let stop = period == .all ? firstDay.monthStart : cur.adding(days: -400)
            while months.count < limit && cur >= stop {
                months.append(cur)
                cur = cur.adding(days: -1).monthStart
            }
            var out: [BeadPoint] = []
            for (i, m) in months.reversed().enumerated() {
                let end = min(m.adding(days: m.daysInMonth - 1), t)
                let name = Fmt.month.string(from: m.noon)
                out.append(BeadPoint.period(i, label: String(name.prefix(3)), title: Fmt.capitalized(name),
                                            summary: DayAnalytics.summary(from: m, to: end, stats: stats), thresholds: store.thresholds))
            }
            return out
        }
    }

    // MARK: Плитки

    private func tiles(_ s: PeriodSummary) -> some View {
        let prev = previousRange.map { DayAnalytics.summary(from: $0.from, to: $0.to, stats: stats) }
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        let has = s.daysWithData > 0
        return LazyVGrid(columns: columns, spacing: 10) {
            StatTile(title: "Спокойных дней", value: has ? "\(s.calmDays)" : "—", small: has ? "из \(s.daysWithData)" : "", tint: Theme.mint)
            StatTile(title: "Тревожных дней", value: has ? "\(s.anxiousDays)" : "—", small: has ? "из \(s.daysWithData)" : "", tint: Theme.pink)
            StatTile(title: "Медиана", value: s.medianOfDays.map { Fmt.num($0) } ?? "—",
                     small: (prev?.medianOfDays).map { "прошлая \(Fmt.num($0))" } ?? "", tint: Theme.lav)
            StatTile(title: "Эпизодов", value: has ? "\(s.episodeCount)" : "—",
                     small: (prev?.daysWithData ?? 0) > 0 ? "прошлая \(prev?.episodeCount ?? 0)" : "", tint: Theme.peach)
        }
    }

    // MARK: Причины и ощущения

    private var causesCard: some View {
        let causes = Array(HistoryAnalytics.topCauses(snapshot: store.active).prefix(4))
        let symptoms = Array(HistoryAnalytics.topSymptoms(snapshot: store.active).prefix(6))
        let maxCount = max(1, causes.map { $0.count }.max() ?? 1)
        let tints = [Theme.pink, Theme.peach, Theme.lav, Theme.mint]
        return VStack(alignment: .leading, spacing: 10) {
            H("Частые причины")
            if causes.isEmpty {
                Cap("Появятся, когда в эпизодах будет указана причина.")
            }
            ForEach(Array(causes.enumerated()), id: \.offset) { i, c in
                HStack(spacing: 10) {
                    Text(c.value).txt(13).lineLimit(1).frame(width: 112, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(tints[i % tints.count])
                            .frame(width: max(10, geo.size.width * CGFloat(c.count) / CGFloat(maxCount)), height: 10)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 16)
                    Text("\(c.count)").txt(12.5).foregroundStyle(pal.fg3).frame(width: 22, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            Sep()
            H("Ощущения в теле")
            if symptoms.isEmpty {
                Cap("Появятся, когда в эпизодах будут отмечены ощущения.")
            } else {
                FlowLayout {
                    ForEach(Array(symptoms.enumerated()), id: \.offset) { _, s in
                        Chip(text: "\(s.value) · \(s.count)")
                    }
                }
            }
        }
        .card()
    }

    // MARK: Истории

    @ViewBuilder
    private var storiesCard: some View {
        let list = store.histories
        if !list.isEmpty {
            let monthAgo = Date().addingTimeInterval(-30 * 86400)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    H("Истории")
                    Spacer()
                    Button { withAnimation { router.tab = .stories } } label: { Cap("все") }
                        .buttonStyle(.plain)
                }
                ForEach(Array(list.enumerated()), id: \.offset) { i, h in
                    if i > 0 { Sep() }
                    Button { router.cover = .story(h.meta.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Lab(h.title)
                                Cap("\(h.status.title.lowercased()) · повторений за 30 дней: \(HistoryAnalytics.recurrence(historyID: h.meta.id, snapshot: store.active, from: monthAgo, to: nil))")
                            }
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Spark(values: Array(HistoryAnalytics.episodes(historyID: h.meta.id, snapshot: store.active).compactMap { $0.peak }.suffix(6)),
                                  width: 70, height: 30, color: pal.fg)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    // MARK: Практики и разговоры

    private var practiceTiles: some View {
        let sessions = store.active.sessions.filter { $0.status != .running }
        let paired = sessions.filter { $0.status != .interrupted && $0.change != nil }
        let improved = paired.filter { ($0.change ?? 0) > 0 }.count
        let talk = ConversationAnalytics.stats(snapshot: store.active)
        var practiceCaption = "пока нет сессий"
        if !sessions.isEmpty {
            practiceCaption = paired.count >= PracticeAnalytics.minimumSample ? "легче в \(improved) из \(paired.count)" : "пока мало данных"
        }
        var talkCaption = "пока нет разговоров"
        if talk.count > 0 {
            var parts: [String] = []
            if let m = talk.meanChange, talk.pairedCount >= 3 {
                parts.append("в среднем " + (m > 0 ? "−" : (m < 0 ? "+" : "")) + Fmt.num(abs(m)))
            } else {
                parts.append("пока мало данных")
            }
            parts.append(Fmt.count(talk.withInsights, "вывод", "вывода", "выводов"))
            talkCaption = parts.joined(separator: " · ")
        }
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "wind").font(.system(size: 17, weight: .medium))
                Num(value: sessions.isEmpty ? "—" : "\(sessions.count)", small: Fmt.plural(sessions.count, "сессия", "сессии", "сессий"), size: 30)
                Cap(practiceCaption)
            }
            .card(14)
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "bubble.left").font(.system(size: 17, weight: .medium))
                Num(value: talk.count == 0 ? "—" : "\(talk.count)", small: Fmt.plural(talk.count, "разговор", "разговора", "разговоров"), size: 30)
                Cap(talkCaption)
            }
            .card(14)
        }
    }

    // MARK: Достижения

    private var achievements: some View {
        let earned = Set(store.active.achievements.map { $0.type })
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                H("Достижения")
                Spacer()
                Cap("\(earned.count) из \(AchievementType.allCases.count)")
            }
            Image(systemName: "star.fill")
                .font(.system(size: 78))
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFBE38E), Color(hex: 0xF4B64A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color(hex: 0xE9A93A).opacity(0.4), radius: 10, x: 0, y: 8)
                .rotation3DEffect(.degrees(spin ? 28 : -28), axis: (x: 0.1, y: 1, z: 0), perspective: 0.5)
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .accessibilityHidden(true)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { spin = true }
                }
            Cap("За действия, а не за отсутствие тревоги.")
                .frame(maxWidth: .infinity, alignment: .center)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AchievementType.allCases, id: \.self) { type in
                    let on = earned.contains(type)
                    VStack(spacing: 8) {
                        Image(systemName: type.icon).font(.system(size: 22, weight: .medium))
                        Text(type.title).txt(11.5, .semibold).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
                    .frame(height: 84)
                    .glass(20)
                    .opacity(on ? 1 : 0.42)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(on ? "получено" : "ещё нет")
                }
            }
        }
        .card()
    }

    // MARK: Победы

    private var winsCard: some View {
        let wins = Array(store.wins.prefix(6))
        return VStack(alignment: .leading, spacing: 4) {
            H("Маленькие победы").padding(.bottom, 6)
            if wins.isEmpty {
                Cap("Пока нет побед. Победа — это любое действие для себя.")
            }
            ForEach(wins, id: \.meta.id) { w in
                HStack(spacing: 4) {
                    Button { router.sheet = .editWin(w.meta.id) } label: { WinRow(text: w.text).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Изменить победу")
                    Button {
                        store.delete([w.meta.id])
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).opacity(0.4).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Удалить победу")
                }
            }
            Chip(text: "добавить победу", icon: "plus") { router.sheet = .addWin(nil) }
                .padding(.top, 6)
        }
        .card()
    }

    // MARK: Ссылки

    private var links: some View {
        let waiting = store.active.letters.filter { $0.canceledAt == nil && $0.openedAt == nil }.count
        let goals = store.active.goals.filter { $0.state == .active }
        let steps = store.active.goalSteps.filter { s in goals.contains { $0.meta.id == s.goalID } }
        let done = steps.filter { $0.isDone }.count
        return HStack(alignment: .top, spacing: 10) {
            linkTile("envelope", "Письма себе", waiting == 0 ? "написать себе в будущее" : "ждёт открытия: \(waiting)") { router.cover = .letters }
            linkTile("flag", "Цели", goals.isEmpty ? "пока нет целей" : "активных: \(goals.count) · этапов \(done) из \(steps.count)") { router.sheet = .goals }
        }
    }

    private func linkTile(_ icon: String, _ title: String, _ caption: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                Lab(title)
                Cap(caption)
            }
            .multilineTextAlignment(.leading)
            .card(14)
        }
        .buttonStyle(PressStyle())
    }

    private var monthCard: some View {
        Button { router.cover = .month } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    H("Как я изменилась за месяц")
                    Cap("Цифры и твои собственные записи, без выводов за тебя")
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Emblem(name: "PivRead", width: 76)
            }
            .card()
        }
        .buttonStyle(PressStyle())
    }
}

/// Плитка с цветным пятном в углу.
struct StatTile: View {
    @Environment(\.palette) private var pal
    let title: String
    let value: String
    var small: String = ""
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Lab(title)
            Spacer(minLength: 0)
            Num(value: value, small: small)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            Circle().fill(tint).frame(width: 140, height: 140).blur(radius: 26).opacity(0.9).offset(x: 46, y: 56)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glass(28)
        .accessibilityElement(children: .combine)
    }
}

/// «Как я изменилась за месяц»: только цифры и собственные записи.
struct MonthReviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = store.today
        let from = t.adding(days: -29)
        let cur = store.summary(from: from, to: t)
        let prev = store.summary(from: t.adding(days: -59), to: t.adding(days: -30))
        let since = from.noon.addingTimeInterval(-12 * 3600)
        let a = store.active
        let sessions = a.sessions.filter { $0.startedAt >= since && $0.status != .running }
        let talks = a.conversations.filter { $0.occurredAt >= since }
        let episodes = a.episodes.filter { $0.startedAt >= since }
        let insights = a.insights.filter { $0.meta.createdAt >= since }.sorted { $0.meta.createdAt > $1.meta.createdAt }.prefix(4)
        let wins = store.wins.filter { $0.occurredAt >= since }.prefix(6)
        let didParts: [String] = [Fmt.count(sessions.count, "практика", "практики", "практик"),
                                  Fmt.count(talks.count, "разговор", "разговора", "разговоров"),
                                  Fmt.count(episodes.count, "эпизод записан", "эпизода записано", "эпизодов записано")]
        let did = didParts.joined(separator: ", ") + "."
        TabScroll(bottom: 30) {
            HStack {
                RoundButton(icon: "chevron.left", label: "Назад") { dismiss() }
                Spacer()
                Cap("\(from.longTitle) — \(t.longTitle)")
            }
            BigHeader(title: "Месяц", subtitle: "как я изменилась")
            if cur.daysWithData == 0 {
                HStack(spacing: 12) {
                    Emblem(name: "PivRead", width: 70)
                    Cap("Пока нет записей — можно начать с одной отметки.")
                }
                .card()
            } else {
                HStack(spacing: 10) {
                    StatTile(title: "Средняя тревога", value: cur.averageOfDays.map { Fmt.num($0) } ?? "—",
                             small: prev.averageOfDays.map { "была \(Fmt.num($0))" } ?? "", tint: Theme.mint)
                    StatTile(title: "Тревожных дней", value: "\(cur.anxiousDays)",
                             small: prev.daysWithData > 0 ? "было \(prev.anxiousDays)" : "", tint: Theme.pink)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                H("Что я делала")
                Text(did)
                    .txt(14).fixedSize(horizontal: false, vertical: true)
            }
            .card()
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    H("Мои слова")
                    ForEach(Array(insights.enumerated()), id: \.offset) { i, x in
                        if i > 0 { Sep() }
                        Text("«\(x.text)»").txt(14.5).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()
            }
            if !wins.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    H("Мои победы").padding(.bottom, 6)
                    ForEach(Array(wins.enumerated()), id: \.offset) { _, w in
                        WinRow(text: w.text)
                    }
                }
                .card()
            }
            Emblem(name: "PivStar", width: 140).frame(maxWidth: .infinity)
            Cap("Только цифры и твои записи. Выводы — твои.")
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
