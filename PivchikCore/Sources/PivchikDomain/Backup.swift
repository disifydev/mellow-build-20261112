import Foundation

/// Резервная копия JSON (§11): один файл с названием формата, версией схемы, датой и версией приложения.
public struct BackupFile: Codable, Sendable, Equatable {
    public static let formatName = "pivchik-backup"
    public static let currentSchemaVersion = 1

    public var format: String
    public var schemaVersion: Int
    public var exportedAt: Date
    public var appVersion: String
    public var data: Snapshot

    public init(exportedAt: Date, appVersion: String, data: Snapshot) {
        self.format = BackupFile.formatName
        self.schemaVersion = BackupFile.currentSchemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.data = data
    }
}

public enum BackupError: Error, Equatable {
    /// Файл не является копией «Пивчика» или повреждён.
    case notABackup
    /// Копия сделана более новой версией приложения.
    case newerSchema(found: Int, supported: Int)
}

public enum BackupCodec {
    public static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(format(date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    public static func decode(_ data: Data) throws -> BackupFile {
        struct Header: Decodable { let format: String; let schemaVersion: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == BackupFile.formatName else {
            throw BackupError.notABackup
        }
        guard header.schemaVersion <= BackupFile.currentSchemaVersion else {
            throw BackupError.newerSchema(found: header.schemaVersion, supported: BackupFile.currentSchemaVersion)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = parse(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date: \(s)")
            }
            return date
        }
        do { return try decoder.decode(BackupFile.self, from: data) } catch { throw BackupError.notABackup }
    }

    // Даты — ISO 8601 в UTC с миллисекундами: читаются человеком и не теряют точность при повторном импорте.
    private static func makeFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f
    }

    static func format(_ date: Date) -> String { makeFormatter().string(from: date) }
    static func parse(_ string: String) -> Date? { makeFormatter().date(from: string) }
}

/// Итог импорта для предпросмотра: сколько записей добавится и обновится.
public struct ImportSummary: Sendable, Equatable {
    public var added = 0
    public var updated = 0
    public var unchanged = 0
    /// Сколько текущих записей будет удалено, потому что в копии они уже удалены.
    public var removed = 0

    public init() {}
}

public enum BackupMerger {
    /// Объединяет текущие данные с копией. Записи сопоставляются по `id`; при совпадении остаётся версия
    /// с более свежим `updatedAt`. Повторный импорт того же файла ничего не меняет.
    /// Удаление сильнее правки: если запись удалена хотя бы с одной стороны, остаётся надгробие без текста —
    /// старая копия не воскрешает удалённое, а удалённое в копии удаляется и здесь.
    public static func merge(current: Snapshot, incoming: Snapshot) -> (merged: Snapshot, summary: ImportSummary) {
        var summary = ImportSummary()
        func mergeList<R: Tombstonable>(_ old: [R], _ new: [R]) -> [R] {
            var byID: [UUID: Int] = [:]
            var out = old
            for (i, r) in old.enumerated() { byID[r.id] = i }
            for r in new {
                if let i = byID[r.id] {
                    let mine = out[i]
                    if mine.meta.isDeleted {
                        summary.unchanged += 1
                    } else if r.meta.isDeleted {
                        out[i] = r.tombstoned()
                        summary.removed += 1
                    } else if r.meta.updatedAt.timeIntervalSince(mine.meta.updatedAt) > 0.001 {
                        out[i] = r
                        summary.updated += 1
                    } else {
                        summary.unchanged += 1
                    }
                } else {
                    byID[r.id] = out.count
                    if r.meta.isDeleted {
                        out.append(r.tombstoned())
                    } else {
                        out.append(r)
                        summary.added += 1
                    }
                }
            }
            return out
        }
        var m = Snapshot()
        m.checkIns = mergeList(current.checkIns, incoming.checkIns)
        m.episodes = mergeList(current.episodes, incoming.episodes)
        m.dayReflections = mergeList(current.dayReflections, incoming.dayReflections)
        m.histories = mergeList(current.histories, incoming.histories)
        m.statusChanges = mergeList(current.statusChanges, incoming.statusChanges)
        m.conversations = mergeList(current.conversations, incoming.conversations)
        m.practices = mergeList(current.practices, incoming.practices)
        m.sessions = mergeList(current.sessions, incoming.sessions)
        m.insights = mergeList(current.insights, incoming.insights)
        m.goals = mergeList(current.goals, incoming.goals)
        m.goalSteps = mergeList(current.goalSteps, incoming.goalSteps)
        m.smallWins = mergeList(current.smallWins, incoming.smallWins)
        m.achievements = mergeList(current.achievements, incoming.achievements)
        m.letters = mergeList(current.letters, incoming.letters)
        m.settings = mergeList(current.settings, incoming.settings)
        return (m.purgingDeleted(), summary)
    }
}
