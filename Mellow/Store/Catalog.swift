import Foundation
import PivchikDomain

/// Подписи уровня тревоги, поза кота и подсказки чувств (таблица LV из макета).
struct LevelInfo {
    let max: Int
    let name: String
    let cat: String
    let phrase: String
    let feels: [String]

    static let all: [LevelInfo] = [
        LevelInfo(max: 1, name: "полный покой", cat: "PivSleep", phrase: "Тихо. Побудем так.",
                  feels: ["спокойно", "расслаблена", "сонно", "тихо внутри"]),
        LevelInfo(max: 3, name: "спокойно", cat: "PivCalm", phrase: "Ровный день. Я рядом.",
                  feels: ["ровно", "чуть напряжена", "устала", "задумчива"]),
        LevelInfo(max: 5, name: "лёгкое беспокойство", cat: "PivTea", phrase: "Давай заметим это и выдохнем.",
                  feels: ["беспокойно", "не по себе", "раздражена", "грустно"]),
        LevelInfo(max: 7, name: "тревожно", cat: "PivPeek", phrase: "Я рядом. Подышим вместе?",
                  feels: ["тревожно", "накручиваю себя", "страшно", "злюсь"]),
        LevelInfo(max: 10, name: "сильная тревога", cat: "PivLove", phrase: "Я с тобой. Сначала — один выдох.",
                  feels: ["очень тревожно", "паника близко", "мысли не остановить", "сердце колотится"]),
    ]

    static func of(_ value: Int) -> LevelInfo {
        all.first { value <= $0.max } ?? all[all.count - 1]
    }
}

enum PracticeGroup: String, CaseIterable, Hashable {
    case breath, body, thoughts

    var title: String {
        switch self {
        case .breath: return "Дыхание"
        case .body: return "Тело"
        case .thoughts: return "Мысли"
        }
    }
}

/// Оформление практики: группа, описание, цвет карточки, кот.
struct PracticeInfo {
    let group: PracticeGroup
    let title: String
    let blurb: String
    let color: UInt32
    let cat: String
    let sortOrder: Int
}

extension PracticeType {
    var info: PracticeInfo {
        switch self {
        case .breathing46:
            return PracticeInfo(group: .breath, title: "Дыхание 4–6", blurb: "Вдох 4 с, выдох 6 с. Без задержки.",
                                color: 0xC9B5F2, cat: "PivBreathe", sortOrder: 0)
        case .breathing44:
            return PracticeInfo(group: .breath, title: "Ровное 4–4", blurb: "Вдох 4 с, выдох 4 с.",
                                color: 0xB4C3F7, cat: "PivCalm", sortOrder: 1)
        case .boxBreathing:
            return PracticeInfo(group: .breath, title: "Квадрат", blurb: "Вдох, пауза, выдох, пауза по 4 с.",
                                color: 0xF5B7D3, cat: "PivHappy", sortOrder: 2)
        case .freeRhythm:
            return PracticeInfo(group: .breath, title: "Свой ритм", blurb: "Фазы от 1 до 15 секунд, без пауз.",
                                color: 0xB5E0CD, cat: "PivStar", sortOrder: 3)
        case .grounding54321:
            return PracticeInfo(group: .body, title: "Заземление 5–4–3–2–1", blurb: "Пять чувств по очереди.",
                                color: 0xB5E0CD, cat: "PivRead", sortOrder: 4)
        case .muscleRelaxation:
            return PracticeInfo(group: .body, title: "Расслабление мышц", blurb: "Мягко напрячь и отпустить.",
                                color: 0xF9D3A8, cat: "PivSleep", sortOrder: 5)
        case .thoughtReview:
            return PracticeInfo(group: .thoughts, title: "Разбор мыслей", blurb: "Факт → предположение → чувство → действие.",
                                color: 0xB4C3F7, cat: "PivRead", sortOrder: 6)
        case .canNotKnow:
            return PracticeInfo(group: .thoughts, title: "Я могу не знать", blurb: "Отложить проверку и вернуться к своему делу.",
                                color: 0xF5B7D3, cat: "PivTea", sortOrder: 7)
        }
    }

    /// Ритм по умолчанию для практик с таймером.
    var defaultPattern: BreathPattern? {
        switch self {
        case .freeRhythm, .muscleRelaxation: return BreathPattern(inhale: 5, exhale: 7)
        default: return BreathPattern.preset(for: self)
        }
    }

