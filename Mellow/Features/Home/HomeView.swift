import SwiftUI
import PivchikDomain

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var pal

    private var info: LevelInfo { LevelInfo.of(store.level) }

    var body: some View {
        TabScroll {
            BigHeader(title: (Features.appleSignIn ? store.appleName : nil).map { "Привет, \($0)." } ?? "Привет.", subtitle: "Как ты сейчас?") {
                RoundButton(icon: "person", label: "Профиль и настройки") { router.cover = .profile }
            }
            stage
            CTAButton(title: "Отметить состояние", trailingIcon: "arrow.right", action: mark)
            quickActions
            eveningCard.id("evening")
        }
    }

    // MARK: Шкала с цифрой

    private var stage: some View {
        ZStack {
            DialView(level: $store.level, haptics: store.settings.hapticsEnabled)
            VStack(spacing: 2) {
                Text("\(store.level)").display(104).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: store.level)
                H(info.name)
                Cap(info.phrase)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .frame(maxWidth: 190)
            .offset(y: 6)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 292)
        .padding(.vertical, -8)
    }


    private func mark() {
        store.addCheckIn(anxiety: store.level, note: info.name)
        Haptics.success(store.settings.hapticsEnabled)
        router.diaryDay = store.today
        withAnimation { router.tab = .diary }
    }

    // MARK: Быстрые действия

    private var quickActions: some View {
        HStack(spacing: 8) {
            quick("wind", "Подышать") {
                if let p = store.practice(.breathing46) { router.cover = .practice(p.meta.id, 180, false, nil) }
            }
            quick("bolt", "Записать эпизод") { router.sheet = .episode(nil) }
            quick("lightbulb", "Разобрать мысли") {
                router.practiceGroup = .thoughts
                withAnimation { router.tab = .practice }
            }
            quick("list.bullet", "Мой план") { router.sheet = .plan }
        }
    }

    private func quick(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 19, weight: .medium))
                Text(title).txt(11.5, .semibold).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .glass(22)
        }
        .buttonStyle(PressStyle())
    }

    // MARK: Итог дня

    private var eveningCard: some View {
        let done = store.reflection(on: store.today) != nil
        return Button {
            router.sheet = .evening(store.today)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    H("Вечерний итог дня")
                    Cap("Что помогло, что было трудно, маленькая победа. " + (done ? "Заполнен — можно дополнить." : "Ещё не заполнен."))
                }
                Spacer(minLength: 0)
                Emblem(name: "PivSleep", width: 74)
            }
            .card()
        }
        .buttonStyle(PressStyle())
    }
}

/// Карточка графика: заголовок, переключатель ряда, бусины, подпись выбранного дня.
struct ChartCard: View {
    @Environment(\.palette) private var pal
    let title: String
    let points: [BeadPoint]
    var delta: String? = nil
    var isDay: Bool = true
    @Binding var selected: Int?
    @State private var series: BeadSeries = .average

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                H(title)
                Spacer()
                if let delta {
                    Chip(text: delta, height: 30, bold: true)
                }
            }
            SegControl(items: [(BeadSeries.average, "Средняя"), (BeadSeries.peak, "Пик"), (BeadSeries.episodes, "Эпизоды")], selection: $series)
            BeadsChart(points: points, series: series, selected: $selected)
            if points.contains(where: { $0.hasData }) {
                BeadInfo(point: points.first { $0.id == selected }, isDay: isDay)
            } else {
                Cap("Пока нет записей — можно начать с одной отметки.")
            }
        }
        .card()
    }
}

extension AppStore {
    /// Точки по дням: день без записей остаётся пробелом.
    func dayPoints(from: LocalDay, to: LocalDay, stats: [LocalDay: DayStats]? = nil) -> [BeadPoint] {
        let series = DayAnalytics.series(from: from, to: to, stats: stats ?? dayStats)
        var out: [BeadPoint] = []
        for (i, item) in series.enumerated() {
            out.append(BeadPoint.day(i, item.day, item.stats))
        }
        return out
    }

    /// «−36% к прошлой»: средняя за 7 дней против предыдущих 7. Без данных — ничего.
    func weekDelta() -> String? {
        let t = today
        let cur = summary(from: t.adding(days: -6), to: t).averageOfDays
        let prev = summary(from: t.adding(days: -13), to: t.adding(days: -7)).averageOfDays
        guard let cur, let prev, prev > 0 else { return nil }
        let p = Int(((cur - prev) / prev * 100).rounded())
        return "\(p <= 0 ? "−" : "+")\(abs(p))% к прошлой"
    }
}
