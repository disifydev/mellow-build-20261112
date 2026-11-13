import SwiftUI
import PivchikDomain

/// Меню «Новая запись».
struct NewMenuSheet: View {
    @Binding var sheet: SheetRoute?
    @EnvironmentObject private var store: AppStore

    var body: some View {
        SheetScroll {
            Text("Новая запись").display(30)
            row("pencil", "Отметка состояния", "оценка 0–10 и заметка, 10 секунд") { sheet = .checkIn }
            row("bolt", "Тревожный эпизод", "причина, мысли, ощущения, начало и конец") { sheet = .episode(nil) }
            row("bubble.left", "Разговор с ИИ", "вставить текст, оценки до и после, вывод") { sheet = .conversation(nil) }
            row("moon", "Итог дня", "что помогло, что было трудно") { sheet = .evening(store.today) }
        }
    }

    private func row(_ icon: String, _ title: String, _ caption: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 19, weight: .medium)).frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Lab(title)
                    Cap(caption)
                }
                Spacer(minLength: 0)
            }
            .card()
        }
        .buttonStyle(PressStyle())
    }
}

/// Выбор одной истории чипами.
struct StoryPicker: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: UUID?

    var body: some View {
        if store.histories.isEmpty {
            Cap("Историй пока нет. Их можно создать на вкладке «Истории».")
        } else {
            FlowLayout {
                ForEach(store.histories, id: \.meta.id) { h in
                    Chip(text: h.title, isOn: selection == h.meta.id) {
                        selection = selection == h.meta.id ? nil : h.meta.id
                    }
                }
            }
        }
    }
}

/// Выбор нескольких значений чипами.
struct MultiChips: View {
    let options: [String]
    @Binding var selection: Set<String>
    var prefix: String = ""

    var body: some View {
        FlowLayout {
            ForEach(options, id: \.self) { o in
                Chip(text: prefix + o, isOn: selection.contains(o)) {
                    if selection.contains(o) { selection.remove(o) } else { selection.insert(o) }
                }
            }
        }
    }
}

/// Дата и время события в стеклянной строке.
struct DateRow: View {
    let title: String
    @Binding var date: Date
    var range: ClosedRange<Date>? = nil
    var components: DatePickerComponents = [.date, .hourAndMinute]

    var body: some View {
        HStack {
            Text(title).txt(14.5)
            Spacer(minLength: 4)
            if let range {
                DatePicker(title, selection: $date, in: range, displayedComponents: components).labelsHidden()
            } else {
                DatePicker(title, selection: $date, in: ...Date(), displayedComponents: components).labelsHidden()
            }
        }
        .environment(\.locale, Fmt.ru)
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .frame(maxWidth: .infinity)
        .glass(18)
    }
}

/// Быстрая отметка состояния.
struct CheckInSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var value: Int = 3
    @State private var note = ""
    @State private var date = Date()
    @State private var historyID: UUID?

    var body: some View {
        SheetScroll {
            BigHeader(title: "Отметка", subtitle: "как ты сейчас", size: 30)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Lab("Уровень тревоги")
                    Spacer()
                    Text("\(value)").display(30).monospacedDigit()
                }
                LevelSlider(value: $value, label: "Уровень тревоги")
                Cap(LevelInfo.of(value).name)
            }
            .card()
            MField(title: "Заметка", text: $note, placeholder: "Что сейчас происходит?", lines: 2)
            DateRow(title: "Когда", date: $date)
            FieldGroup(title: "История") { StoryPicker(selection: $historyID) }
            CTAButton(title: "Сохранить отметку") {
                store.addCheckIn(anxiety: value, note: note, at: date, historyIDs: historyID.map { [$0] } ?? [])
                store.level = value
                dismiss()
            }
            Cap("Запись старше суток будет помечена «задним числом».")
        }
        .onAppear { value = store.level }
    }
}

