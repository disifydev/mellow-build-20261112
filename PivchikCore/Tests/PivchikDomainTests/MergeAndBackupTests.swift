import XCTest
@testable import PivchikDomain

final class MergeAndBackupTests: XCTestCase {
    func testTwoDevicesSameDayReflectionBecomeOne() {
        let phone = DayReflectionRecord(meta: meta(at(2026, 11, 12, 21), updated: at(2026, 11, 12, 21)), localDate: "2026-11-12",
                                        zoneID: tbilisi, overallAnxiety: 4, helped: "прогулка", hard: nil, victory: " ")
        let pad = DayReflectionRecord(meta: meta(at(2026, 11, 12, 22), updated: at(2026, 11, 12, 23)), localDate: "2026-11-12",
                                      zoneID: tbilisi, overallAnxiety: 5, helped: nil, hard: "ожидание", victory: "не проверяла телефон")
        let other = DayReflectionRecord(meta: meta(), localDate: "2026-11-11", zoneID: tbilisi, overallAnxiety: 2)
        let r = MergeRules.mergeDayReflections([pad, other, phone])
        XCTAssertEqual(r.kept.count, 2)
        XCTAssertEqual(r.removedIDs, [pad.id])
        let merged = r.kept.first { $0.localDate == "2026-11-12" }!
        XCTAssertEqual(merged.id, phone.id, "остаётся самая ранняя запись")
        XCTAssertEqual(merged.overallAnxiety, 5, "поле берётся из более свежей правки")
        XCTAssertEqual(merged.helped, "прогулка", "пустое поле не затирает заполненное")
        XCTAssertEqual(merged.hard, "ожидание")
        XCTAssertEqual(merged.victory, "не проверяла телефон")
    }

    func testAchievementDedupe() {
        let src = UUID()
        let items = [
            AchievementRecord(meta: meta(), type: .firstCheckIn, earnedAt: at(2026, 11, 12, 10)),
            AchievementRecord(meta: meta(), type: .firstCheckIn, earnedAt: at(2026, 11, 12, 9)),
            AchievementRecord(meta: meta(), type: .returnedToActivity, earnedAt: at(2026, 11, 12, 11), sourceID: src),
            AchievementRecord(meta: meta(), type: .returnedToActivity, earnedAt: at(2026, 11, 12, 12), sourceID: src),
            AchievementRecord(meta: meta(), type: .returnedToActivity, earnedAt: at(2026, 11, 12, 13), sourceID: UUID()),
        ]
        let r = MergeRules.dedupeAchievements(items)
        XCTAssertEqual(r.kept.count, 3)
        XCTAssertEqual(r.removedIDs.count, 2)
        XCTAssertEqual(r.kept.first { $0.type == .firstCheckIn }!.id, items[1].id, "остаётся самое раннее")
    }

    func testSettingsAndBuiltInPracticeDedupe() {
        let old = SettingsRecord(meta: meta(updated: at(2026, 11, 1)), calmThreshold: 2)
        let new = SettingsRecord(meta: meta(updated: at(2026, 11, 12)), calmThreshold: 4)
        XCTAssertEqual(MergeRules.dedupeSettings([old, new]).kept.map { $0.calmThreshold }, [4])
        XCTAssertEqual(new.thresholds, DayThresholds(calm: 4, anxious: 7))

        let a = PracticeDefinitionRecord(meta: meta(at(2026, 11, 1)), type: .breathing46, title: "Дыхание 4–6")
        let b = PracticeDefinitionRecord(meta: meta(at(2026, 11, 2)), type: .breathing46, title: "Дыхание 4–6", isFavorite: true)
        let custom = PracticeDefinitionRecord(meta: meta(), type: .freeRhythm, title: "Мой ритм", isBuiltIn: false, sortOrder: 9)
        let r = MergeRules.dedupeBuiltInPractices([a, b, custom])
        XCTAssertEqual(r.kept.count, 2)
        XCTAssertEqual(r.removedIDs, [b.id])
        XCTAssertTrue(r.kept.first { $0.id == a.id }!.isFavorite)
    }

    func testPurgeAfter30Days() {
        XCTAssertFalse(MergeRules.shouldPurge(meta(), now: at(2027, 1, 1)))
        XCTAssertFalse(MergeRules.shouldPurge(meta(deleted: at(2026, 11, 12)), now: at(2026, 12, 11)))
        XCTAssertTrue(MergeRules.shouldPurge(meta(deleted: at(2026, 11, 12)), now: at(2026, 12, 12)))
    }

