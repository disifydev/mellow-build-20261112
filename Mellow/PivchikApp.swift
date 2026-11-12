import SwiftUI
import Charts

@main
struct PivchikApp: App {
    @StateObject private var store = JournalStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .tint(Palette.purple)
        }
    }
}

enum Palette {
    static let purple = Color(red: 0.63, green: 0.36, blue: 0.84)
    static let ink = Color(red: 0.30, green: 0.19, blue: 0.39)
    static let lilac = Color(red: 0.94, green: 0.88, blue: 0.99)
    static let pink = Color(red: 1, green: 0.91, blue: 0.96)
    static let background = Color(red: 0.985, green: 0.964, blue: 0.995)
    static let gradient = LinearGradient(colors: [Color(red: 0.79, green: 0.56, blue: 0.94), purple], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct JournalEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var anxiety: Int
    var note: String
    var kind: String
    var story: String = ""
}

@MainActor final class JournalStore: ObservableObject {
    @Published var entries: [JournalEntry] = [] { didSet { save() } }
    private let key = "pivchik.entries.v1"
    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([JournalEntry].self, from: data) { entries = saved }
    }
    func add(_ entry: JournalEntry) { entries.insert(entry, at: 0) }
    func remove(at offsets: IndexSet) { entries.remove(atOffsets: offsets) }
    private func save() {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }
    var current: Int? { entries.sorted { $0.date > $1.date }.first?.anxiety }
    var week: [JournalEntry] { entries.filter { $0.date >= Calendar.current.date(byAdding: .day, value: -7, to: .now)! }.sorted { $0.date < $1.date } }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Главная", systemImage: "house.fill") }
            DiaryView().tabItem { Label("Дневник", systemImage: "calendar") }
            StoriesView().tabItem { Label("Истории", systemImage: "books.vertical") }
            PracticesView().tabItem { Label("Практики", systemImage: "leaf") }
            ProgressView().tabItem { Label("Прогресс", systemImage: "chart.xyaxis.line") }
        }
        .foregroundStyle(Palette.ink)
    }
}

struct PivBackground: View {
    var body: some View {
        LinearGradient(colors: [Palette.pink, Palette.background, Palette.lilac.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

struct SoftCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.95), lineWidth: 1))
            .shadow(color: Palette.purple.opacity(0.08), radius: 14, y: 6)
    }
}

struct PurpleButton: View {
    var title: String
    var symbol: String = "heart.fill"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.headline)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .foregroundStyle(.white).background(Palette.gradient, in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct Cat: View {
    var asset: String = "PivHappy"
    var width: CGFloat = 130
    var body: some View { Image(asset).resizable().scaledToFit().frame(width: width).accessibilityLabel("Пивчик") }
}

struct AnxietyChart: View {
    let entries: [JournalEntry]
    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView("Пока нет отметок", systemImage: "chart.xyaxis.line", description: Text("Добавь первую запись, чтобы увидеть динамику"))
                .frame(height: 165)
        } else {
            Chart(entries) { entry in
                LineMark(x: .value("Время", entry.date), y: .value("Тревога", entry.anxiety))
                    .interpolationMethod(.catmullRom).foregroundStyle(Palette.purple)
                PointMark(x: .value("Время", entry.date), y: .value("Тревога", entry.anxiety))
                    .foregroundStyle(Palette.purple)
            }
            .chartYScale(domain: 0...10)
            .chartYAxis { AxisMarks(values: [0,2,4,6,8,10]) }
            .frame(height: 175)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: JournalStore
    @State private var showEntry = false
    @State private var showBreathing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Привет! ♡").font(.largeTitle.bold())
                            Text("Как ты сегодня?").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Cat(asset: "PivHappy", width: 112)
                    }
                    SoftCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Пивчик рядом 🐾").font(.headline)
                                Text("Маленькие шаги тоже считаются.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "heart.text.square.fill").foregroundStyle(Palette.purple).font(.title)
                        }
                    }
                    SoftCard {
                        Text("Текущее состояние").font(.headline)
                        HStack(alignment: .firstTextBaseline) {
                            Text(store.current.map { "\($0)/10" } ?? "—/10").font(.system(size: 35, weight: .bold))
                            Spacer()
                            Text("Последняя отметка").font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 4)
                    }
                    SoftCard {
                        HStack { Text("Тревога · 7 дней").font(.headline); Spacer(); Image(systemName: "chart.line.uptrend.xyaxis") }
                        AnxietyChart(entries: store.week)
                    }
                    SoftCard {
                        Text("Маленькие победы").font(.headline)
                        Text("\(store.entries.count) записей о себе — это внимание к своему состоянию.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 4)
                    }
                    PurpleButton(title: "Позаботиться о себе", symbol: "heart.fill") { showEntry = true }
                    HStack(spacing: 10) {
                        Button { showBreathing = true } label: { Label("Подышать", systemImage: "wind").frame(maxWidth: .infinity) }
                        Button { showEntry = true } label: { Label("Записать", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }
                    }.buttonStyle(.borderedProminent).tint(Palette.purple)
                }.padding(18)
            }
            .background(PivBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showEntry) { EntrySheet() }
            .sheet(isPresented: $showBreathing) { BreathingView() }
        }
    }
}

