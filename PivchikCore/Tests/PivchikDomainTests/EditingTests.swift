import XCTest
@testable import PivchikDomain

final class EditingTests: XCTestCase {
    // MARK: Надгробия и импорт

    func testTombstoneWipesAllUserText() {
        let h = UUID()
        let e = EpisodeRecord(meta: meta(deleted: at(2026, 11, 13)), startedAt: at(2026, 11, 12, 10), zoneID: tbilisi, peak: 8,
                              cause: "нет ответа", context: "вечер", thoughts: "мысль", fears: "страх", bodySymptoms: ["сердцебиение"],
                              coping: "дыхание", insights: "вывод", tags: ["связь"], historyIDs: [h])
        let t = e.tombstoned()
        XCTAssertEqual(t.id, e.id)
        XCTAssertEqual(t.meta.deletedAt, e.meta.deletedAt)
        XCTAssertNil(t.cause); XCTAssertNil(t.thoughts); XCTAssertNil(t.fears); XCTAssertNil(t.coping); XCTAssertNil(t.insights)
        XCTAssertNil(t.context); XCTAssertNil(t.peak)
        XCTAssertTrue(t.tags.isEmpty); XCTAssertTrue(t.bodySymptoms.isEmpty); XCTAssertTrue(t.historyIDs.isEmpty)

        let letter = FutureLetterRecord(meta: meta(deleted: at(2026, 11, 13)), body: "секрет", unlockAt: at(2027, 1, 1)).tombstoned()
        XCTAssertEqual(letter.body, "")
        let r = DayReflectionRecord(meta: meta(), localDate: "2026-11-12", zoneID: tbilisi, helped: "a", hard: "b", victory: "c", summary: "d").tombstoned()
        XCTAssertNil(r.helped); XCTAssertNil(r.hard); XCTAssertNil(r.victory); XCTAssertNil(r.summary); XCTAssertEqual(r.localDate, "")
    }

    func testPurgingDeletedOnlyTouchesDeleted() {
        var s = Snapshot()
        s.checkIns = [checkIn(3, at(2026, 11, 12)), checkIn(5, at(2026, 11, 12), deleted: true)]
        s.checkIns[0].note = "живая"
        s.checkIns[1].note = "удалённая"
        let p = s.purgingDeleted()
        XCTAssertEqual(p.checkIns[0].note, "живая")
        XCTAssertNil(p.checkIns[1].note)
        XCTAssertTrue(p.checkIns[1].meta.isDeleted)
        // Только выбранные id.
        let onlyOther = s.purgingDeleted(ids: [UUID()])
        XCTAssertEqual(onlyOther.checkIns[1].note, "удалённая")
    }

    func testOldBackupDoesNotResurrectDeletedRecord() throws {
        let id = UUID()
        var old = Snapshot()
        old.checkIns = [CheckInRecord(meta: meta(at(2026, 11, 10), id: id), observedAt: at(2026, 11, 10), zoneID: tbilisi, anxiety: 6, note: "личное")]
        let backup = try BackupCodec.decode(try BackupCodec.encode(BackupFile(exportedAt: at(2026, 11, 10), appVersion: "1.0", data: old)))

        // Запись удалили и стёрли до надгробия.
        var mine = old
        mine.checkIns[0].meta.deletedAt = at(2026, 11, 12)
        mine.checkIns[0].meta.updatedAt = at(2026, 11, 12)
        mine = mine.purgingDeleted()

        let r = BackupMerger.merge(current: mine, incoming: backup.data)
        XCTAssertEqual(r.merged.checkIns.count, 1)
        XCTAssertTrue(r.merged.checkIns[0].meta.isDeleted)
        XCTAssertNil(r.merged.checkIns[0].note)
        XCTAssertEqual(r.summary.added, 0)
        XCTAssertEqual(r.summary.updated, 0)
        XCTAssertTrue(r.merged.active().checkIns.isEmpty)

        // Даже если в копии запись правили позже удаления — удаление сильнее.
        var newer = old
        newer.checkIns[0].meta.updatedAt = at(2026, 11, 20)
        let r2 = BackupMerger.merge(current: mine, incoming: newer)
        XCTAssertTrue(r2.merged.checkIns[0].meta.isDeleted)
        XCTAssertNil(r2.merged.checkIns[0].note)
    }

    func testDeletionInBackupPropagatesAndTombstonesAreNotCountedAsAdded() {
        let id = UUID()
        var mine = Snapshot()
        mine.smallWins = [SmallWinRecord(meta: meta(id: id), text: "победа", occurredAt: at(2026, 11, 12), zoneID: tbilisi)]
        var theirs = mine
        theirs.smallWins[0].meta.deletedAt = at(2026, 11, 13)
        theirs.smallWins.append(SmallWinRecord(meta: meta(deleted: at(2026, 11, 13)), text: "другая", occurredAt: at(2026, 11, 12), zoneID: tbilisi))
        let r = BackupMerger.merge(current: mine, incoming: theirs)
        XCTAssertEqual(r.summary.removed, 1)
        XCTAssertEqual(r.summary.added, 0)
        XCTAssertEqual(r.merged.smallWins.count, 2)
        XCTAssertTrue(r.merged.smallWins.allSatisfy { $0.meta.isDeleted && $0.text.isEmpty })
    }

