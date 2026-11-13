import Foundation

/// Общие поля всех записей (§9).
public struct RecordMeta: Codable, Sendable, Hashable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var isTestData: Bool
    /// Когда пользователь последний раз правил запись вручную (для подписи «изменено»).
    /// В отличие от `updatedAt` не меняется от служебных обновлений. В старых копиях поля нет — это nil.
    public var editedAt: Date?

    public init(id: UUID = UUID(), createdAt: Date, updatedAt: Date? = nil, deletedAt: Date? = nil, isTestData: Bool = false,
                editedAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
        self.isTestData = isTestData
        self.editedAt = editedAt
    }

    public var isDeleted: Bool { deletedAt != nil }
}

public protocol Record: Codable, Sendable {
    var meta: RecordMeta { get set }
}

public extension Record {
    var id: UUID { meta.id }
}

public struct CheckInRecord: Record, Hashable {
    public var meta: RecordMeta
    public var observedAt: Date
    public var zoneID: String
    public var isRetrospective: Bool
    public var dayPart: DayPart?
    public var anxiety: Int
    public var note: String?
    public var tags: [String]
    public var historyIDs: [UUID]
    public var episodeID: UUID?

    public init(meta: RecordMeta, observedAt: Date, zoneID: String, isRetrospective: Bool = false, dayPart: DayPart? = nil,
                anxiety: Int, note: String? = nil, tags: [String] = [], historyIDs: [UUID] = [], episodeID: UUID? = nil) {
        self.meta = meta; self.observedAt = observedAt; self.zoneID = zoneID; self.isRetrospective = isRetrospective
        self.dayPart = dayPart; self.anxiety = anxiety; self.note = note; self.tags = tags
        self.historyIDs = historyIDs; self.episodeID = episodeID
    }
}

public struct EpisodeRecord: Record, Hashable {
    public var meta: RecordMeta
    public var startedAt: Date
    public var endedAt: Date?
    public var zoneID: String
    public var isRetrospective: Bool
    public var peak: Int?
    public var cause: String?
    public var context: String?
    public var thoughts: String?
    public var fears: String?
    public var bodySymptoms: [String]
    public var coping: String?
    public var insights: String?
    public var tags: [String]
    public var historyIDs: [UUID]

    public init(meta: RecordMeta, startedAt: Date, endedAt: Date? = nil, zoneID: String, isRetrospective: Bool = false,
                peak: Int? = nil, cause: String? = nil, context: String? = nil, thoughts: String? = nil, fears: String? = nil,
                bodySymptoms: [String] = [], coping: String? = nil, insights: String? = nil, tags: [String] = [], historyIDs: [UUID] = []) {
        self.meta = meta; self.startedAt = startedAt; self.endedAt = endedAt; self.zoneID = zoneID
        self.isRetrospective = isRetrospective; self.peak = peak; self.cause = cause; self.context = context
        self.thoughts = thoughts; self.fears = fears; self.bodySymptoms = bodySymptoms; self.coping = coping
        self.insights = insights; self.tags = tags; self.historyIDs = historyIDs
    }

    /// Длительность в секундах; nil, пока эпизод продолжается.
    public var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    public var isOngoing: Bool { endedAt == nil }
}

public struct DayReflectionRecord: Record, Hashable {
    public var meta: RecordMeta
    /// Календарный день в формате ГГГГ-ММ-ДД.
    public var localDate: String
    public var zoneID: String
    public var overallAnxiety: Int?
    public var helped: String?
    public var hard: String?
    public var victory: String?
    public var summary: String?

    public init(meta: RecordMeta, localDate: String, zoneID: String, overallAnxiety: Int? = nil, helped: String? = nil,
                hard: String? = nil, victory: String? = nil, summary: String? = nil) {
        self.meta = meta; self.localDate = localDate; self.zoneID = zoneID; self.overallAnxiety = overallAnxiety
        self.helped = helped; self.hard = hard; self.victory = victory; self.summary = summary
    }
}

