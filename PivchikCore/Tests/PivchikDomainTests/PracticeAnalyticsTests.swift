import XCTest
@testable import PivchikDomain

final class PracticeAnalyticsTests: XCTestCase {
    func testMissingAfterIsNotImprovement() {
        let p = UUID()
        var s = Snapshot()
        s.sessions = [session(practice: p, before: 7, after: 2, duration: 180),
                      session(practice: p, before: 8, after: nil, duration: 180),
                      session(practice: p, before: nil, after: nil, duration: 60)]
        let st = PracticeAnalytics.stats(snapshot: s)[p]!
        XCTAssertEqual(st.sessionCount, 3)
        XCTAssertEqual(st.pairedCount, 1)
        XCTAssertEqual(st.improvedCount, 1)
        XCTAssertEqual(st.improvedShare, 1)
        XCTAssertEqual(st.meanChange, 5)
        XCTAssertFalse(st.hasEnoughData)
    }

    func testEffectivenessDenominatorIsPairedSessions() {
        let p = UUID()
        var s = Snapshot()
        s.sessions = [session(practice: p, before: 7, after: 4, duration: 180),   // +3
                      session(practice: p, before: 5, after: 5, duration: 180),   // 0 — не улучшение
                      session(practice: p, before: 4, after: 6, duration: 180),   // −2
                      session(practice: p, before: 9, after: 3, duration: 300, status: .endedEarly), // +6, досрочно — считается
                      session(practice: p, before: 9, after: 1, duration: 30, status: .interrupted), // прервана — не считается
                      session(practice: p, before: 6, duration: 180)]
        let st = PracticeAnalytics.stats(snapshot: s)[p]!
        XCTAssertEqual(st.sessionCount, 6)
        XCTAssertEqual(st.pairedCount, 4)
        XCTAssertEqual(st.improvedShare, 0.5)
        XCTAssertEqual(st.meanChange!, 1.75, accuracy: 0.0001)
        XCTAssertEqual(st.medianChange!, 1.5, accuracy: 0.0001)
        XCTAssertEqual(st.changes.sorted(), [-2, 0, 3, 6])
        XCTAssertTrue(st.hasEnoughData)
        XCTAssertEqual(st.medianDuration, 180)
    }

    func testSpeedOnlyForTimedPracticesAtLeastOneMinute() {
        let timed = UUID(), untimed = UUID()
        var s = Snapshot()
        s.sessions = [session(practice: timed, type: .breathing46, before: 8, after: 2, duration: 180),   // 2 балла/мин
                      session(practice: timed, type: .breathing46, before: 8, after: 2, duration: 30),    // короче минуты
                      session(practice: untimed, type: .canNotKnow, before: 7, after: 2, duration: 600)]
        let stats = PracticeAnalytics.stats(snapshot: s)
        XCTAssertEqual(stats[timed]!.speedPerMinute!, 2, accuracy: 0.0001)
        XCTAssertEqual(stats[timed]!.speedSampleCount, 1)
        XCTAssertNil(stats[untimed]!.speedPerMinute)
        XCTAssertNil(stats[untimed]!.medianDuration)
        XCTAssertEqual(stats[untimed]!.meanChange, 5)
    }

    func testFeltResultCounts() {
        let p = UUID()
        var s = Snapshot()
        s.sessions = [session(practice: p, felt: .easier), session(practice: p, felt: .easier), session(practice: p, felt: .harder), session(practice: p)]
        let st = PracticeAnalytics.stats(snapshot: s)[p]!
        XCTAssertEqual([st.feltEasier, st.feltSame, st.feltHarder], [2, 0, 1])
        XCTAssertNil(st.improvedShare)
    }

    func testConversationStatsUseLinkedPracticeRatings() {
        let h = UUID(), c1 = UUID(), c2 = UUID(), c3 = UUID()
        var s = Snapshot()
        s.conversations = [
            ConversationRecord(meta: meta(id: c1), occurredAt: at(2026, 11, 12), zoneID: tbilisi, insights: "могу подождать", historyIDs: [h]),
            ConversationRecord(meta: meta(id: c2), occurredAt: at(2026, 11, 11), zoneID: tbilisi, before: 6, after: 5, historyIDs: [h]),
            ConversationRecord(meta: meta(id: c3), occurredAt: at(2026, 11, 10), zoneID: tbilisi, before: 6),
        ]
        s.sessions = [session(type: .canNotKnow, before: 7, after: 2, conversation: c1)]
        let st = ConversationAnalytics.stats(snapshot: s)
        XCTAssertEqual(st.count, 3)
        XCTAssertEqual(st.pairedCount, 2)
        XCTAssertEqual(st.meanChange!, 3, accuracy: 0.0001)
        XCTAssertEqual(st.withInsights, 1)
        XCTAssertEqual(st.countByHistory[h], 2)
    }

    func testRecurrenceCountsUniqueEpisodesInPeriodOnly() {
        let h = UUID()
        var s = Snapshot()
        s.episodes = [EpisodeRecord(meta: meta(), startedAt: at(2026, 11, 3), zoneID: tbilisi, historyIDs: [h]),
                      EpisodeRecord(meta: meta(), startedAt: at(2026, 11, 10), zoneID: tbilisi, historyIDs: [h, h]),
                      EpisodeRecord(meta: meta(), startedAt: at(2026, 11, 11), zoneID: tbilisi, historyIDs: []),
                      EpisodeRecord(meta: meta(deleted: at(2026, 11, 12)), startedAt: at(2026, 11, 11), zoneID: tbilisi, historyIDs: [h])]
        // Отметки по той же истории повторениями не считаются.
        s.checkIns = [checkIn(8, at(2026, 11, 10), histories: [h]), checkIn(8, at(2026, 11, 10, 13), histories: [h])]
        XCTAssertEqual(HistoryAnalytics.recurrence(historyID: h, snapshot: s), 2)
        XCTAssertEqual(HistoryAnalytics.recurrence(historyID: h, snapshot: s, from: at(2026, 11, 9), to: at(2026, 11, 16)), 1)
    }

    func testFrequencies() {
        let f = HistoryAnalytics.frequencies(["Нет связи", "нет связи ", "работа", "", "  "])
        XCTAssertEqual(f.map { $0.value }, ["Нет связи", "работа"])
        XCTAssertEqual(f.map { $0.count }, [2, 1])
    }
}
