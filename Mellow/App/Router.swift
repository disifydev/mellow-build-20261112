import SwiftUI
import PivchikDomain

enum AppTab: String, CaseIterable, Hashable {
    case home, diary, stories, practice, progress

    var title: String {
        switch self {
        case .home: return "Главная"
        case .diary: return "Дневник"
        case .stories: return "Истории"
        case .practice: return "Практики"
        case .progress: return "Прогресс"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .diary: return "book"
        case .stories: return "square.stack.3d.up"
        case .practice: return "wind"
        case .progress: return "chart.bar"
        }
    }
}

/// Листы снизу.
enum SheetRoute: Identifiable {
    case newMenu
    case checkIn
    case episode(UUID?)
    case conversation(UUID?)
    case evening(LocalDay)
    case plan
    case newStory
    case addWin(UUID?)
    case goals
    case backup
    case report
    case summary
    case newLetter
    case message(String, String)

    var id: String {
        switch self {
        case .newMenu: return "newMenu"
        case .checkIn: return "checkIn"
        case .episode: return "episode"
        case .conversation: return "conversation"
        case .evening(let d): return "evening-\(d.description)"
        case .plan: return "plan"
        case .newStory: return "newStory"
        case .addWin: return "addWin"
        case .goals: return "goals"
        case .backup: return "backup"
        case .report: return "report"
        case .summary: return "summary"
        case .newLetter: return "newLetter"
        case .message(let text, _): return "message-\(text.hashValue)"
        }
    }

    var isCompact: Bool {
        switch self {
        case .message, .addWin, .newMenu, .plan: return true
        default: return false
        }
    }
}

/// Полноэкранные экраны.
enum CoverRoute: Identifiable {
    case profile
    case story(UUID)
    case practice(UUID, Int, Bool, UUID?)
    case letters
    case month
    case help

    var id: String {
        switch self {
        case .profile: return "profile"
        case .story(let id): return "story-\(id.uuidString)"
        case .practice(let id, _, _, _): return "practice-\(id.uuidString)"
        case .letters: return "letters"
        case .month: return "month"
        case .help: return "help"
        }
    }
}

@MainActor
final class Router: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var sheet: SheetRoute?
    @Published var cover: CoverRoute?
    @Published var practiceGroup: PracticeGroup = .breath
    @Published var diaryDay: LocalDay?
}