public struct HistoryRecord: Record, Hashable {
    public var meta: RecordMeta
    public var title: String
    public var details: String?
    public var startedAt: Date
    public var status: HistoryStatus

    public init(meta: RecordMeta, title: String, details: String? = nil, startedAt: Date, status: HistoryStatus = .active) {
        self.meta = meta; self.title = title; self.details = details; self.startedAt = startedAt; self.status = status
    }
}

public struct StatusChangeRecord: Record, Hashable {
    public var meta: RecordMeta
    public var historyID: UUID
    public var fromStatus: HistoryStatus
    public var toStatus: HistoryStatus
    public var changedAt: Date
    public var note: String?

    public init(meta: RecordMeta, historyID: UUID, fromStatus: HistoryStatus, toStatus: HistoryStatus, changedAt: Date, note: String? = nil) {
        self.meta = meta; self.historyID = historyID; self.fromStatus = fromStatus; self.toStatus = toStatus
        self.changedAt = changedAt; self.note = note
    }
}

public struct ConversationRecord: Record, Hashable {
    public var meta: RecordMeta
    public var occurredAt: Date
    public var zoneID: String
    public var isRetrospective: Bool
    public var before: Int?
    public var after: Int?
    public var pastedText: String?
    public var summary: String?
    public var insights: String?
    public var historyIDs: [UUID]
    public var episodeIDs: [UUID]

    public init(meta: RecordMeta, occurredAt: Date, zoneID: String, isRetrospective: Bool = false, before: Int? = nil, after: Int? = nil,
                pastedText: String? = nil, summary: String? = nil, insights: String? = nil, historyIDs: [UUID] = [], episodeIDs: [UUID] = []) {
        self.meta = meta; self.occurredAt = occurredAt; self.zoneID = zoneID; self.isRetrospective = isRetrospective
        self.before = before; self.after = after; self.pastedText = pastedText; self.summary = summary
        self.insights = insights; self.historyIDs = historyIDs; self.episodeIDs = episodeIDs
    }
}

/// Настройки практики. Фазы дыхания — в секундах; 0 у паузы = пауза выключена.
public struct PracticeSettings: Codable, Sendable, Hashable {
    public var pattern: BreathPattern?
    public var defaultDurationSeconds: Int?
    public var soundID: String?
    public var soundVolume: Double?
    public var withoutTension: Bool?

    public init(pattern: BreathPattern? = nil, defaultDurationSeconds: Int? = nil, soundID: String? = nil,
                soundVolume: Double? = nil, withoutTension: Bool? = nil) {
        self.pattern = pattern; self.defaultDurationSeconds = defaultDurationSeconds; self.soundID = soundID
        self.soundVolume = soundVolume; self.withoutTension = withoutTension
    }
}

public struct PracticeDefinitionRecord: Record, Hashable {
    public var meta: RecordMeta
    public var type: PracticeType
    public var title: String
    public var settings: PracticeSettings
    public var isFavorite: Bool
    public var isBuiltIn: Bool
    public var sortOrder: Int

    public init(meta: RecordMeta, type: PracticeType, title: String, settings: PracticeSettings = PracticeSettings(),
                isFavorite: Bool = false, isBuiltIn: Bool = true, sortOrder: Int = 0) {
        self.meta = meta; self.type = type; self.title = title; self.settings = settings
        self.isFavorite = isFavorite; self.isBuiltIn = isBuiltIn; self.sortOrder = sortOrder
    }
}

public struct PracticeSessionRecord: Record, Hashable {
    public var meta: RecordMeta
    public var practiceID: UUID
    /// Вид практики на момент сессии (чтобы аналитика не зависела от правок определения).
    public var practiceType: PracticeType
    public var startedAt: Date
    public var endedAt: Date?
    public var zoneID: String
    public var isRetrospective: Bool
    public var plannedDuration: TimeInterval?
    /// Фактическая длительность без пауз, секунды.
    public var activeDuration: TimeInterval?
    public var status: SessionStatus
    public var before: Int?
    public var after: Int?
    public var feltResult: FeltResult?
    public var notes: String?
    public var settingsSnapshot: PracticeSettings?
    public var historyIDs: [UUID]
    public var episodeID: UUID?
    public var conversationID: UUID?