struct EntrySheet: View {
    @EnvironmentObject private var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var anxiety = 5.0
    @State private var note = ""
    @State private var story = ""
    @State private var kind = "Эпизод"
    var body: some View {
        NavigationStack {
            Form {
                Section("Как ты себя чувствуешь?") {
                    HStack { Text("Тревога"); Spacer(); Text("\(Int(anxiety))/10").bold() }
                    Slider(value: $anxiety, in: 0...10, step: 1).tint(Palette.purple)
                    Picker("Тип записи", selection: $kind) {
                        ForEach(["Эпизод", "Утро", "День", "Вечер", "Итог дня"], id: \.self) { Text($0) }
                    }
                }
                Section("Твои мысли") {
                    TextField("Что произошло, что ты почувствовала?", text: $note, axis: .vertical).lineLimit(3...7)
                    TextField("История или тема (необязательно)", text: $story)
                }
            }
            .navigationTitle("Новая запись")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        store.add(JournalEntry(anxiety: Int(anxiety), note: note, kind: kind, story: story))
                        dismiss()
                    }
                }
            }
        }.tint(Palette.purple)
    }
}

struct DiaryView: View {
    @EnvironmentObject private var store: JournalStore
    @State private var showEntry = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    SoftCard {
                        Text("Твой дневник").font(.title2.bold())
                        Text("Отмечай состояние в любой момент дня.").foregroundStyle(.secondary)
                        PurpleButton(title: "Новая запись", symbol: "plus") { showEntry = true }.padding(.top, 8)
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section("История записей") {
                    ForEach(store.entries.sorted { $0.date > $1.date }) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(entry.anxiety)/10").font(.title3.bold()).foregroundStyle(Palette.purple)
                                Text(entry.kind).font(.subheadline)
                                Spacer()
                                Text(entry.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }
                            if !entry.note.isEmpty { Text(entry.note) }
                            if !entry.story.isEmpty { Label(entry.story, systemImage: "tag").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 5)
                    }.onDelete { offsets in
                        let sorted = store.entries.sorted { $0.date > $1.date }
                        let ids = offsets.map { sorted[$0].id }
                        store.entries.removeAll { ids.contains($0.id) }
                    }
                }
            }.scrollContentBackground(.hidden).background(PivBackground())
                .navigationTitle("Дневник")
                .sheet(isPresented: $showEntry) { EntrySheet() }
        }
    }
}

struct StoriesView: View {
    @EnvironmentObject private var store: JournalStore
    private var groups: [String] { Array(Set(store.entries.map(\.story).filter { !$0.isEmpty })).sorted() }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    HStack { Cat(asset: "PivRead", width: 115); Text("Каждая история — это путь, а не оценка себя.").font(.subheadline) }
                    if groups.isEmpty {
                        SoftCard { Text("Историй пока нет").font(.headline); Text("Укажи название темы при создании записи в дневнике. Здесь появятся связанные эпизоды.").foregroundStyle(.secondary) }
                    }
                    ForEach(groups, id: \.self) { group in
                        let items = store.entries.filter { $0.story == group }.sorted { $0.date < $1.date }
                        SoftCard {
                            Text(group).font(.headline)
                            Text("Записей: \(items.count)").foregroundStyle(.secondary)
                            if let first = items.first, let last = items.last {
                                Text("Первая оценка: \(first.anxiety)/10 · Последняя: \(last.anxiety)/10").font(.caption)
                            }
                        }
                    }
                }.padding(18)
            }.background(PivBackground()).navigationTitle("Истории")
        }
    }
}

struct PracticesView: View {
    @State private var showBreathing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Cat(asset: "PivBreathe", width: 185)
                    Text("Минута для себя").font(.title2.bold())
                    Text("Выбери спокойный ритм. Дыши комфортно, без усилий.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    SoftCard {
                        Label("Дыхательные практики", systemImage: "wind").font(.headline)
                        Text("4–6 · 4–4 · Квадратное дыхание").font(.subheadline).foregroundStyle(.secondary)
                        PurpleButton(title: "Начать практику", symbol: "play.fill") { showBreathing = true }.padding(.top, 8)
                    }
                    SoftCard {
                        Text("Я могу не знать").font(.headline)
                        Text("Мне необязательно знать всё прямо сейчас, чтобы заниматься своей жизнью.")
                            .foregroundStyle(.secondary)
                    }
                    SoftCard {
                        Text("Заземление 5–4–3–2–1").font(.headline)
                        Text("Заметь 5 вещей, которые видишь; 4, которые ощущаешь; 3 звука; 2 запаха; 1 вкус.")
                            .foregroundStyle(.secondary)
                    }
                }.padding(18)
            }.background(PivBackground()).navigationTitle("Практики")
                .sheet(isPresented: $showBreathing) { BreathingView() }
        }
    }
}

