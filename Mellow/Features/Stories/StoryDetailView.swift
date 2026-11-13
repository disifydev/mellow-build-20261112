import SwiftUI
import PivchikDomain

/// Событие хронологии истории.
private struct StoryEvent: Identifiable {
    let id: String
    let date: Date
    let text: String
    let color: Color
}

struct StoryDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss
    let historyID: UUID

    @State private var sheet: SheetRoute?
    @State private var cover: CoverRoute?
    @State private var newGoal = ""
    @State private var askGoal = false

    var body: some View {
        Group {
            if let h = store.history(historyID) {
                content(h)
            } else {
                VStack(spacing: 14) {
                    Cap("История удалена.")
                    CTAButton(title: "Закрыть", small: true) { dismiss() }
                }
                .padding(20)
            }
        }
        .modifier(SheetHost(sheet: $sheet))
        .modifier(CoverHost(cover: $cover))
        .alert("Новая цель", isPresented: $askGoal) {
            TextField("Например: реже проверять телефон", text: $newGoal)
            Button("Добавить") {
                if let t = newGoal.nilIfEmpty { store.addGoal(title: t, historyID: historyID) }
                newGoal = ""
            }
            Button("Отмена", role: .cancel) { newGoal = "" }
        }
    }

    private func content(_ h: HistoryRecord) -> some View {
        let a = store.active
        let episodes = HistoryAnalytics.episodes(historyID: h.meta.id, snapshot: a)
        let talks = a.conversations.filter { $0.historyIDs.contains(h.meta.id) }.sorted { $0.occurredAt > $1.occurredAt }
        let sessions = a.sessions.filter { $0.historyIDs.contains(h.meta.id) && $0.status != .running }
        return TabScroll(bottom: 30) {
            HStack {
                RoundButton(icon: "chevron.left", label: "Назад") { dismiss() }
                Spacer()
            }
            BigHeader(title: h.title, subtitle: "с \(Fmt.dayMonth.string(from: h.startedAt))", size: 31)
            SegControl(items: HistoryStatus.allCases.map { ($0, $0.title) },
                       selection: Binding(get: { h.status }, set: { store.setStatus($0, historyID: h.meta.id) }))
            HStack(spacing: 8) {
                kpi(episodes.count, Fmt.plural(episodes.count, "эпизод", "эпизода", "эпизодов"))
                kpi(talks.count, Fmt.plural(talks.count, "разговор", "разговора", "разговоров"))
                kpi(sessions.count, Fmt.plural(sessions.count, "практика", "практики", "практик"))
            }
            intensity(h, episodes)
            goals(h)
            talksCard(h, talks)
            insightsCard(h)
            timeline(h, episodes: episodes, talks: talks, sessions: sessions).id("timeline")
            winsCard(h)
            HStack(spacing: 10) {
                CTAButton(title: "Эпизод", icon: "plus", small: true) { sheet = .episode(h.meta.id) }
                CTAButton(title: "Практика", icon: "wind", small: true) {
                    if let p = store.practice(.breathing46) { cover = .practice(p.meta.id, 180, false, h.meta.id) }
                }
            }
            if h.status == .easier || h.status == .resolved {
                Cap("Ты уже прошла большую часть пути по этой теме.")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func kpi(_ value: Int, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)").display(26).monospacedDigit()
            Cap(caption)
        }
        .card(12, radius: 22)
    }

    private func intensity(_ h: HistoryRecord, _ episodes: [EpisodeRecord]) -> some View {
        let peaks = Array(episodes.compactMap { $0.peak }.suffix(12))
        let cal = Cal.current
        let now = Date()
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
        let prevStart = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let thisMonth = HistoryAnalytics.recurrence(historyID: h.meta.id, snapshot: store.active, from: monthStart, to: nil)
        let lastMonth = HistoryAnalytics.recurrence(historyID: h.meta.id, snapshot: store.active, from: prevStart, to: monthStart)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                H("Интенсивность")
                Spacer()
                Cap("пик эпизодов")
            }
            if peaks.isEmpty {
                Cap("Пока нет эпизодов с оценкой.")
            } else {
                Spark(values: peaks, width: 300, height: 64, color: pal.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Cap("Повторений за \(Fmt.month.string(from: now)): \(thisMonth), за \(Fmt.month.string(from: prevStart)): \(lastMonth)")
        }
        .card()
    }

    @ViewBuilder
    private func goals(_ h: HistoryRecord) -> some View {
        let list = store.active.goals.filter { $0.historyID == h.meta.id }.sorted { $0.meta.createdAt < $1.meta.createdAt }
        ForEach(list, id: \.meta.id) { g in
            GoalCard(goal: g)
        }
        if list.isEmpty {
            Button { askGoal = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "flag").font(.system(size: 17, weight: .medium))
                    VStack(alignment: .leading, spacing: 3) {
                        Lab("Поставить цель")
                        Cap("Маленькие этапы, которые можно отмечать")
                    }
                    Spacer(minLength: 0)
                }
                .card()
            }
            .buttonStyle(PressStyle())
        }
    }

    private func talksCard(_ h: HistoryRecord, _ talks: [ConversationRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                H("Разговоры с ИИ")
                Spacer()
                Chip(text: "добавить", icon: "plus", height: 30) { sheet = .conversation(h.meta.id) }
            }
            if talks.isEmpty {
                Cap("Пока нет разговоров по этой теме.")
            }
            ForEach(Array(talks.prefix(5).enumerated()), id: \.offset) { i, t in
                if i > 0 { Sep() }
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Lab(Fmt.dayMonthShort.string(from: t.occurredAt))
                        Spacer()
                        let r = ConversationAnalytics.ratings(for: t, sessions: store.active.sessions)
                        if let b = r.before, let af = r.after {
                            Chip(text: "\(b) → \(af)", height: 26, bold: true)
                        }
                    }
                    Cap(t.summary ?? t.insights ?? "Без описания")
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func insightsCard(_ h: HistoryRecord) -> some View {
        let items = store.active.insights.filter { $0.historyIDs.contains(h.meta.id) }.sorted { $0.meta.createdAt > $1.meta.createdAt }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb").font(.system(size: 17, weight: .medium))
                    H("Открытия")
                }
                ForEach(Array(items.enumerated()), id: \.offset) { i, x in
                    if i > 0 { Sep() }
                    Text("«\(x.text)»").txt(14.5).fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }

    private func events(_ h: HistoryRecord, episodes: [EpisodeRecord], talks: [ConversationRecord], sessions: [PracticeSessionRecord]) -> [StoryEvent] {
        var out: [StoryEvent] = []
        out.append(StoryEvent(id: "start", date: h.startedAt, text: "История начата", color: Theme.lav))
        for e in episodes {
            var text = "Эпизод"
            if let p = e.peak { text += ", пик \(p)" }
            if e.isRetrospective { text += " · добавлено задним числом" }
            out.append(StoryEvent(id: e.meta.id.uuidString, date: e.startedAt, text: text, color: Theme.pink))
        }
        for t in talks {
            out.append(StoryEvent(id: t.meta.id.uuidString, date: t.occurredAt, text: "Разговор с ИИ: " + (t.summary ?? "без описания"), color: Theme.lav))
        }
        for s in sessions {
            var text = "Практика «\(store.practice(id: s.practiceID)?.title ?? s.practiceType.info.title)»"
            if let b = s.before, let af = s.after { text += ": \(b) → \(af)" }
            out.append(StoryEvent(id: s.meta.id.uuidString, date: s.startedAt, text: text, color: Theme.mint))
        }
        for c in store.active.statusChanges where c.historyID == h.meta.id {
            out.append(StoryEvent(id: c.meta.id.uuidString, date: c.changedAt,
                                  text: "Статус: \(c.fromStatus.title.lowercased()) → \(c.toStatus.title.lowercased())", color: Theme.mint))
        }
        return out.sorted { $0.date > $1.date }
    }

    private func timeline(_ h: HistoryRecord, episodes: [EpisodeRecord], talks: [ConversationRecord], sessions: [PracticeSessionRecord]) -> some View {
        let list = events(h, episodes: episodes, talks: talks, sessions: sessions)
        return VStack(alignment: .leading, spacing: 10) {
            H("Хронология")
            VStack(alignment: .leading, spacing: 13) {
                ForEach(list.prefix(30)) { e in
                    HStack(alignment: .top, spacing: 11) {
                        Circle().fill(e.color).frame(width: 10, height: 10).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Lab(Fmt.dayMonthShort.string(from: e.date))
                            Cap(e.text)
                        }
                    }
                }
            }
            if list.count > 30 { Cap("Показаны последние 30 событий.") }
        }
        .card()
    }

    private func winsCard(_ h: HistoryRecord) -> some View {
        let wins = store.wins.filter { $0.historyIDs.contains(h.meta.id) }
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                H("Победы по теме")
                Spacer()
                Chip(text: "добавить", icon: "plus", height: 30) { sheet = .addWin(h.meta.id) }
            }
            .padding(.bottom, 6)
            if wins.isEmpty {
                Cap("Здесь появятся победы, связанные с этой историей.")
            }
            ForEach(wins, id: \.meta.id) { w in
                WinRow(text: w.text)
            }
        }
        .card()
    }
}