/// Форма тревожного эпизода. Все поля, кроме оценки, можно пропустить.
struct EpisodeSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let historyID: UUID?

    @State private var peak: Int = 5
    @State private var start = Date()
    @State private var ongoing = true
    @State private var end = Date()
    @State private var cause = ""
    @State private var thoughts = ""
    @State private var symptoms: Set<String> = []
    @State private var story: UUID?
    @State private var tags: Set<String> = []
    @State private var customTag = ""
    @State private var coping = ""
    @State private var insight = ""

    private var tagOptions: [String] {
        var all = ["связь", "вечер", "работа", "дорога"]
        let used = store.active.episodes.flatMap { $0.tags } + store.active.checkIns.flatMap { $0.tags }
        for t in used + Array(tags) where !all.contains(t) { all.append(t) }
        return all
    }

    var body: some View {
        SheetScroll {
            BigHeader(title: "Эпизод", subtitle: "что случилось", size: 30)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Lab("Пик тревоги")
                    Spacer()
                    Text("\(peak)").display(30).monospacedDigit()
                }
                LevelSlider(value: $peak, label: "Пик тревоги")
            }
            .card()
            FieldGroup(title: "Начало и конец") {
                DateRow(title: "Начало", date: $start)
                Toggle(isOn: $ongoing) { Text("Ещё продолжается").txt(14.5) }
                    .tint(Theme.mint)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .glass(18)
                if !ongoing {
                    DateRow(title: "Конец", date: $end, range: start...max(start, Date()))
                }
            }
            MField(title: "Причина и контекст", text: $cause, placeholder: "Что произошло перед этим?", lines: 2)
            MField(title: "Мысли и страхи", text: $thoughts, placeholder: "Что я себе говорю?", lines: 2)
            FieldGroup(title: "Ощущения в теле") {
                MultiChips(options: BodySymptoms.common, selection: $symptoms)
            }
            FieldGroup(title: "История") { StoryPicker(selection: $story) }
            FieldGroup(title: "Теги") {
                MultiChips(options: tagOptions, selection: $tags, prefix: "#")
                MField(title: "Свой тег", text: $customTag, placeholder: "например: учёба")
            }
            MField(title: "Что я сделала", text: $coping, placeholder: "Можно заполнить позже", lines: 2)
            MField(title: "Что я поняла", text: $insight, placeholder: "Вывод попадёт в «Открытия»", lines: 2)
            CTAButton(title: "Сохранить эпизод", action: save)
            Cap("Все поля, кроме оценки, можно пропустить.")
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear {
            peak = max(store.level, 5)
            story = historyID
        }
        .onChange(of: start) { _, new in
            if end < new { end = new }
        }
    }

    private func save() {
        var allTags = Array(tags).sorted()
        if let t = customTag.replacingOccurrences(of: "#", with: "").nilIfEmpty, !allTags.contains(t) { allTags.append(t) }
        let rec = EpisodeRecord(meta: store.meta(), startedAt: start, endedAt: ongoing ? nil : max(start, end), zoneID: store.zone,
                                peak: peak, cause: cause.nilIfEmpty, thoughts: thoughts.nilIfEmpty,
                                bodySymptoms: BodySymptoms.common.filter { symptoms.contains($0) },
                                coping: coping.nilIfEmpty, insights: insight.nilIfEmpty, tags: allTags,
                                historyIDs: story.map { [$0] } ?? [])
        store.addEpisode(rec)
        store.level = peak
        dismiss()
    }
}

/// Разговор с ИИ: вставленный текст, оценки до и после, вывод.
struct ConversationSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let historyID: UUID?

    @State private var pasted = ""
    @State private var before: Int?
    @State private var after: Int?
    @State private var summary = ""
    @State private var insight = ""
    @State private var story: UUID?
    @State private var date = Date()

    var body: some View {
        SheetScroll {
            BigHeader(title: "Разговор", subtitle: "с ИИ", size: 30)
            MField(title: "Текст разговора", text: $pasted, placeholder: "Вставь сюда текст — он останется только на устройстве", lines: 3)
            LevelCard(title: "Тревога до", value: $before, fallback: 5)
            LevelCard(title: "Тревога после", value: $after, fallback: 3, hint: "Оценки можно пропустить. Тогда разговор не войдёт в расчёт изменений.")
            MField(title: "Коротко: о чём", text: $summary, placeholder: "Что разобрали", lines: 2)
            MField(title: "Вывод", text: $insight, placeholder: "Что я поняла", lines: 2)
            FieldGroup(title: "История") { StoryPicker(selection: $story) }
            DateRow(title: "Когда", date: $date)
            CTAButton(title: "Сохранить разговор") {
                let rec = ConversationRecord(meta: store.meta(), occurredAt: date, zoneID: store.zone, before: before, after: after,
                                             pastedText: pasted.nilIfEmpty, summary: summary.nilIfEmpty, insights: insight.nilIfEmpty,
                                             historyIDs: story.map { [$0] } ?? [])
                store.addConversation(rec)
                dismiss()
            }
        }
        .onAppear { story = historyID }
    }
}