struct BreathingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected = 0
    @State private var duration = 60
    @State private var remaining = 60
    @State private var isRunning = false
    @State private var elapsed = 0
    @State private var before = 5.0
    @State private var after = 5.0
    @State private var finished = false
    private let names = ["4–6", "4–4", "Квадрат"]
    private var steps: [(String, Int)] {
        switch selected {
        case 1: return [("Вдох",4),("Выдох",4)]
        case 2: return [("Вдох",4),("Пауза",4),("Выдох",4),("Пауза",4)]
        default: return [("Вдох",4),("Выдох",6)]
        }
    }
    private var phase: (String, Double) {
        var second = elapsed % steps.reduce(0) { $0 + $1.1 }
        for (name, count) in steps {
            if second < count { return (name, Double(second) / Double(count)) }
            second -= count
        }
        return ("Вдох",0)
    }
    private var scale: CGFloat {
        switch phase.0 {
        case "Вдох": return 0.76 + 0.30 * phase.1
        case "Выдох": return 1.06 - 0.30 * phase.1
        default: return elapsed % 16 < 8 ? 1.06 : 0.76
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Cat(asset: "PivCalm", width: 120)
                    Text(finished ? "Как ты сейчас?" : (isRunning ? phase.0 : "Готова начать?")).font(.title2.bold())
                    ZStack {
                        Circle().fill(Palette.lilac).frame(width: 210, height: 210)
                        Circle().fill(Palette.gradient).frame(width: 175, height: 175)
                            .scaleEffect(isRunning ? scale : 0.76)
                            .shadow(color: Palette.purple.opacity(0.2), radius: 22)
                        Text(isRunning ? "\(remaining) сек" : "♡").font(.title.bold()).foregroundStyle(.white)
                    }.frame(height: 230).animation(.easeInOut(duration: 0.9), value: elapsed)
                    Picker("Ритм", selection: $selected) {
                        ForEach(names.indices, id: \.self) { Text(names[$0]).tag($0) }
                    }.pickerStyle(.segmented).disabled(isRunning)
                    Picker("Длительность", selection: $duration) {
                        ForEach([60,180,300,600], id: \.self) { seconds in Text("\(seconds / 60) мин").tag(seconds) }
                    }.pickerStyle(.segmented).disabled(isRunning)
                    SoftCard {
                        Text("Тревога до практики: \(Int(before))/10")
                        Slider(value: $before, in: 0...10, step: 1)
                    }
                    if finished {
                        SoftCard {
                            Text("Тревога после практики: \(Int(after))/10")
                            Slider(value: $after, in: 0...10, step: 1)
                            Text("Изменение: \(Int(after-before)) баллов").font(.headline)
                        }
                    }
                    PurpleButton(title: isRunning ? "Завершить" : (finished ? "Повторить" : "Начать дыхание"), symbol: isRunning ? "stop.fill" : "play.fill") {
                        if isRunning { isRunning = false; finished = true }
                        else { remaining = duration; elapsed = 0; finished = false; isRunning = true }
                    }
                    Text("Если задержки дыхания неприятны, выбери ритм без пауз.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(20)
            }.background(PivBackground()).navigationTitle("Дыхание")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { dismiss() } } }
                .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                    guard isRunning else { return }
                    elapsed += 1; remaining = max(0, duration - elapsed)
                    if remaining == 0 { isRunning = false; finished = true }
                }
        }
    }
}

struct ProgressView: View {
    @EnvironmentObject private var store: JournalStore
    private var avg: Double { guard !store.entries.isEmpty else { return 0 }; return Double(store.entries.map(\.anxiety).reduce(0,+)) / Double(store.entries.count) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack { Text("Твои маленькие шаги").font(.title2.bold()); Spacer(); Cat(asset: "PivStar", width: 100) }
                    SoftCard {
                        Text("Динамика · 7 дней").font(.headline)
                        AnxietyChart(entries: store.week)
                    }
                    HStack(spacing: 12) {
                        SoftCard {
                            Text("Записей").font(.caption).foregroundStyle(.secondary)
                            Text("\(store.entries.count)").font(.largeTitle.bold())
                        }
                        SoftCard {
                            Text("Средняя тревога").font(.caption).foregroundStyle(.secondary)
                            Text(store.entries.isEmpty ? "—" : String(format: "%.1f", avg)).font(.largeTitle.bold())
                        }
                    }
                    SoftCard {
                        Text("Что важно помнить").font(.headline)
                        Text("Прогресс — не только снижение баллов. Это и способность заботиться о себе, даже когда тревога ещё есть.")
                            .foregroundStyle(.secondary)
                    }
                    Text("Статистика строится только из твоих записей — без вымышленных данных.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }.background(PivBackground()).navigationTitle("Прогресс")
        }
    }
}