    // MARK: Удаление и отмена

    func testDeleteCascadesAndUndoRestoresFully() {
        var s = Snapshot()
        let e = EpisodeRecord(meta: meta(), startedAt: at(2026, 11, 12, 10), zoneID: tbilisi, peak: 7, cause: "причина", insights: "вывод")
        s.episodes = [e]
        s.insights = [InsightRecord(meta: meta(), text: "вывод", sourceKind: .episode, sourceID: e.id),
                      InsightRecord(meta: meta(), text: "чужой")]
        let g = GoalRecord(meta: meta(), title: "цель")
        s.goals = [g]
        s.goalSteps = [GoalStepRecord(meta: meta(), goalID: g.id, title: "этап")]

        let (d, affected) = Deletion.delete([e.id, g.id], in: s, now: at(2026, 11, 13))
        XCTAssertEqual(affected.count, 4)
        XCTAssertTrue(d.active().episodes.isEmpty)
        XCTAssertEqual(d.active().insights.map { $0.text }, ["чужой"])
        XCTAssertTrue(d.active().goalSteps.isEmpty)
        // До окончания отмены текст ещё на месте.
        XCTAssertEqual(d.episodes[0].cause, "причина")

        let undone = d.restoring(affected, from: s)
        XCTAssertEqual(undone, s)

        let purged = d.purgingDeleted(ids: affected)
        XCTAssertNil(purged.episodes[0].cause)
        XCTAssertEqual(purged.insights[0].text, "")
        XCTAssertEqual(purged.insights[1].text, "чужой")
    }

    func testDeleteHistoryOnlyKeepsRecordsWithoutLinks() {
        let (s, h, other) = historySample()
        let (d, affected) = Deletion.deleteHistory(h, withRecords: false, in: s, now: at(2026, 11, 13))
        let a = d.active()
        XCTAssertEqual(a.histories.map { $0.id }, [other])
        XCTAssertEqual(a.checkIns.count, 3)
        XCTAssertTrue(a.checkIns.allSatisfy { !$0.historyIDs.contains(h) })
        XCTAssertEqual(a.checkIns.first { $0.note == "две" }?.historyIDs, [other])
        XCTAssertEqual(a.episodes.count, 1)
        XCTAssertTrue(a.episodes[0].historyIDs.isEmpty)
        XCTAssertNil(a.goals[0].historyID)
        XCTAssertTrue(a.statusChanges.isEmpty)
        // Отмена возвращает и историю, и связи.
        XCTAssertEqual(d.restoring(affected, from: s), s)
    }

    func testDeleteHistoryWithRecords() {
        let (s, h, other) = historySample()
        let (d, affected) = Deletion.deleteHistory(h, withRecords: true, in: s, now: at(2026, 11, 13))
        let a = d.active()
        XCTAssertEqual(a.histories.map { $0.id }, [other])
        XCTAssertEqual(a.checkIns.map { $0.note }, ["без истории"])
        XCTAssertTrue(a.episodes.isEmpty)
        XCTAssertTrue(a.goals.isEmpty)
        XCTAssertTrue(a.goalSteps.isEmpty, "этапы удаляются вместе с целью")
        XCTAssertTrue(a.insights.isEmpty, "вывод эпизода удаляется вместе с эпизодом")
        XCTAssertEqual(d.restoring(affected, from: s), s)
    }

    private func historySample() -> (Snapshot, UUID, UUID) {
        let h = UUID(), other = UUID()
        var s = Snapshot()
        s.histories = [HistoryRecord(meta: meta(id: h), title: "А", startedAt: at(2026, 10, 1)),
                       HistoryRecord(meta: meta(id: other), title: "Б", startedAt: at(2026, 10, 2))]
        s.statusChanges = [StatusChangeRecord(meta: meta(), historyID: h, fromStatus: .active, toStatus: .easier, changedAt: at(2026, 11, 1))]
        var c1 = checkIn(4, at(2026, 11, 12, 9), histories: [h]); c1.note = "одна"
        var c2 = checkIn(5, at(2026, 11, 12, 10), histories: [h, other]); c2.note = "две"
        var c3 = checkIn(2, at(2026, 11, 12, 11)); c3.note = "без истории"
        s.checkIns = [c1, c2, c3]
        let e = EpisodeRecord(meta: meta(), startedAt: at(2026, 11, 12, 12), zoneID: tbilisi, peak: 7, insights: "вывод", historyIDs: [h])
        s.episodes = [e]
        s.insights = [InsightRecord(meta: meta(), text: "вывод", sourceKind: .episode, sourceID: e.id)]
        let g = GoalRecord(meta: meta(), title: "цель", historyID: h)
        s.goals = [g]
        s.goalSteps = [GoalStepRecord(meta: meta(), goalID: g.id, title: "этап")]
        return (s, h, other)
    }

