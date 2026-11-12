import Foundation

/// Необязательная пометка времени суток у отметки.
public enum DayPart: String, Codable, Sendable, CaseIterable {
    case morning, day, evening
}

/// Статус истории (§5).
public enum HistoryStatus: String, Codable, Sendable, CaseIterable {
    case active, easier, resolved, archived
}

/// Вид практики (§6).
public enum PracticeType: String, Codable, Sendable, CaseIterable {
    case breathing46, breathing44, boxBreathing, freeRhythm, muscleRelaxation
    case grounding54321, thoughtReview, canNotKnow

    /// Практики с таймером: только для них считается длительность и скорость снижения.
    public var isTimed: Bool {
        switch self {
        case .breathing46, .breathing44, .boxBreathing, .freeRhythm, .muscleRelaxation: return true
        case .grounding54321, .thoughtReview, .canNotKnow: return false
        }
    }

    public var isBreathing: Bool {
        switch self {
        case .breathing46, .breathing44, .boxBreathing, .freeRhythm: return true
        default: return false
        }
    }
}

public enum SessionStatus: String, Codable, Sendable, CaseIterable {
    /// Дошла до конца.
    case completed
    /// Пользователь завершил раньше времени.
    case endedEarly
    /// Приложение было выгружено или сессия брошена.
    case interrupted
    /// Ещё идёт.
    case running
}

/// Субъективная отметка после практики.
public enum FeltResult: String, Codable, Sendable, CaseIterable {
    case easier, same, harder
}

public enum GoalState: String, Codable, Sendable, CaseIterable {
    case active, done, paused, dropped
}

/// Достижения — за действия и навыки, не за отсутствие тревоги (§8).
public enum AchievementType: String, Codable, Sendable, CaseIterable {
    case firstCheckIn, firstEpisode, firstHistory, firstInsight, firstConversation
    case firstPractice, triedNewPractice, firstDayReflection, firstLetter, firstGoalDone
    case historyResolved
    /// Ручная отметка «вернулась к своему занятию».
    case returnedToActivity

    /// Можно получить много раз (по одному на источник), а не один раз на всё приложение.
    public var isRepeatable: Bool {
        switch self {
        case .triedNewPractice, .returnedToActivity, .historyResolved: return true
        default: return false
        }
    }
}

/// Источник открытия.
public enum InsightSourceKind: String, Codable, Sendable {
    case episode, conversation, practiceSession
}

/// Шкала тревоги 0…10.
public enum AnxietyScale {
    public static let range: ClosedRange<Int> = 0...10
    public static func isValid(_ value: Int) -> Bool { range.contains(value) }
    public static func clamp(_ value: Int) -> Int { min(max(value, range.lowerBound), range.upperBound) }
}
