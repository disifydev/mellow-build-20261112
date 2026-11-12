import Foundation
import PivchikDomain

/// Строка ленты дневника: отметка, эпизод, разговор или сессия практики.
struct DiaryItem: Identifiable {
    enum Kind: String {
        case checkIn, episode, conversation, session

        var title: String {
            switch self {
            case .checkIn: return "Отметка"
            case .episode: return "Эпизод"
            case .conversation: return "Разговор с ИИ"
            case .session: return "Практика"
            }
        }
    }

    let id: UUID
    let kind: Kind
    let date: Date
    let day: LocalDay
    let value: Int?
    let note: String
    let trailing: String
    let stories: [String]
    let tags: [String]
    let retro: Bool
    /// Всё, по чему идёт поиск, в нижнем регистре.
    let haystack: String

    static func build(from a: Snapshot) -> [DiaryItem] {
        var titles: [UUID: String] = [:]
        for h in a.histories { titles[h.meta.id] = h.title }
        var practiceTitles: [UUID: String] = [:]
        for p in a.practices { practiceTitles[p.meta.id] = p.title }
        func names(_ ids: [UUID]) -> [String] { ids.compactMap { titles[$0] } }
        func hay(_ parts: [String]) -> String { parts.joined(separator: " ").lowercased() }

        var out: [DiaryItem] = []
        for c in a.checkIns {
            let st = names(c.historyIDs)
            let note = c.note ?? ""
            out.append(DiaryItem(id: c.meta.id, kind: .checkIn, date: c.observedAt, day: LocalDay(date: c.observedAt, zoneID: c.zoneID),
                                 value: c.anxiety, note: note, trailing: "", stories: st, tags: c.tags, retro: c.isRetrospective,
                                 haystack: hay([Kind.checkIn.title, note] + st + c.tags)))
        }
        for e in a.episodes {
            let st = names(e.historyIDs)
            let text = [e.cause, e.thoughts, e.coping, e.insights].compactMap { $0 }
            let note = e.cause ?? e.thoughts ?? "Без описания"
            let dur = e.duration.map { Fmt.duration($0) } ?? "продолжается"
            out.append(DiaryItem(id: e.meta.id, kind: .episode, date: e.startedAt, day: LocalDay(date: e.startedAt, zoneID: e.zoneID),
                                 value: e.peak, note: note, trailing: dur, stories: st, tags: e.tags, retro: e.isRetrospective,
                                 haystack: hay([Kind.episode.title] + text + st + e.tags + e.bodySymptoms)))
        }
        for c in a.conversations {
            let st = names(c.historyIDs)
            let r = ConversationAnalytics.ratings(for: c, sessions: a.sessions)
            var trailing = ""
            if let b = r.before, let af = r.after { trailing = "\(b) → \(af)" }
            let note = c.summary ?? c.insights ?? "Без описания"
            out.append(DiaryItem(id: c.meta.id, kind: .conversation, date: c.occurredAt, day: LocalDay(date: c.occurredAt, zoneID: c.zoneID),
                                 value: nil, note: note, trailing: trailing, stories: st, tags: [], retro: c.isRetrospective,
                                 haystack: hay([Kind.conversation.title, c.summary ?? "", c.insights ?? "", c.pastedText ?? ""] + st)))
        }
        for s in a.sessions where s.status != .running {
            let st = names(s.historyIDs)
            let title = practiceTitles[s.practiceID] ?? s.practiceType.info.title
            var note = "«\(title)»"
            if let f = s.feltResult { note += " · " + f.title.lowercased() }
            if s.status == .interrupted { note += " · прервана" }
            if s.status == .endedEarly { note += " · завершена раньше" }
            var trailing = ""
            if let b = s.before, let af = s.after { trailing = "\(b) → \(af)" }
            out.append(DiaryItem(id: s.meta.id, kind: .session, date: s.startedAt, day: LocalDay(date: s.startedAt, zoneID: s.zoneID),
                                 value: s.after, note: note, trailing: trailing, stories: st, tags: [], retro: s.isRetrospective,
                                 haystack: hay([Kind.session.title, title, s.notes ?? ""] + st)))
        }
        return out.sorted { $0.date < $1.date }
    }
}
