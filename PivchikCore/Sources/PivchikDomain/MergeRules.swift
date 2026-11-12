import Foundation

/// Слияние дублей. iCloud не позволяет уникальные ключи, поэтому два устройства могут создать
/// один и тот же итог дня, достижение или настройки (§9).
public enum MergeRules {
    public struct Result<R: Record>: Sendable {
        /// Записи, которые остаются (уже с объединёнными полями).
        public let kept: [R]
        /// Идентификаторы дублей, которые нужно пометить удалёнными.
        public let removedIDs: [UUID]
    }

    /// Итог дня: один на `localDate`. Остаётся самая ранняя запись, по каждому полю — более свежее непустое значение.
    public static func mergeDayReflections(_ items: [DayReflectionRecord]) -> Result<DayReflectionRecord> {
        var kept: [DayReflectionRecord] = [], removed: [UUID] = []
        for (_, group) in Dictionary(grouping: items, by: { $0.localDate }) {
            guard group.count > 1 else { kept.append(contentsOf: group); continue }
            let byAge = group.sorted { ($0.meta.createdAt, $0.id.uuidString) < ($1.meta.createdAt, $1.id.uuidString) }
            let freshFirst = group.sorted { ($0.meta.updatedAt, $0.id.uuidString) > ($1.meta.updatedAt, $1.id.uuidString) }
            var survivor = byAge[0]
            func text(_ key: KeyPath<DayReflectionRecord, String?>) -> String? {
                freshFirst.compactMap { $0[keyPath: key] }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            survivor.overallAnxiety = freshFirst.compactMap { $0.overallAnxiety }.first
            survivor.helped = text(\.helped)
            survivor.hard = text(\.hard)
            survivor.victory = text(\.victory)
            survivor.summary = text(\.summary)
            survivor.zoneID = freshFirst[0].zoneID
            survivor.meta.updatedAt = freshFirst[0].meta.updatedAt
            survivor.meta.isTestData = group.allSatisfy { $0.meta.isTestData }
            kept.append(survivor)
            removed.append(contentsOf: byAge.dropFirst().map { $0.id })
        }
        return Result(kept: kept.sorted { $0.localDate < $1.localDate }, removedIDs: removed)
    }

    /// Достижение: одно на `type` + `sourceID` (для неповторяемых — одно на `type`). Остаётся самое раннее.
    public static func dedupeAchievements(_ items: [AchievementRecord]) -> Result<AchievementRecord> {
        var kept: [AchievementRecord] = [], removed: [UUID] = []
        let groups = Dictionary(grouping: items) { a -> String in
            a.type.isRepeatable ? a.type.rawValue + "|" + (a.sourceID?.uuidString ?? "") : a.type.rawValue
        }
        for (_, group) in groups {
            let sorted = group.sorted { ($0.earnedAt, $0.id.uuidString) < ($1.earnedAt, $1.id.uuidString) }
            kept.append(sorted[0])
            removed.append(contentsOf: sorted.dropFirst().map { $0.id })
        }
        return Result(kept: kept.sorted { $0.earnedAt < $1.earnedAt }, removedIDs: removed)
    }

    /// Настройки: остаётся запись с более свежим `updatedAt`.
    public static func dedupeSettings(_ items: [SettingsRecord]) -> Result<SettingsRecord> {
        let sorted = items.sorted { ($0.meta.updatedAt, $0.id.uuidString) > ($1.meta.updatedAt, $1.id.uuidString) }
        guard let first = sorted.first else { return Result(kept: [], removedIDs: []) }
        return Result(kept: [first], removedIDs: sorted.dropFirst().map { $0.id })
    }

    /// Встроенные практики: одна на вид. Остаётся самая ранняя; «избранное» сохраняется, если стояло хоть на одной.
    public static func dedupeBuiltInPractices(_ items: [PracticeDefinitionRecord]) -> Result<PracticeDefinitionRecord> {
        var kept = items.filter { !$0.isBuiltIn }, removed: [UUID] = []
        for (_, group) in Dictionary(grouping: items.filter { $0.isBuiltIn }, by: { $0.type }) {
            let sorted = group.sorted { ($0.meta.createdAt, $0.id.uuidString) < ($1.meta.createdAt, $1.id.uuidString) }
            var survivor = sorted[0]
            survivor.isFavorite = group.contains { $0.isFavorite }
            kept.append(survivor)
            removed.append(contentsOf: sorted.dropFirst().map { $0.id })
        }
        return Result(kept: kept.sorted { $0.sortOrder < $1.sortOrder }, removedIDs: removed)
    }

    /// Мягко удалённые записи стираются окончательно через 30 дней.
    public static let purgeAfter: TimeInterval = 30 * 24 * 60 * 60

    public static func shouldPurge(_ meta: RecordMeta, now: Date) -> Bool {
        guard let deletedAt = meta.deletedAt else { return false }
        return now.timeIntervalSince(deletedAt) >= purgeAfter
    }
}
