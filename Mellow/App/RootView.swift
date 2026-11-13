import SwiftUI
import PivchikDomain

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @State private var launched = false

    var body: some View {
        Themed {
            ZStack(alignment: .bottom) {
                tabContent
                TabBar()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                UndoToastBar()
                    .padding(.bottom, 84)
            }
        }
        .modifier(SheetHost(sheet: $router.sheet))
        .modifier(CoverHost(cover: $router.cover))
        .onAppear {
            openLaunchScreen()
            if Features.appleSignIn { store.checkAppleCredential() }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch router.tab {
        case .home: HomeView()
        case .diary: DiaryView()
        case .stories: StoriesView()
        case .practice: PracticeView()
        case .progress: ProgressTabView()
        }
    }

    /// Аргумент запуска -screen: сразу открыть нужный экран (для снимков).
    private func openLaunchScreen() {
        guard !launched else { return }
        launched = true
        guard let screen = Launch.screen else { return }
        switch screen {
        case "home": router.tab = .home
        case "diary": router.tab = .diary
        case "stories": router.tab = .stories
        case "practice": router.tab = .practice
        case "practice-body": router.tab = .practice; router.practiceGroup = .body
        case "progress": router.tab = .progress
        case "breath":
            if let p = store.practice(.breathing46) { router.cover = .practice(p.meta.id, 180, true, nil) }
        case "breath-before":
            if let p = store.practice(.breathing46) { router.cover = .practice(p.meta.id, 180, false, nil) }
        case "steps":
            if let p = store.practice(.thoughtReview) { router.cover = .practice(p.meta.id, 180, true, nil) }
        case "episode":
            router.tab = .diary
            router.sheet = .episode(nil)
        case "evening":
            router.tab = .diary
            router.sheet = .evening(store.today)
        case "conversation":
            router.tab = .diary
            router.sheet = .conversation(nil)
        case "newmenu":
            router.tab = .diary
            router.sheet = .newMenu
        case "backup": router.sheet = .backup
        case "pdf": router.tab = .progress; router.sheet = .report
        case "summary": router.tab = .progress; router.sheet = .summary
        case "heatmap", "progress-filter": router.tab = .progress
        case "goals": router.sheet = .goals
        case "plan": router.sheet = .plan
        case "profile": router.cover = .profile
        case "letters": router.cover = .letters
        case "month": router.cover = .month
        case "help": router.cover = .help
        case "story", "story-delete":
            if let h = store.histories.first { router.cover = .story(h.meta.id) }
        case "edit-checkin":
            router.tab = .diary
            if let c = store.diary.last(where: { $0.kind == .checkIn && $0.day == store.today }) { router.sheet = .editCheckIn(c.id) }
        case "diary-swipe", "diary-select": router.tab = .diary
        case "diary-undo":
            router.tab = .diary
            if let e = store.diary.last(where: { $0.kind == .episode && $0.day == store.today }) { store.delete([e.id]) }
        default: break
        }
    }
}

/// Листы: один общий набор для вкладок и полноэкранных экранов.
struct SheetHost: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Binding var sheet: SheetRoute?

    func body(content: Content) -> some View {
        content.sheet(item: $sheet) { route in
            Themed {
                SheetBody(route: route, sheet: $sheet)
                    .overlay(alignment: .bottom) { UndoToastBar().padding(.bottom, 12) }
            }
            .environmentObject(store)
            .environmentObject(router)
            .presentationDetents(route.isCompact ? [.medium, .large] : [.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(36)
        }
    }
}

struct SheetBody: View {
    let route: SheetRoute
    @Binding var sheet: SheetRoute?

    var body: some View {
        switch route {
        case .newMenu: NewMenuSheet(sheet: $sheet)
        case .checkIn: CheckInSheet()
        case .episode(let history): EpisodeSheet(historyID: history)
        case .conversation(let history): ConversationSheet(historyID: history)
        case .evening(let day): EveningSheet(day: day)
        case .plan: PlanSheet()
        case .newStory: NewStorySheet()
        case .addWin(let history): AddWinSheet(historyID: history)
        case .goals: GoalsSheet()
        case .backup: BackupSheet()
        case .report: ReportSheet()
        case .summary: SummarySheet()
        case .newLetter: NewLetterSheet()
        case .message(let text, let cat): MessageSheet(text: text, cat: cat)
        case .editCheckIn(let id): CheckInSheet(editID: id)
        case .editEpisode(let id): EpisodeSheet(historyID: nil, editID: id)
        case .editConversation(let id): ConversationSheet(historyID: nil, editID: id)
        case .editSession(let id): SessionEditSheet(sessionID: id)
        case .editWin(let id): AddWinSheet(historyID: nil, editID: id)
        case .editStory(let id): NewStorySheet(editID: id)
        case .editLetter(let id): NewLetterSheet(editID: id)
        }
    }
}

/// Полноэкранные экраны; могут открываться друг из друга.
struct CoverHost: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Binding var cover: CoverRoute?

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $cover) { route in
            Themed {
                CoverBody(route: route)
                    .overlay(alignment: .bottom) { UndoToastBar().padding(.bottom, 12) }
            }
            .environmentObject(store)
            .environmentObject(router)
        }
    }
}

struct CoverBody: View {
    let route: CoverRoute

    var body: some View {
        switch route {
        case .profile: ProfileView()
        case .story(let id): StoryDetailView(historyID: id)
        case .practice(let id, let seconds, let autostart, let history):
            PracticeFlowView(practiceID: id, seconds: seconds, autostart: autostart, historyID: history)
        case .letters: LettersView()
        case .month: MonthReviewView()
        case .help: HelpView()
        }
    }
}

/// Короткое сообщение со знаком.
struct MessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    let cat: String

    var body: some View {
        SheetScroll {
            HStack(spacing: 12) {
                Emblem(name: cat, width: 86)
                Text(text).txt(15).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            CTAButton(title: "Хорошо", small: true) { dismiss() }
        }
    }
}
