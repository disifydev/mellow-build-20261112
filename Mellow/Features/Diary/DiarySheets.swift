import SwiftUI
import PivchikDomain

/// Меню «Новая запись». Из дневника на прошлом дне записи создаются в этот день.
struct NewMenuSheet: View {
    @Binding var sheet: SheetRoute?
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router

    private var day: LocalDay { router.composeDay ?? store.today }

    var body: some View {
        SheetScroll {
            Text("Новая запись").display(30)
            if day != store.today {
                Cap("Записи попадут в \(day.longTitle) — время можно поменять в форме.")
            }
            row("pencil", "Отметка состояния", "оценка 0–10 и заметка, 10 секунд") { sheet = .checkIn }
            row("bolt", "Тревожный эпизод", "причина, мысли, ощущения, начало и конец") { sheet = .episode(nil) }
            row("bubble.left", "Разговор с ИИ", "вставить текст, оценки до и после, вывод") { sheet = .conversation(nil) }
            row("checkmark.circle", "Маленькая победа", "любое действие для себя") { sheet = .addWin(nil) }
            row("moon", "Итог дня", "что помогло, что было трудно") { sheet = .evening(day) }
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


/// Время новой записи по умолчанию: в выбранном в дневнике дне, но не в будущем.
@MainActor
func defaultEventDate(_ store: AppStore, _ router: Router) -> Date {
    DefaultTime.inDay(router.composeDay ?? store.today, zoneID: store.zone, now: Date())
}

/// Отметка состояния: создание и правка.
struct CheckInSheet: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    var editID: UUID? = nil

    @State private var value: Int = 3
    @State private var note = ""
    @State private var date = Date()
    @State private var stories: [UUID] = []
    @State private var tags: Set<String> = []
    @State private var customTag = ""
    @State private var loaded = false

    private var record: CheckInRecord? {
        editID.flatMap { id in store.active.checkIns.first { $0.meta.id == id } }
    }

    var body: some View {
        SheetScroll {
            BigHeader(title: "Отметка", subtitle: editID == nil ? "как ты сейчас" : "изменить", size: 30)
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
            DateRow(title: "Дата и время", date: $date)
            FieldGroup(title: "История") { MultiStoryPicker(selection: $stories) }
            FieldGroup(title: "Теги") {
                MultiChips(options: store.tagOptions(including: tags), selection: $tags, prefix: "#")
                MField(title: "Свой тег", text: $customTag, placeholder: "например: учёба")
            }
            CTAButton(title: editID == nil ? "Сохранить отметку" : "Сохранить изменения", action: save)
            if let r = record {
                EditedNote(date: r.meta.editedAt)
                DeleteRecordButton {
                    store.delete([r.meta.id])
                    dismiss()
                }
            } else {
                Cap("Запись старше суток будет помечена «задним числом».")
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let r = record {
            value = r.anxiety
            note = r.note ?? ""
            date = r.observedAt
            stories = r.historyIDs
            tags = Set(r.tags)
        } else {
            value = store.level
            date = defaultEventDate(store, router)
        }
    }

    private func save() {
        let allTags = AppStore.tags(tags, custom: customTag)
        if let r = record {
            store.updateCheckIn(id: r.meta.id, anxiety: value, note: note, date: date, tags: allTags, historyIDs: stories)
        } else {
            store.addCheckIn(anxiety: value, note: note, at: date, tags: allTags, historyIDs: stories)
            if Cal.current.isDateInToday(date) { store.level = value }
        }
        dismiss()
    }
}

/// Форма тревожного эпизода: создание и правка. Все поля, кроме оценки, можно пропустить.
/// Если лист закрыли, не сохранив, введённое остаётся черновиком и возвращается в следующий раз.
struct EpisodeSheet: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    let historyID: UUID?
    var editID: UUID? = nil

    @State private var peak: Int = 5
    @State private var start = Date()
    @State private var ongoing = true
    @State private var end = Date()
    @State private var cause = ""
    @State private var thoughts = ""
    @State private var symptoms: Set<String> = []
    @State private var stories: [UUID] = []
    @State private var tags: Set<String> = []
    @State private var customTag = ""
    @State private var coping = ""
    @State private var insight = ""
    @State private var loaded = false
    @State private var saved = false
    @State private var fromDraft = false

    private var record: EpisodeRecord? {
        editID.flatMap { id in store.active.episodes.first { $0.meta.id == id } }
    }

    var body: some View {
        SheetScroll {
            BigHeader(title: "Эпизод", subtitle: editID == nil ? "что случилось" : "изменить", size: 30)
            if fromDraft {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text").font(.system(size: 16, weight: .medium))
                    Cap("Восстановлен черновик — то, что ты не успела сохранить.")
                    Spacer(minLength: 4)
                    Chip(text: "Начать заново", height: 30) { startOver() }
                }
                .card(13)
            }
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
            FieldGroup(title: "История") { MultiStoryPicker(selection: $stories) }
            FieldGroup(title: "Теги") {
                MultiChips(options: store.tagOptions(including: tags), selection: $tags, prefix: "#")
                MField(title: "Свой тег", text: $customTag, placeholder: "например: учёба")
            }
            MField(title: "Что я сделала", text: $coping, placeholder: "Можно заполнить позже", lines: 2)
            MField(title: "Что я поняла", text: $insight, placeholder: "Вывод попадёт в «Открытия»", lines: 2)
            CTAButton(title: editID == nil ? "Сохранить эпизод" : "Сохранить изменения", action: save)
            if let r = record {
                EditedNote(date: r.meta.editedAt)
                DeleteRecordButton {
                    saved = true
                    store.delete([r.meta.id])
                    dismiss()
                }
            } else {
                Cap("Все поля, кроме оценки, можно пропустить.")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: keepDraft)
        .onChange(of: start) { _, new in
            if end < new { end = new }
        }
    }

    private var hasInput: Bool {
        !(cause.trimmed.isEmpty && thoughts.trimmed.isEmpty && coping.trimmed.isEmpty && insight.trimmed.isEmpty
          && customTag.trimmed.isEmpty && symptoms.isEmpty && tags.isEmpty)
    }

    private var draft: EpisodeDraft {
        EpisodeDraft(peak: peak, start: start, ongoing: ongoing, end: end, cause: cause, thoughts: thoughts,
                     symptoms: BodySymptoms.common.filter { symptoms.contains($0) }, stories: stories, tags: Array(tags).sorted(),
                     customTag: customTag, coping: coping, insight: insight)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let r = record {
            peak = r.peak ?? 5
            start = r.startedAt
            ongoing = r.endedAt == nil
            end = r.endedAt ?? r.startedAt
            cause = r.cause ?? ""
            thoughts = r.thoughts ?? ""
            symptoms = Set(r.bodySymptoms)
            stories = r.historyIDs
            tags = Set(r.tags)
            coping = r.coping ?? ""
            insight = r.insights ?? ""
        } else if editID == nil, let d = store.episodeDraft {
            peak = d.peak
            start = min(d.start, Date())
            ongoing = d.ongoing
            end = min(max(d.end, start), Date())
            cause = d.cause
            thoughts = d.thoughts
            symptoms = Set(d.symptoms)
            stories = d.stories.filter { store.history($0) != nil }
            tags = Set(d.tags)
            customTag = d.customTag
            coping = d.coping
            insight = d.insight
            fromDraft = true
        } else {
            reset()
        }
    }

    private func reset() {
        peak = max(store.level, 5)
        start = defaultEventDate(store, router)
        end = start
        ongoing = true
        cause = ""; thoughts = ""; coping = ""; insight = ""; customTag = ""
        symptoms = []; tags = []
        stories = historyID.map { [$0] } ?? []
    }

    private func startOver() {
        store.discardEpisodeDraft()
        withAnimation(.easeOut(duration: 0.2)) { fromDraft = false }
        reset()
    }

    /// Лист закрыт без сохранения: введённое остаётся черновиком (только для нового эпизода).
    private func keepDraft() {
        guard editID == nil, !saved else { return }
        if hasInput { store.saveEpisodeDraft(draft) } else { store.discardEpisodeDraft() }
    }

    private func save() {
        let allTags = AppStore.tags(tags, custom: customTag)
        let begin = min(start, Date())
        if let r = record {
            var rec = r
            rec.peak = peak
            rec.startedAt = begin
            rec.endedAt = ongoing ? nil : max(begin, end)
            rec.cause = cause.nilIfEmpty
            rec.thoughts = thoughts.nilIfEmpty
            rec.bodySymptoms = BodySymptoms.common.filter { symptoms.contains($0) } + r.bodySymptoms.filter { !BodySymptoms.common.contains($0) && symptoms.contains($0) }
            rec.coping = coping.nilIfEmpty
            rec.insights = insight.nilIfEmpty
            rec.tags = allTags
            rec.historyIDs = stories
            store.updateEpisode(rec)
        } else {
            let rec = EpisodeRecord(meta: store.meta(), startedAt: begin, endedAt: ongoing ? nil : max(begin, end), zoneID: store.zone,
                                    peak: peak, cause: cause.nilIfEmpty, thoughts: thoughts.nilIfEmpty,
                                    bodySymptoms: BodySymptoms.common.filter { symptoms.contains($0) },
                                    coping: coping.nilIfEmpty, insights: insight.nilIfEmpty, tags: allTags, historyIDs: stories)
            store.addEpisode(rec)
            store.discardEpisodeDraft()
            if Cal.current.isDateInToday(begin) { store.level = peak }
        }
        saved = true
        dismiss()
    }
}

/// Разговор с ИИ: вставленный текст, оценки до и после, вывод. Создание и правка.
struct ConversationSheet: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    let historyID: UUID?
    var editID: UUID? = nil

    @State private var pasted = ""
    @State private var before: Int?
    @State private var after: Int?
    @State private var summary = ""
    @State private var insight = ""
    @State private var stories: [UUID] = []
    @State private var date = Date()
    @State private var loaded = false

    private var record: ConversationRecord? {
        editID.flatMap { id in store.active.conversations.first { $0.meta.id == id } }
    }

    var body: some View {
        SheetScroll {
            BigHeader(title: "Разговор", subtitle: editID == nil ? "с ИИ" : "изменить", size: 30)
            MField(title: "Текст разговора", text: $pasted, placeholder: "Вставь сюда текст — он останется только на устройстве", lines: 3)
            LevelCard(title: "Тревога до", value: $before, fallback: 5)
            LevelCard(title: "Тревога после", value: $after, fallback: 3, hint: "Оценки можно пропустить. Тогда разговор не войдёт в расчёт изменений.")
            MField(title: "Коротко: о чём", text: $summary, placeholder: "Что разобрали", lines: 2)
            MField(title: "Вывод", text: $insight, placeholder: "Что я поняла", lines: 2)
            FieldGroup(title: "История") { MultiStoryPicker(selection: $stories) }
            DateRow(title: "Дата и время", date: $date)
            CTAButton(title: editID == nil ? "Сохранить разговор" : "Сохранить изменения", action: save)
            if let r = record {
                EditedNote(date: r.meta.editedAt)
                DeleteRecordButton {
                    store.delete([r.meta.id])
                    dismiss()
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let r = record {
            pasted = r.pastedText ?? ""
            before = r.before
            after = r.after
            summary = r.summary ?? ""
            insight = r.insights ?? ""
            stories = r.historyIDs
            date = r.occurredAt
        } else {
            stories = historyID.map { [$0] } ?? []
            date = defaultEventDate(store, router)
        }
    }

    private func save() {
        if let r = record {
            var rec = r
            rec.pastedText = pasted.nilIfEmpty
            rec.before = before
            rec.after = after
            rec.summary = summary.nilIfEmpty
            rec.insights = insight.nilIfEmpty
            rec.historyIDs = stories
            rec.occurredAt = date
            store.updateConversation(rec)
        } else {
            let rec = ConversationRecord(meta: store.meta(), occurredAt: min(date, Date()), zoneID: store.zone, before: before, after: after,
                                         pastedText: pasted.nilIfEmpty, summary: summary.nilIfEmpty, insights: insight.nilIfEmpty,
                                         historyIDs: stories)
            store.addConversation(rec)
        }
        dismiss()
    }
}

/// Правка сессии практики: оценки до и после, ощущение, заметка, время, истории.
struct SessionEditSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID

    @State private var before: Int?
    @State private var after: Int?
    @State private var felt: FeltResult?
    @State private var notes = ""
    @State private var start = Date()
    @State private var stories: [UUID] = []
    @State private var loaded = false

    private var record: PracticeSessionRecord? {
        store.active.sessions.first { $0.meta.id == sessionID }
    }

    var body: some View {
        SheetScroll {
            if let r = record {
                BigHeader(title: "Практика", subtitle: "«\(store.practice(id: r.practiceID)?.title ?? r.practiceType.info.title)»", size: 30)
                LevelCard(title: "Тревога до", value: $before, fallback: 5)
                LevelCard(title: "Тревога после", value: $after, fallback: 3,
                          hint: "Без обеих оценок практика не входит в расчёт «что помогает».")
                FieldGroup(title: "Как ощущается") {
                    HStack(spacing: 8) {
                        ForEach(FeltResult.allCases, id: \.self) { f in
                            Chip(text: f.title, isOn: felt == f) { felt = felt == f ? nil : f }
                        }
                    }
                }
                MField(title: "Заметка", text: $notes, placeholder: "Что заметила во время практики", lines: 2)
                DateRow(title: "Дата и время", date: $start)
                FieldGroup(title: "История") { MultiStoryPicker(selection: $stories) }
                CTAButton(title: "Сохранить изменения") {
                    store.updateSession(id: r.meta.id, before: before, after: after, felt: felt, notes: notes, start: start, historyIDs: stories)
                    dismiss()
                }
                EditedNote(date: r.meta.editedAt)
                DeleteRecordButton {
                    store.delete([r.meta.id])
                    dismiss()
                }
            } else {
                Cap("Запись удалена.")
            }
        }
        .onAppear {
            guard !loaded, let r = record else { return }
            loaded = true
            before = r.before
            after = r.after
            felt = r.feltResult
            notes = r.notes ?? ""
            start = r.startedAt
            stories = r.historyIDs
        }
    }
}

/// Итог дня: один на календарный день. Сохранённый итог можно перенести на другой день и удалить.
struct EveningSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let day: LocalDay

    @State private var overall: Int?
    @State private var helped = ""
    @State private var hard = ""
    @State private var victory = ""
    @State private var summary = ""
    @State private var date = Date()
    @State private var saved = false
    @State private var loaded = false
    @State private var conflictDay: LocalDay?

    private var record: DayReflectionRecord? { store.reflection(on: day) }
    private var chosenDay: LocalDay { LocalDay(date: date, zoneID: store.zone) }

    var body: some View {
        ZStack {
            SheetScroll {
                HStack(alignment: .top) {
                    BigHeader(title: "Итог дня", subtitle: (record == nil ? day : chosenDay).longTitle, size: 30)
                    Emblem(name: "PivSleep", width: 84)
                }
                LevelCard(title: "Общее состояние", value: $overall, fallback: 3,
                          hint: "В среднюю дня эта оценка не входит — она показывается отдельно.")
                MField(title: "Что помогло", text: $helped, placeholder: "Прогулка, разговор, дыхание")
                MField(title: "Что было трудно", text: $hard, placeholder: "Ожидание ответа")
                MField(title: "Маленькая победа", text: $victory, placeholder: "Не проверяла телефон целый час")
                MField(title: "Свободно", text: $summary, placeholder: "Что хочется запомнить", lines: 2)
                if record != nil {
                    DateRow(title: "День", date: $date, components: [.date])
                }
                CTAButton(title: record == nil ? "Сохранить итог" : "Сохранить изменения", action: save)
                if let r = record {
                    EditedNote(date: r.meta.editedAt)
                    DeleteRecordButton(title: "Удалить итог дня") {
                        store.delete([r.meta.id], label: "Итог дня удалён")
                        dismiss()
                    }
                }
            }
            if saved { StarBurst() }
        }
        .onAppear(perform: load)
        .confirmationDialog("В этом дне уже есть итог", isPresented: Binding(get: { conflictDay != nil }, set: { if !$0 { conflictDay = nil } }),
                            titleVisibility: .visible) {
            Button("Заменить", role: .destructive) { finishMove(.replace) }
            Button("Объединить") { finishMove(.merge) }
            Button("Отмена", role: .cancel) { conflictDay = nil }
        } message: {
            Text("Заменить — старый итог \(conflictDay?.longTitle ?? "") удалится. Объединить — тексты сложатся в один итог.")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        date = day.noon
        guard let r = record else { return }
        overall = r.overallAnxiety
        helped = r.helped ?? ""
        hard = r.hard ?? ""
        victory = r.victory ?? ""
        summary = r.summary ?? ""
    }

    private func save() {
        store.saveReflection(day: day, overall: overall, helped: helped, hard: hard, victory: victory, summary: summary)
        if let r = store.reflection(on: day), chosenDay != day {
            if store.reflectionConflict(moving: r.meta.id, to: chosenDay) != nil {
                conflictDay = chosenDay
                return
            }
            store.moveReflection(r.meta.id, to: chosenDay, resolution: .replace)
        }
        close()
    }

    private func finishMove(_ resolution: ReflectionMove.Resolution) {
        if let r = store.reflection(on: day), let target = conflictDay {
            store.moveReflection(r.meta.id, to: target, resolution: resolution)
        }
        conflictDay = nil
        close()
    }

    private func close() {
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