    func sample() -> Snapshot {
        let h = UUID(), c = UUID(), p = UUID()
        var s = Snapshot()
        s.histories = [HistoryRecord(meta: meta(id: h), title: "Тревога при отсутствии связи", startedAt: at(2026, 10, 1))]
        s.statusChanges = [StatusChangeRecord(meta: meta(), historyID: h, fromStatus: .active, toStatus: .easier, changedAt: at(2026, 11, 10), note: "стало спокойнее")]
        s.checkIns = [checkIn(6, at(2026, 11, 12, 9), tags: ["утро"], histories: [h], part: .morning)]
        s.episodes = [EpisodeRecord(meta: meta(), startedAt: at(2026, 11, 12, 10), endedAt: at(2026, 11, 12, 11), zoneID: tbilisi, peak: 8,
                                    cause: "нет ответа", bodySymptoms: ["сердцебиение"], tags: ["связь"], historyIDs: [h])]
        s.conversations = [ConversationRecord(meta: meta(id: c), occurredAt: at(2026, 11, 12, 20), zoneID: tbilisi, pastedText: "текст беседы «ёж»", historyIDs: [h])]
        s.practices = [PracticeDefinitionRecord(meta: meta(id: p), type: .canNotKnow, title: "Я могу не знать",
                                                settings: PracticeSettings(pattern: .box, defaultDurationSeconds: 180))]
        s.sessions = [session(practice: p, type: .canNotKnow, at(2026, 11, 12, 20), before: 7, after: 2, conversation: c, felt: .easier)]
        s.dayReflections = [DayReflectionRecord(meta: meta(), localDate: "2026-11-12", zoneID: tbilisi, overallAnxiety: 4, hard: "ждать")]
        s.insights = [InsightRecord(meta: meta(), text: "Я могу не знать", isFavorite: true, historyIDs: [h], sourceKind: .conversation, sourceID: c)]
        let g = UUID()
        s.goals = [GoalRecord(meta: meta(id: g), title: "Реже проверять телефон", historyID: h)]
        s.goalSteps = [GoalStepRecord(meta: meta(), goalID: g, title: "Час без проверки", isDone: true, doneAt: at(2026, 11, 12, 18))]
        s.smallWins = [SmallWinRecord(meta: meta(), text: "Вернулась к книге", occurredAt: at(2026, 11, 12, 21), zoneID: tbilisi, historyIDs: [h])]
        s.achievements = [AchievementRecord(meta: meta(), type: .firstPractice, earnedAt: at(2026, 11, 12, 20))]
        s.letters = [FutureLetterRecord(meta: meta(), body: "Привет, я", unlockAt: at(2027, 1, 1))]
        s.settings = [SettingsRecord(meta: meta(), homeCardsOrder: ["chart", "wins"])]
        return s
    }

    func testBackupRoundTripKeepsEverythingIncludingCyrillic() throws {
        let original = BackupFile(exportedAt: at(2026, 11, 12, 22), appVersion: "1.0", data: sample())
        let data = try BackupCodec.encode(original)
        let restored = try BackupCodec.decode(data)
        XCTAssertEqual(restored, original)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("pivchik-backup"))
        XCTAssertTrue(text.contains("Тревога при отсутствии связи"))
    }

    func testBackupRejectsForeignAndNewerFiles() {
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"a\":1}".utf8))) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        XCTAssertThrowsError(try BackupCodec.decode(Data("не json".utf8))) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        let newer = Data("{\"format\":\"pivchik-backup\",\"schemaVersion\":99}".utf8)
        XCTAssertThrowsError(try BackupCodec.decode(newer)) {
            XCTAssertEqual($0 as? BackupError, .newerSchema(found: 99, supported: BackupFile.currentSchemaVersion))
        }
    }

    func testImportTwiceCreatesNoDuplicates() throws {
        let s = sample()
        let file = try BackupCodec.decode(try BackupCodec.encode(BackupFile(exportedAt: at(2026, 11, 12), appVersion: "1.0", data: s)))
        let first = BackupMerger.merge(current: Snapshot(), incoming: file.data)
        XCTAssertEqual(first.summary.added, 15)
        XCTAssertEqual(first.summary.updated, 0)
        let second = BackupMerger.merge(current: first.merged, incoming: file.data)
        XCTAssertEqual(second.summary.added, 0)
        XCTAssertEqual(second.summary.updated, 0)
        XCTAssertEqual(second.summary.unchanged, 15)
        XCTAssertEqual(second.merged, first.merged)
    }

    func testImportKeepsFresherVersion() {
        let id = UUID()
        var mine = Snapshot(), theirs = Snapshot()
        mine.checkIns = [CheckInRecord(meta: meta(at(2026, 11, 12), updated: at(2026, 11, 12, 15), id: id), observedAt: at(2026, 11, 12), zoneID: tbilisi, anxiety: 3)]
        theirs.checkIns = [CheckInRecord(meta: meta(at(2026, 11, 12), updated: at(2026, 11, 12, 13), id: id), observedAt: at(2026, 11, 12), zoneID: tbilisi, anxiety: 9)]
        XCTAssertEqual(BackupMerger.merge(current: mine, incoming: theirs).merged.checkIns.map { $0.anxiety }, [3])
        let back = BackupMerger.merge(current: theirs, incoming: mine)
        XCTAssertEqual(back.merged.checkIns.map { $0.anxiety }, [3])
        XCTAssertEqual(back.summary.updated, 1)
    }

    func testActiveSnapshotExcludesDeletedAndOptionallyTestData() {
        var s = Snapshot()
        s.checkIns = [checkIn(1, at(2026, 11, 12)), checkIn(2, at(2026, 11, 12), deleted: true)]
        s.checkIns.append(CheckInRecord(meta: meta(test: true), observedAt: at(2026, 11, 12), zoneID: tbilisi, anxiety: 7))
        XCTAssertEqual(s.active().checkIns.count, 2)
        XCTAssertEqual(s.active(includingTestData: false).checkIns.map { $0.anxiety }, [1])
    }

    func testFutureLetter() {
        var letter = FutureLetterRecord(meta: meta(), body: "x", unlockAt: at(2027, 1, 1))
        XCTAssertFalse(letter.isUnlocked(at: at(2026, 12, 31)))
        XCTAssertTrue(letter.isUnlocked(at: at(2027, 1, 1)))
        letter.canceledAt = at(2026, 12, 1)
        XCTAssertFalse(letter.isUnlocked(at: at(2027, 1, 2)))
    }
}
