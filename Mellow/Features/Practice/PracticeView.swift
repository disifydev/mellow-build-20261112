import SwiftUI
import PivchikDomain

struct PracticeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var pal
    @State private var index = 0
    @State private var seconds = 180

    private var list: [PracticeDefinitionRecord] {
        store.practices.filter { $0.type.info.group == router.practiceGroup }
    }

    private var current: PracticeDefinitionRecord? {
        let l = list
        guard !l.isEmpty else { return nil }
        return l[min(max(index, 0), l.count - 1)]
    }

    var body: some View {
        TabScroll {
            BigHeader(title: "Практики", subtitle: "для себя") {
                favouriteButton
            }
            SegControl(items: PracticeGroup.allCases.map { ($0, $0.title) }, selection: $router.practiceGroup)
            DrumView(items: list, index: $index, haptics: store.settings.hapticsEnabled)
                .padding(.horizontal, -20)
            durations
            CTAButton(title: (current?.type.isTimed ?? true) ? "Начать практику" : "Открыть по шагам", icon: "play.fill") {
                guard let p = current else { return }
                router.cover = .practice(p.meta.id, seconds, false, nil)
            }
            Cap("Дыши, как удобно. Прекрати, если станет неприятно.")
                .frame(maxWidth: .infinity, alignment: .center)
            if let p = current, p.type == .freeRhythm {
                RhythmEditor(practice: p)
            }
            statsCard.id("stats")
            recentCard.id("recent")
        }
        .onChange(of: router.practiceGroup) { _, _ in index = 0 }
    }

    private var favouriteButton: some View {
        let fav = current?.isFavorite ?? false
        return RoundButton(icon: fav ? "heart.fill" : "heart", label: fav ? "Убрать из избранного" : "В избранное",
                           tint: fav ? Color(hex: 0xE0569B) : nil) {
            guard let p = current else { return }
            store.update(\Snapshot.practices, id: p.meta.id) { $0.isFavorite.toggle() }
        }
    }

    private var durations: some View {
        let timed = current?.type.isTimed ?? true
        return SegControl(items: SessionTimer.allowedDurations.map { (Int($0), "\(Int($0) / 60) мин") }, selection: $seconds)
            .opacity(timed ? 1 : 0.35)
            .disabled(!timed)
    }

    // MARK: Что помогает

    private var statsCard: some View {
        let stats = PracticeAnalytics.stats(snapshot: store.active)
        let rows = store.practices.compactMap { p -> (PracticeDefinitionRecord, PracticeStats)? in
            guard let s = stats[p.meta.id] else { return nil }
            return (p, s)
        }.sorted { $0.1.sessionCount > $1.1.sessionCount }
        return VStack(alignment: .leading, spacing: 10) {
            H("Что помогает тебе")
            if rows.isEmpty {
                Cap("Пока нет сессий. После первой практики здесь появится, что тебе помогает.")
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 { Sep() }
                PracticeStatRow(title: row.0.title, stats: row.1)
            }
            Cap("Снижение после практики не доказывает, что его вызвала только она.")
        }
        .card()
    }

    private var recentCard: some View {
        let sessions = store.active.sessions.filter { $0.status != .running }.sorted { $0.startedAt > $1.startedAt }.prefix(5)
        return VStack(alignment: .leading, spacing: 10) {
            H("Последние сессии")
            if sessions.isEmpty {
                Cap("Сессий пока нет.")
            }
            ForEach(Array(sessions.enumerated()), id: \.offset) { i, s in
                if i > 0 { Sep() }
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Lab(sessionTitle(s))
                        Cap(sessionCaption(s))
                    }
                    Spacer(minLength: 4)
                    Chip(text: sessionChange(s), height: 28, bold: true)
                }
            }
        }
        .card()
    }

    private func sessionTitle(_ s: PracticeSessionRecord) -> String {
        var t = store.practice(id: s.practiceID)?.title ?? s.practiceType.info.title
        if s.practiceType.isTimed, let d = s.activeDuration, d >= 1 { t += " · " + Fmt.duration(d) }
        return t
    }

    private func sessionCaption(_ s: PracticeSessionRecord) -> String {
        var parts = [Fmt.relative(s.startedAt)]
        if let f = s.feltResult { parts.append(f.title.lowercased()) }
        if s.status == .endedEarly { parts.append("завершена раньше") }
        if s.status == .interrupted { parts.append("прервана") }
        return parts.joined(separator: " · ")
    }

    private func sessionChange(_ s: PracticeSessionRecord) -> String {
        if let b = s.before, let a = s.after { return "\(b) → \(a)" }
        return "без оценки"
    }
}

/// Строка аналитики одной практики. При выборке меньше трёх — «пока мало данных».
struct PracticeStatRow: View {
    @Environment(\.palette) private var pal
    let title: String
    let stats: PracticeStats

    var body: some View {
        let change = stats.hasEnoughData ? stats.meanChange : nil
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Lab(title)
                Spacer()
                Lab(changeText(change))
            }
            GeometryReader { geo in
                Capsule()
                    .fill(change == nil ? pal.fg2 : ((change ?? 0) > 0 ? Theme.mint : Theme.lav))
                    .frame(width: geo.size.width * barShare(change), height: 10)
            }
            .frame(height: 10)
            Cap(caption)
        }
    }

    private func changeText(_ change: Double?) -> String {
        guard let change else { return "—" }
        if change > 0 { return "−" + Fmt.num(change) }
        if change < 0 { return "+" + Fmt.num(-change) }
        return "0"
    }

    private func barShare(_ change: Double?) -> CGFloat {
        guard let change, change > 0 else { return 0.08 }
        return CGFloat(min(1, max(0.08, change * 0.18)))
    }

    private var caption: String {
        var parts = [Fmt.count(stats.sessionCount, "сессия", "сессии", "сессий")]
        if stats.hasEnoughData {
            parts.append("легче в \(stats.improvedCount) из \(stats.pairedCount)")
            if let m = stats.medianChange { parts.append("медиана " + (m > 0 ? "−" : "") + Fmt.num(abs(m))) }
            if let d = stats.medianDuration { parts.append(Fmt.duration(d)) }
        } else {
            parts.append("пока мало данных")
            if !stats.changes.isEmpty {
                parts.append("изменения: " + stats.changes.map { $0 > 0 ? "−\($0)" : ($0 < 0 ? "+\(-$0)" : "0") }.joined(separator: ", "))
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// Настройка «Своего ритма»: вдох и выдох от 1 до 15 секунд.
struct RhythmEditor: View {
    @EnvironmentObject private var store: AppStore
    let practice: PracticeDefinitionRecord

    var body: some View {
        let p = practice.pattern
        VStack(alignment: .leading, spacing: 8) {
            H("Свой ритм")
            stepper("Вдох", Int(p.inhale)) { v in set(inhale: Double(v), exhale: p.exhale) }
            stepper("Выдох", Int(p.exhale)) { v in set(inhale: p.inhale, exhale: Double(v)) }
        }
        .card()
    }

    private func stepper(_ title: String, _ value: Int, _ change: @escaping (Int) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: { change($0) }), in: 1...15) {
            Text("\(title): \(value) с").txt(14.5)
        }
    }

    private func set(inhale: Double, exhale: Double) {
        let pattern = BreathPattern(inhale: inhale, exhale: exhale)
        guard pattern.isValid else { return }
        store.update(\Snapshot.practices, id: practice.meta.id) { $0.settings.pattern = pattern }
    }
}
