import SwiftUI
import PivchikDomain

struct StoriesView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var pal
    @State private var filter: HistoryStatus?

    private var list: [HistoryRecord] {
        store.histories.filter { filter == nil || $0.status == filter }
    }

    var body: some View {
        TabScroll {
            BigHeader(title: "Истории", subtitle: "это путь") {
                RoundButton(icon: "plus", label: "Новая история") { router.sheet = .newStory }
            }
            HScroll {
                Chip(text: "Все", isOn: filter == nil) { filter = nil }
                Chip(text: "Активные", isOn: filter == .active) { filter = .active }
                Chip(text: "Стало легче", isOn: filter == .easier) { filter = .easier }
                Chip(text: "Не беспокоит", isOn: filter == .resolved) { filter = .resolved }
                Chip(text: "Архив", isOn: filter == .archived) { filter = .archived }
            }
            if store.histories.isEmpty {
                empty
            } else if list.isEmpty {
                Cap("Историй с таким статусом нет.")
            } else {
                ForEach(list, id: \.meta.id) { h in
                    StoryCard(history: h) { router.cover = .story(h.meta.id) }
                }
            }
            insights.id("insights")
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Emblem(name: "PivRead", width: 120)
            H("Историй пока нет")
            Cap("История — это тема, которая повторяется. К ней можно привязывать эпизоды, разговоры и практики и видеть путь.")
                .multilineTextAlignment(.center)
            CTAButton(title: "Создать историю", icon: "plus", small: true) { router.sheet = .newStory }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    @ViewBuilder
    private var insights: some View {
        let items = store.active.insights.sorted { $0.meta.createdAt > $1.meta.createdAt }.prefix(3)
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
}

/// Цветная карточка истории.
struct StoryCard: View {
    @EnvironmentObject private var store: AppStore
    let history: HistoryRecord
    var action: () -> Void

    var body: some View {
        let index = store.historyIndex(history.meta.id)
        let episodes = HistoryAnalytics.episodes(historyID: history.meta.id, snapshot: store.active)
        let talks = store.active.conversations.filter { $0.historyIDs.contains(history.meta.id) }.count
        let peaks = Array(episodes.compactMap { $0.peak }.suffix(7))
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(history.title).display(24)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 76)
                    if !peaks.isEmpty { Spark(values: peaks) }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 7) {
                    TagPill(text: history.status.title)
                    Text("с \(Fmt.dayMonth.string(from: history.startedAt)) · эпизодов \(episodes.count) · разговоров \(talks)")
                        .txt(12).opacity(0.66)
                        .padding(.trailing, 76)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
            .background(alignment: .bottomTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    Color(hex: StoryLook.colors[index % StoryLook.colors.count])
                    Emblem(name: StoryLook.cats[index % StoryLook.cats.count], width: 110)
                        .padding(18)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Color(hex: 0x462882).opacity(0.16), radius: 14, x: 0, y: 12)
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Новая история.
struct NewStorySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var start = Date()

    var body: some View {
        SheetScroll {
            BigHeader(title: "Новая история", subtitle: "тема, которая повторяется", size: 30)
            MField(title: "Название", text: $title, placeholder: "Например: волнение перед встречами")
            MField(title: "Описание", text: $details, placeholder: "Как это обычно происходит", lines: 3)
            DateRow(title: "Когда началась", date: $start, components: [.date])
            CTAButton(title: "Создать историю") {
                guard let t = title.nilIfEmpty else { return }
                store.addHistory(title: t, details: details, startedAt: start)
                dismiss()
            }
            .opacity(title.trimmed.isEmpty ? 0.5 : 1)
            Cap("Старые записи можно добавить задним числом — они будут помечены.")
        }
    }
}

/// Маленькая победа.
struct AddWinSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let historyID: UUID?
    @State private var text = ""

    var body: some View {
        SheetScroll {
            BigHeader(title: "Победа", subtitle: "даже маленькая", size: 30)
            MField(title: "Что получилось", text: $text, placeholder: "Отметила своё состояние сегодня", lines: 2)
            CTAButton(title: "Сохранить") {
                guard text.nilIfEmpty != nil else { return }
                store.addWin(text, historyIDs: historyID.map { [$0] } ?? [])
                Haptics.success(store.settings.hapticsEnabled)
                dismiss()
            }
            .opacity(text.trimmed.isEmpty ? 0.5 : 1)
        }
    }
}
