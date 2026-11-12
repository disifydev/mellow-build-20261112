import XCTest
@testable import PivchikDomain

final class DayAnalyticsTests: XCTestCase {
    let day = LocalDay(year: 2026, month: 11, day: 12)

    func testAnxiousDayHasPriorityOverCalm() {
        // 1, 1, 1, 8: среднее 2,75 (≤ 3), но максимум 8 (≥ 7) — день тревожный.
        var s = Snapshot()
        s.checkIns = [1, 1, 1, 8].enumerated().map { checkIn($1, at(2026, 11, 12, 9 + $0)) }
        let stats = DayAnalytics.dayStats(snapshot: s)[day]!
        XCTAssertEqual(stats.average, 2.75, accuracy: 0.0001)
        XCTAssertEqual(stats.maximum, 8)
        XCTAssertEqual(stats.median, 1)
        XCTAssertEqual(stats.count, 4)
        XCTAssertEqual(stats.category, .anxious)
    }

    func testCalmRegularAndThresholds() {
        XCTAssertEqual(DayAnalytics.category(average: 3, maximum: 6, thresholds: .default), .calm)
        XCTAssertEqual(DayAnalytics.category(average: 3.1, maximum: 6, thresholds: .default), .regular)
        XCTAssertEqual(DayAnalytics.category(average: 7, maximum: 7, thresholds: .default), .anxious)
        XCTAssertEqual(DayAnalytics.category(average: 4, maximum: 5, thresholds: DayThresholds(calm: 4, anxious: 5)), .anxious)
        // Некорректные пороги (спокойный не меньше тревожного) заменяются значениями по умолчанию.
        XCTAssertFalse(DayThresholds(calm: 7, anxious: 7).isValid)
        XCTAssertEqual(DayAnalytics.category(average: 5, maximum: 6, thresholds: DayThresholds(calm: 8, anxious: 2)), .regular)
    }

    func testEmptyDayIsGapNotCalm() {
        var s = Snapshot()
        s.checkIns = [checkIn(2, at(2026, 11, 10)), checkIn(2, at(2026, 11, 12))]
        let stats = DayAnalytics.dayStats(snapshot: s)
        let series = DayAnalytics.series(from: LocalDay(year: 2026, month: 11, day: 10), to: day, stats: stats)
        XCTAssertEqual(series.count, 3)
        XCTAssertNil(series[1].stats)
        let summary = DayAnalytics.summary(from: LocalDay(year: 2026, month: 11, day: 10), to: day, stats: stats)
        XCTAssertEqual(summary.calmDays, 2)
        XCTAssertEqual(summary.daysWithData, 2)
        XCTAssertEqual(summary.daysWithoutData, 1)
    }

    func testNoRecordsNoStats() {
        XCTAssertTrue(DayAnalytics.dayStats(snapshot: Snapshot()).isEmpty)
        let summary = DayAnalytics.summary(from: day, to: day, stats: [:])
        XCTAssertNil(summary.averageOfDays)
        XCTAssertEqual(summary.calmDays, 0)
    }

    func testDeletedRecordsIgnored() {
        var s = Snapshot()
        s.checkIns = [checkIn(9, at(2026, 11, 12), deleted: true)]
        XCTAssertTrue(DayAnalytics.dayStats(snapshot: s).isEmpty)
    }

    func testFirstTestDataFromSpec() {
        // §16: разговор и привязанная практика «Я могу не знать», 7 → 2. Оценки хранятся в сессии.
        let convID = UUID()
        var s = Snapshot()
        s.conversations = [ConversationRecord(meta: meta(id: convID), occurredAt: at(2026, 11, 12, 20), zoneID: tbilisi)]
        s.sessions = [session(type: .canNotKnow, at(2026, 11, 12, 20), before: 7, after: 2, conversation: convID)]
        let all = DayAnalytics.dayStats(snapshot: s)
        XCTAssertEqual(all.count, 1, "фиктивных значений за другие дни быть не должно")
        let stats = all[day]!
        XCTAssertEqual(stats.values.sorted(), [2, 7])
        XCTAssertEqual(stats.average, 4.5, accuracy: 0.0001)
        XCTAssertEqual(stats.category, .anxious)
    }

    func testConversationRatingsNotCountedTwice() {
        let convID = UUID()
        var s = Snapshot()
        s.conversations = [ConversationRecord(meta: meta(id: convID), occurredAt: at(2026, 11, 12, 20), zoneID: tbilisi, before: 7, after: 2)]
        // Без практики оценки разговора считаются.
        XCTAssertEqual(DayAnalytics.dayStats(snapshot: s)[day]!.count, 2)
        // С привязанной практикой, у которой свои оценки, — берутся только оценки практики.
        s.sessions = [session(type: .canNotKnow, at(2026, 11, 12, 20), before: 7, after: 2, conversation: convID)]
        XCTAssertEqual(DayAnalytics.dayStats(snapshot: s)[day]!.count, 2)
        // Привязанная практика без оценок двойного учёта не создаёт и оценки разговора не отменяет.
        s.sessions = [session(type: .canNotKnow, at(2026, 11, 12, 20), conversation: convID)]
        XCTAssertEqual(DayAnalytics.dayStats(snapshot: s)[day]!.count, 2)
    }

