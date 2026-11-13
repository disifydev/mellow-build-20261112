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
    // Правка сохранённых записей: та же форма, что при создании, но заполненная.
    case editCheckIn(UUID)
    case editEpisode(UUID)
    case editConversation(UUID)
    case editSession(UUID)
    case editWin(UUID)
    case editStory(UUID)
    case editLetter(UUID)

    /// Форма правки для строки дневника.
    static func edit(_ item: DiaryItem) -> SheetRoute {
        switch item.kind {
        case .checkIn: return .editCheckIn(item.id)
        case .episode: return .editEpisode(item.id)
        case .conversation: return .editConversation(item.id)
        case .session: return .editSession(item.id)
        case .win: return .editWin(item.id)
        }
    }

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
        case .editCheckIn(let id): return "editCheckIn-\(id.uuidString)"
        case .editEpisode(let id): return "editEpisode-\(id.uuidString)"
        case .editConversation(let id): return "editConversation-\(id.uuidString)"
        case .editSession(let id): return "editSession-\(id.uuidString)"
        case .editWin(let id): return "editWin-\(id.uuidString)"
        case .editStory(let id): return "editStory-\(id.uuidString)"
        case .editLetter(let id): return "editLetter-\(id.uuidString)"
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
    /// День, выбранный в дневнике: новые записи из «+» по умолчанию попадают в него (задним числом).
    @Published var composeDay: LocalDay?
}