    public init(meta: RecordMeta, practiceID: UUID, practiceType: PracticeType, startedAt: Date, endedAt: Date? = nil, zoneID: String,
                isRetrospective: Bool = false, plannedDuration: TimeInterval? = nil, activeDuration: TimeInterval? = nil,
                status: SessionStatus = .completed, before: Int? = nil, after: Int? = nil, feltResult: FeltResult? = nil,
                notes: String? = nil, settingsSnapshot: PracticeSettings? = nil, historyIDs: [UUID] = [],
                episodeID: UUID? = nil, conversationID: UUID? = nil) {
        self.meta = meta; self.practiceID = practiceID; self.practiceType = practiceType; self.startedAt = startedAt
        self.endedAt = endedAt; self.zoneID = zoneID; self.isRetrospective = isRetrospective
        self.plannedDuration = plannedDuration; self.activeDuration = activeDuration; self.status = status
        self.before = before; self.after = after; self.feltResult = feltResult; self.notes = notes
        self.settingsSnapshot = settingsSnapshot; self.historyIDs = historyIDs; self.episodeID = episodeID
        self.conversationID = conversationID
    }

    /// before − after; положительное значение = снижение. Только если есть обе оценки.
    public var change: Int? {
        guard let before, let after else { return nil }
        return before - after
    }
}

public struct InsightRecord: Record, Hashable {
    public var meta: RecordMeta
    public var text: String
    public var isFavorite: Bool
    public var historyIDs: [UUID]
    public var sourceKind: InsightSourceKind?
    public var sourceID: UUID?

    public init(meta: RecordMeta, text: String, isFavorite: Bool = false, historyIDs: [UUID] = [],
                sourceKind: InsightSourceKind? = nil, sourceID: UUID? = nil) {
        self.meta = meta; self.text = text; self.isFavorite = isFavorite; self.historyIDs = historyIDs
        self.sourceKind = sourceKind; self.sourceID = sourceID
    }
}

public struct GoalRecord: Record, Hashable {
    public var meta: RecordMeta
    public var title: String
    public var details: String?
    public var historyID: UUID?
    public var state: GoalState
    public var completedAt: Date?

    public init(meta: RecordMeta, title: String, details: String? = nil, historyID: UUID? = nil,
                state: GoalState = .active, completedAt: Date? = nil) {
        self.meta = meta; self.title = title; self.details = details; self.historyID = historyID
        self.state = state; self.completedAt = completedAt
    }
}

public struct GoalStepRecord: Record, Hashable {
    public var meta: RecordMeta
    public var goalID: UUID
    public var title: String
    public var isDone: Bool
    public var doneAt: Date?
    public var order: Int

    public init(meta: RecordMeta, goalID: UUID, title: String, isDone: Bool = false, doneAt: Date? = nil, order: Int = 0) {
        self.meta = meta; self.goalID = goalID; self.title = title; self.isDone = isDone; self.doneAt = doneAt; self.order = order
    }
}

public struct SmallWinRecord: Record, Hashable {
    public var meta: RecordMeta
    public var text: String
    public var occurredAt: Date
    public var zoneID: String
    public var isRetrospective: Bool
    public var historyIDs: [UUID]
    public var dayReflectionID: UUID?

    public init(meta: RecordMeta, text: String, occurredAt: Date, zoneID: String, isRetrospective: Bool = false,
                historyIDs: [UUID] = [], dayReflectionID: UUID? = nil) {
        self.meta = meta; self.text = text; self.occurredAt = occurredAt; self.zoneID = zoneID
        self.isRetrospective = isRetrospective; self.historyIDs = historyIDs; self.dayReflectionID = dayReflectionID
    }
}