    func testEpisodePeakCounts() {
        var s = Snapshot()
        s.episodes = [EpisodeRecord(meta: meta(), startedAt: at(2026, 11, 12, 10), zoneID: tbilisi, peak: 8),
                      EpisodeRecord(meta: meta(), startedAt: at(2026, 11, 12, 15), zoneID: tbilisi)]
        let stats = DayAnalytics.dayStats(snapshot: s)[day]!
        XCTAssertEqual(stats.values, [8])
        XCTAssertEqual(stats.episodeCount, 2)
    }

    func testReflectionIsSeparateAndFallback() {
        var s = Snapshot()
        s.dayReflections = [DayReflectionRecord(meta: meta(), localDate: "2026-11-12", zoneID: tbilisi, overallAnxiety: 9),
                            DayReflectionRecord(meta: meta(), localDate: "2026-11-11", zoneID: tbilisi, overallAnxiety: 2)]
        s.checkIns = [checkIn(1, at(2026, 11, 12))]
        let stats = DayAnalytics.dayStats(snapshot: s)
        // Есть измерения: вечерняя оценка в среднее не входит.
        XCTAssertEqual(stats[day]!.average, 1)
        XCTAssertEqual(stats[day]!.reflectionScore, 9)
        XCTAssertEqual(stats[day]!.basis, .measurements)
        XCTAssertEqual(stats[day]!.category, .calm)
        // Измерений нет: оценка дня — по вечернему итогу.
        let prev = stats[LocalDay(year: 2026, month: 11, day: 11)]!
        XCTAssertEqual(prev.basis, .reflection)
        XCTAssertEqual(prev.count, 0)
        XCTAssertEqual(prev.category, .calm)
    }

    func testDayUsesRecordZoneNotDeviceZone() {
        // 23:30 в Тбилиси 12.11 = 19:30 UTC; запись в Токио в тот же момент — уже 13.11.
        let moment = at(2026, 11, 12, 23, 30)
        var s = Snapshot()
        s.checkIns = [checkIn(4, moment, zone: tbilisi), checkIn(6, moment, zone: "Asia/Tokyo")]
        let stats = DayAnalytics.dayStats(snapshot: s)
        XCTAssertEqual(stats[day]?.values, [4])
        XCTAssertEqual(stats[LocalDay(year: 2026, month: 11, day: 13)]?.values, [6])
    }

    func testMidnightBoundary() {
        var s = Snapshot()
        s.checkIns = [checkIn(5, at(2026, 11, 12, 23, 59)), checkIn(6, at(2026, 11, 13, 0, 0))]
        let stats = DayAnalytics.dayStats(snapshot: s)
        XCTAssertEqual(stats[day]?.values, [5])
        XCTAssertEqual(stats[LocalDay(year: 2026, month: 11, day: 13)]?.values, [6])
    }

    func testFilters() {
        let h = UUID()
        var s = Snapshot()
        s.checkIns = [checkIn(8, at(2026, 11, 12, 8), tags: ["работа"], histories: [h]),
                      checkIn(2, at(2026, 11, 12, 20), tags: ["дом"])]
        XCTAssertEqual(DayAnalytics.dayStats(snapshot: s, filter: MeasurementFilter(historyIDs: [h]))[day]!.values, [8])
        XCTAssertEqual(DayAnalytics.dayStats(snapshot: s, filter: MeasurementFilter(tags: ["дом"]))[day]!.values, [2])
        XCTAssertEqual(DayAnalytics.dayStats(snapshot: s, filter: MeasurementFilter(dayParts: [.morning]))[day]!.values, [8])
        XCTAssertEqual(DayAnalytics.dayStats(snapshot: s, filter: MeasurementFilter(dayParts: [.evening]))[day]!.values, [2])
    }

    func testLocalDayHelpers() {
        XCTAssertEqual(LocalDay(year: 2026, month: 3, day: 5).description, "2026-03-05")
        XCTAssertEqual(LocalDay(string: "2026-03-05"), LocalDay(year: 2026, month: 3, day: 5))
        XCTAssertNil(LocalDay(string: "2026-13-05"))
        XCTAssertEqual(LocalDay(year: 2026, month: 12, day: 31).adding(days: 1), LocalDay(year: 2027, month: 1, day: 1))
        XCTAssertEqual(LocalDay(year: 2028, month: 3, day: 1).adding(days: -1), LocalDay(year: 2028, month: 2, day: 29))
        XCTAssertEqual(LocalDay.range(from: day, to: day.adding(days: 6)).count, 7)
    }

    func testRetrospectiveRule() {
        let created = at(2026, 11, 12, 12)
        XCTAssertFalse(RetrospectiveRule.isRetrospective(eventAt: created.addingTimeInterval(-23 * 3600), createdAt: created))
        XCTAssertTrue(RetrospectiveRule.isRetrospective(eventAt: created.addingTimeInterval(-25 * 3600), createdAt: created))
    }

    func testMultiDayEpisodeCoversAllDaysButCountsOnce() {
        let h = UUID()
        let e = EpisodeRecord(meta: meta(), startedAt: at(2026, 11, 10, 22), endedAt: at(2026, 11, 12, 9), zoneID: tbilisi, peak: 7, historyIDs: [h])
        XCTAssertEqual(e.coveredDays(now: at(2026, 11, 20)).map { $0.description }, ["2026-11-10", "2026-11-11", "2026-11-12"])
        XCTAssertEqual(e.duration, 35.0 * 3600.0)
        var s = Snapshot(); s.episodes = [e]
        XCTAssertEqual(HistoryAnalytics.recurrence(historyID: h, snapshot: s), 1)
        XCTAssertEqual(DayAnalytics.dayStats(snapshot: s).count, 1)
    }
}