/// Цель с этапами: этапы отмечаются, новый этап добавляется строкой.
struct GoalCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    let goal: GoalRecord
    @State private var newStep = ""
    @State private var burst = 0

    var body: some View {
        let steps = store.active.goalSteps.filter { $0.goalID == goal.meta.id }.sorted { $0.order < $1.order }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flag").font(.system(size: 17, weight: .medium))
                H(goal.title)
                Spacer(minLength: 0)
                if goal.state == .done { Chip(text: "выполнена", height: 26) }
            }
            ForEach(steps, id: \.meta.id) { s in
                Button {
                    if !s.isDone { burst += 1 }
                    store.toggleStep(s.meta.id)
                    Haptics.tick(store.settings.hapticsEnabled)
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(s.isDone ? Theme.mint : Color.clear)
                            Circle().strokeBorder(s.isDone ? Color.clear : pal.fg2, lineWidth: 1.5)
                            if s.isDone {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.ink)
                            }
                        }
                        .frame(width: 22, height: 22)
                        Text(s.title).txt(14.5).strikethrough(s.isDone).opacity(s.isDone ? 0.55 : 1)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.title)
                .accessibilityValue(s.isDone ? "выполнен" : "не выполнен")
            }
            HStack(spacing: 8) {
                TextField("", text: $newStep, prompt: Text("Новый этап").foregroundColor(pal.fg2))
                    .txt(14)
                    .submitLabel(.done)
                    .onSubmit(addStep)
                    .accessibilityLabel("Новый этап цели")
                Button(action: addStep) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .opacity(newStep.trimmed.isEmpty ? 0.35 : 1)
                .accessibilityLabel("Добавить этап")
            }
            .padding(.top, 2)
        }
        .card()
        .overlay {
            if burst > 0 { StarBurst().id(burst) }
        }
    }

    private func addStep() {
        guard let t = newStep.nilIfEmpty else { return }
        store.addGoalStep(goalID: goal.meta.id, title: t)
        newStep = ""
    }
}

/// Все цели.
struct GoalsSheet: View {
    @EnvironmentObject private var store: AppStore
    @State private var title = ""

    var body: some View {
        let goals = store.active.goals.sorted { $0.meta.createdAt < $1.meta.createdAt }
        SheetScroll {
            BigHeader(title: "Цели", subtitle: "маленькими этапами", size: 30)
            if goals.isEmpty {
                Cap("Целей пока нет. Цель — это не «перестать тревожиться», а действие, которое в твоей власти.")
            }
            ForEach(goals, id: \.meta.id) { g in
                GoalCard(goal: g)
            }
            MField(title: "Новая цель", text: $title, placeholder: "Например: реже проверять телефон")
            CTAButton(title: "Добавить цель", icon: "plus", small: true) {
                guard let t = title.nilIfEmpty else { return }
                store.addGoal(title: t, historyID: nil)
                title = ""
            }
            .opacity(title.trimmed.isEmpty ? 0.5 : 1)
        }
    }
}