    // MARK: Перенос итога дня

    func testMoveReflectionToFreeDay() {
        var s = Snapshot()
        let r = DayReflectionRecord(meta: meta(), localDate: "2026-11-12", zoneID: tbilisi, victory: "победа")
        s.dayReflections = [r]
        s.smallWins = [SmallWinRecord(meta: meta(), text: "победа", occurredAt: at(2026, 11, 12, 21), zoneID: tbilisi, dayReflectionID: r.id)]
        let day = LocalDay(year: 2026, month: 11, day: 10)
        XCTAssertNil(ReflectionMove.conflict(moving: r.id, to: day, in: s))
        let (m, _) = ReflectionMove.move(r.id, to: day, resolution: .replace, winDate: at(2026, 11, 10, 12), in: s, now: at(2026, 11, 13))
        XCTAssertEqual(m.dayReflections[0].localDate, "2026-11-10")
        XCTAssertNotNil(m.dayReflections[0].meta.editedAt)
        XCTAssertEqual(m.smallWins[0].occurredAt, at(2026, 11, 10, 12))
    }

    func testMoveReflectionReplaceAndMerge() {
        var s = Snapshot()
        let moving = DayReflectionRecord(meta: meta(), localDate: "2026-11-12", zoneID: tbilisi, overallAnxiety: 3, helped: "прогулка", victory: "уснула")
        let target = DayReflectionRecord(meta: meta(), localDate: "2026-11-10", zoneID: tbilisi, overallAnxiety: 6, helped: "чай", hard: "ожидание")
        s.dayReflections = [moving, target]
        s.smallWins = [SmallWinRecord(meta: meta(), text: "уснула", occurredAt: at(2026, 11, 12, 21), zoneID: tbilisi, dayReflectionID: moving.id)]
        let day = LocalDay(year: 2026, month: 11, day: 10)
        XCTAssertEqual(ReflectionMove.conflict(moving: moving.id, to: day, in: s)?.id, target.id)

        let (rep, repAffected) = ReflectionMove.move(moving.id, to: day, resolution: .replace, winDate: at(2026, 11, 10, 12), in: s, now: at(2026, 11, 13))
        let ra = rep.active()
        XCTAssertEqual(ra.dayReflections.map { $0.id }, [moving.id])
        XCTAssertEqual(ra.dayReflections[0].localDate, "2026-11-10")
        XCTAssertEqual(ra.smallWins.count, 1)
        XCTAssertEqual(rep.restoring(repAffected, from: s), s)

        let (mer, merAffected) = ReflectionMove.move(moving.id, to: day, resolution: .merge, winDate: at(2026, 11, 10, 12), in: s, now: at(2026, 11, 13))
        let ma = mer.active()
        XCTAssertEqual(ma.dayReflections.map { $0.id }, [target.id])
        XCTAssertEqual(ma.dayReflections[0].helped, "чай\nпрогулка")
        XCTAssertEqual(ma.dayReflections[0].hard, "ожидание")
        XCTAssertEqual(ma.dayReflections[0].victory, "уснула")
        XCTAssertEqual(ma.dayReflections[0].overallAnxiety, 3)
        XCTAssertEqual(ma.smallWins.count, 1)
        XCTAssertEqual(ma.smallWins[0].dayReflectionID, target.id)
        XCTAssertEqual(mer.restoring(merAffected, from: s), s)
    }

    func testMergeText() {
        XCTAssertEqual(ReflectionMove.mergeText("а", "а"), "а")
        XCTAssertEqual(ReflectionMove.mergeText(nil, " б "), "б")
        XCTAssertNil(ReflectionMove.mergeText(" ", nil))
    }

    // MARK: Время по умолчанию

    func testDefaultTimeInsidePastDay() {
        let now = at(2026, 11, 13, 15, 40)
        let d = DefaultTime.inDay(LocalDay(year: 2026, month: 11, day: 10), zoneID: tbilisi, now: now)
        XCTAssertEqual(d, at(2026, 11, 10, 15, 40))
        XCTAssertEqual(DefaultTime.inDay(LocalDay(year: 2026, month: 11, day: 13), zoneID: tbilisi, now: now), now)
        XCTAssertEqual(DefaultTime.inDay(LocalDay(year: 2026, month: 11, day: 20), zoneID: tbilisi, now: now), now, "в будущее нельзя")
        XCTAssertEqual(DefaultTime.clampToNow(at(2026, 12, 1), now: now), now)
    }

    func testEditedAtIsOptionalInOldFiles() throws {
        // Старый формат без editedAt читается.
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","createdAt":0,"updatedAt":0,"isTestData":false}"#
        let m = try JSONDecoder().decode(RecordMeta.self, from: Data(json.utf8))
        XCTAssertNil(m.editedAt)
    }
}