public struct AchievementRecord: Record, Hashable {
    public var meta: RecordMeta
    public var type: AchievementType
    public var earnedAt: Date
    public var sourceID: UUID?

    public init(meta: RecordMeta, type: AchievementType, earnedAt: Date, sourceID: UUID? = nil) {
        self.meta = meta; self.type = type; self.earnedAt = earnedAt; self.sourceID = sourceID
    }
}

public struct FutureLetterRecord: Record, Hashable {
    public var meta: RecordMeta
    public var body: String
    public var unlockAt: Date
    public var openedAt: Date?
    public var canceledAt: Date?

    public init(meta: RecordMeta, body: String, unlockAt: Date, openedAt: Date? = nil, canceledAt: Date? = nil) {
        self.meta = meta; self.body = body; self.unlockAt = unlockAt; self.openedAt = openedAt; self.canceledAt = canceledAt
    }

    public func isUnlocked(at now: Date) -> Bool { canceledAt == nil && now >= unlockAt }
}

public struct SettingsRecord: Record, Hashable {
    public var meta: RecordMeta
    public var calmThreshold: Int
    public var anxiousThreshold: Int
    public var theme: String
    public var reduceMotion: Bool
    public var soundEnabled: Bool
    public var hapticsEnabled: Bool
    public var preferredPracticeID: UUID?
    public var homeCardsOrder: [String]

    public init(meta: RecordMeta, calmThreshold: Int = DayThresholds.default.calm, anxiousThreshold: Int = DayThresholds.default.anxious,
                theme: String = "system", reduceMotion: Bool = false, soundEnabled: Bool = true, hapticsEnabled: Bool = true,
                preferredPracticeID: UUID? = nil, homeCardsOrder: [String] = []) {
        self.meta = meta; self.calmThreshold = calmThreshold; self.anxiousThreshold = anxiousThreshold; self.theme = theme
        self.reduceMotion = reduceMotion; self.soundEnabled = soundEnabled; self.hapticsEnabled = hapticsEnabled
        self.preferredPracticeID = preferredPracticeID; self.homeCardsOrder = homeCardsOrder
    }

    public var thresholds: DayThresholds { DayThresholds(calm: calmThreshold, anxious: anxiousThreshold) }
}

/// Полный снимок данных: вход для аналитики и содержимое резервной копии.
public struct Snapshot: Codable, Sendable, Equatable {
    public var checkIns: [CheckInRecord] = []
    public var episodes: [EpisodeRecord] = []
    public var dayReflections: [DayReflectionRecord] = []
    public var histories: [HistoryRecord] = []
    public var statusChanges: [StatusChangeRecord] = []
    public var conversations: [ConversationRecord] = []
    public var practices: [PracticeDefinitionRecord] = []
    public var sessions: [PracticeSessionRecord] = []
    public var insights: [InsightRecord] = []
    public var goals: [GoalRecord] = []
    public var goalSteps: [GoalStepRecord] = []
    public var smallWins: [SmallWinRecord] = []
    public var achievements: [AchievementRecord] = []
    public var letters: [FutureLetterRecord] = []
    public var settings: [SettingsRecord] = []

    public init() {}

    /// Без удалённых записей; тестовые данные по желанию тоже исключаются (в отчёты они не попадают).
    public func active(includingTestData: Bool = true) -> Snapshot {
        func keep<R: Record>(_ items: [R]) -> [R] {
            items.filter { !$0.meta.isDeleted && (includingTestData || !$0.meta.isTestData) }
        }
        var s = Snapshot()
        s.checkIns = keep(checkIns); s.episodes = keep(episodes); s.dayReflections = keep(dayReflections)
        s.histories = keep(histories); s.statusChanges = keep(statusChanges); s.conversations = keep(conversations)
        s.practices = keep(practices); s.sessions = keep(sessions); s.insights = keep(insights)
        s.goals = keep(goals); s.goalSteps = keep(goalSteps); s.smallWins = keep(smallWins)
        s.achievements = keep(achievements); s.letters = keep(letters); s.settings = keep(settings)
        return s
    }
}