    /// Подпись фазы: у расслабления мышц свои слова.
    func phaseName(_ phase: BreathPhase) -> String {
        switch phase {
        case .inhale: return self == .muscleRelaxation ? "Напрячь" : "Вдох"
        case .exhale: return self == .muscleRelaxation ? "Отпустить" : "Выдох"
        case .holdIn, .holdOut: return "Пауза"
        }
    }

    /// Шаги практик без таймера: заголовок, пояснение, нужен ли ввод текста.
    var steps: [PracticeStep] {
        switch self {
        case .grounding54321:
            return [
                PracticeStep(title: "5 вещей, которые ты видишь", hint: "Назови их про себя, не торопясь.", input: false),
                PracticeStep(title: "4 вещи, которые можно потрогать", hint: "Ткань, стол, свои ладони.", input: false),
                PracticeStep(title: "3 звука вокруг", hint: "Близкие и далёкие.", input: false),
                PracticeStep(title: "2 запаха", hint: "Или два запаха, которые тебе нравятся.", input: false),
                PracticeStep(title: "1 вкус", hint: "Или один медленный глоток воды.", input: false),
            ]
        case .thoughtReview:
            return [
                PracticeStep(title: "Факт", hint: "Что произошло на самом деле, без оценок?", input: true),
                PracticeStep(title: "Предположение", hint: "Что я додумала поверх факта?", input: true),
                PracticeStep(title: "Чувство", hint: "Что я сейчас чувствую?", input: true),
                PracticeStep(title: "Действие в моей власти", hint: "Что я могу сделать прямо сейчас?", input: true),
            ]
        case .canNotKnow:
            return [
                PracticeStep(title: "Я могу не знать", hint: "Сейчас ответа нет. Скажи это себе спокойно.", input: false),
                PracticeStep(title: "Отложить проверку", hint: "На сколько минут я откладываю проверку?", input: true),
                PracticeStep(title: "Вернуться к своему делу", hint: "Чем я займусь, пока жду?", input: true),
            ]
        default:
            return []
        }
    }
}

struct PracticeStep {
    let title: String
    let hint: String
    let input: Bool
}

extension PracticeDefinitionRecord {
    var pattern: BreathPattern {
        if let p = settings.pattern, p.isValid { return p }
        return type.defaultPattern ?? BreathPattern.breathing44
    }
}

extension HistoryStatus {
    var title: String {
        switch self {
        case .active: return "Активна"
        case .easier: return "Стало легче"
        case .resolved: return "Не беспокоит"
        case .archived: return "Архив"
        }
    }
}

extension FeltResult {
    var title: String {
        switch self {
        case .easier: return "Стало легче"
        case .same: return "Без изменений"
        case .harder: return "Сложнее"
        }
    }
}

extension DayCategory {
    var title: String {
        switch self {
        case .calm: return "спокойный"
        case .regular: return "обычный"
        case .anxious: return "тревожный"
        }
    }
}

extension AchievementType {
    var title: String {
        switch self {
        case .firstCheckIn: return "Первая отметка"
        case .firstEpisode: return "Записала эпизод"
        case .firstHistory: return "Первая история"
        case .firstInsight: return "Записала вывод"
        case .firstConversation: return "Разобрала разговор"
        case .firstPractice: return "Первая практика"
        case .triedNewPractice: return "Новая практика"
        case .firstDayReflection: return "Итог дня"
        case .firstLetter: return "Письмо себе"
        case .firstGoalDone: return "Цель выполнена"
        case .historyResolved: return "История закрыта"
        case .returnedToActivity: return "Вернулась к делу"
        }
    }

    var icon: String {
        switch self {
        case .firstCheckIn: return "pencil"
        case .firstEpisode: return "bolt"
        case .firstHistory: return "square.stack.3d.up"
        case .firstInsight: return "lightbulb"
        case .firstConversation: return "bubble.left"
        case .firstPractice: return "wind"
        case .triedNewPractice: return "sparkles"
        case .firstDayReflection: return "moon"
        case .firstLetter: return "envelope"
        case .firstGoalDone: return "flag"
        case .historyResolved: return "checkmark.seal"
        case .returnedToActivity: return "star"
        }
    }
}

/// Цвета и коты карточек историй — по порядку создания.
enum StoryLook {
    static let colors: [UInt32] = [0xC9B5F2, 0xF9D3A8, 0xB5E0CD, 0xF5B7D3, 0xB4C3F7]
    static let cats: [String] = ["PivPeek", "PivTea", "PivRead", "PivCalm", "PivHappy"]
}

enum BodySymptoms {
    static let common: [String] = ["сердцебиение", "ком в горле", "напряжение", "дрожь", "трудно дышать", "жар"]
}