/// Вечерний итог: один на календарный день.
struct EveningSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let day: LocalDay

    @State private var overall: Int?
    @State private var helped = ""
    @State private var hard = ""
    @State private var victory = ""
    @State private var summary = ""
    @State private var saved = false

    var body: some View {
        ZStack {
            SheetScroll {
                HStack(alignment: .top) {
                    BigHeader(title: "Итог дня", subtitle: day.longTitle, size: 30)
                    Emblem(name: "PivSleep", width: 84)
                }
                LevelCard(title: "Общее состояние", value: $overall, fallback: 3,
                          hint: "В среднюю дня эта оценка не входит — она показывается отдельно.")
                MField(title: "Что помогло", text: $helped, placeholder: "Прогулка, разговор, дыхание")
                MField(title: "Что было трудно", text: $hard, placeholder: "Ожидание ответа")
                MField(title: "Маленькая победа", text: $victory, placeholder: "Не проверяла телефон целый час")
                MField(title: "Свободно", text: $summary, placeholder: "Что хочется запомнить", lines: 2)
                CTAButton(title: "Сохранить итог", action: save)
            }
            if saved { StarBurst() }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let r = store.reflection(on: day) else { return }
        overall = r.overallAnxiety
        helped = r.helped ?? ""
        hard = r.hard ?? ""
        victory = r.victory ?? ""
        summary = r.summary ?? ""
    }

    private func save() {
        store.saveReflection(day: day, overall: overall, helped: helped, hard: hard, victory: victory, summary: summary)
        Haptics.success(store.settings.hapticsEnabled)
        if victory.nilIfEmpty != nil {
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
        } else {
            dismiss()
        }
    }
}

/// План «Позаботиться о себе»: любой шаг можно пропустить.
struct PlanSheet: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss

    private var insight: String {
        let list = store.active.insights.sorted { ($0.isFavorite ? 1 : 0, $0.meta.createdAt) > ($1.isFavorite ? 1 : 0, $1.meta.createdAt) }
        if let first = list.first { return "«\(first.text)»" }
        return "пока нет — он появится после эпизода или разговора"
    }

    private var bestPractice: String {
        let stats = PracticeAnalytics.stats(snapshot: store.active)
        let best = stats.values.filter { $0.hasEnoughData }.max { ($0.medianChange ?? 0) < ($1.medianChange ?? 0) }
        if let best, let p = store.practice(id: best.practiceID) { return "чаще всего помогает «\(p.title)»" }
        return "можно начать с дыхания 4–6"
    }

    var body: some View {
        SheetScroll {
            BigHeader(title: "Мой план", subtitle: "позаботиться о себе", size: 30)
            VStack(alignment: .leading, spacing: 13) {
                step("Отметить состояние", "сейчас на дуге: \(store.level) из 10")
                step("Выбрать практику", bestPractice)
                step("Открыть свой вывод", insight)
                step("Оценить изменения", "после практики")
            }
            Cap("Любой шаг можно пропустить.")
            CTAButton(title: "Начать с дыхания", icon: "wind") {
                dismiss()
                guard let p = store.practice(.breathing46) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    router.cover = .practice(p.meta.id, 180, false, nil)
                }
            }
        }
    }

    private func step(_ title: String, _ caption: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Theme.lav).frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Lab(title)
                Cap(caption)
            }
        }
    }
}
