import XCTest
@testable import PivchikDomain

final class BreathingTests: XCTestCase {
    func testPresets() {
        XCTAssertEqual(BreathPattern.breathing46.cycleDuration, 10)
        XCTAssertEqual(BreathPattern.breathing46.phases.map { $0.phase }, [.inhale, .exhale], "в дыхании 4–6 нет задержек")
        XCTAssertEqual(BreathPattern.box.phases.map { $0.phase }, [.inhale, .holdIn, .exhale, .holdOut])
        XCTAssertEqual(BreathPattern.box.withoutHolds.phases.map { $0.phase }, [.inhale, .exhale])
        XCTAssertNil(BreathPattern.preset(for: .thoughtReview))
        for t in PracticeType.allCases where t.isBreathing { XCTAssertTrue(BreathPattern.preset(for: t)!.isValid) }
    }

    func testValidation() {
        XCTAssertTrue(BreathPattern(inhale: 1, exhale: 15).isValid)
        XCTAssertFalse(BreathPattern(inhale: 0, exhale: 4).isValid)
        XCTAssertFalse(BreathPattern(inhale: 4, exhale: 16).isValid)
        XCTAssertFalse(BreathPattern(inhale: 4, holdIn: 0.5, exhale: 4).isValid)
        XCTAssertTrue(BreathPattern(inhale: 4, holdIn: 0, exhale: 4, holdOut: 2).isValid)
    }

    func testPositionInPattern() {
        let p = BreathPattern.breathing46
        XCTAssertEqual(p.position(at: 0).phase, .inhale)
        XCTAssertEqual(p.position(at: 3.9).phase, .inhale)
        let exhale = p.position(at: 4)
        XCTAssertEqual(exhale.phase, .exhale)
        XCTAssertEqual(exhale.phaseRemaining, 6)
        XCTAssertEqual(exhale.secondsLeftDisplay, 6)
        let second = p.position(at: 12.5)
        XCTAssertEqual(second.cycleIndex, 1)
        XCTAssertEqual(second.phase, .inhale)
        XCTAssertEqual(second.phaseElapsed, 2.5, accuracy: 0.0001)
        XCTAssertEqual(second.circleScale, 0.625, accuracy: 0.0001)

        let box = BreathPattern.box
        XCTAssertEqual(box.position(at: 5).phase, .holdIn)
        XCTAssertEqual(box.position(at: 5).circleScale, 1)
        XCTAssertEqual(box.position(at: 9).phase, .exhale)
        XCTAssertEqual(box.position(at: 13).phase, .holdOut)
        XCTAssertEqual(box.position(at: 16).phase, .inhale)
        XCTAssertEqual(box.position(at: 16).cycleIndex, 1)
    }

    func testTimerSurvivesBackgroundAndPause() {
        var t = SessionTimer(plannedDuration: 180, now: 1000)
        XCTAssertEqual(t.remaining(now: 1000), 180)
        // Экран заблокировали на 60 с — монотонное время продолжает идти.
        XCTAssertEqual(t.remaining(now: 1060), 120)
        t.pause(now: 1060)
        XCTAssertTrue(t.isPaused)
        XCTAssertEqual(t.remaining(now: 1500), 120, "на паузе время стоит")
        t.resume(now: 1500)
        XCTAssertEqual(t.activeElapsed(now: 1530), 90)
        XCTAssertEqual(t.progress(now: 1530)!, 0.5, accuracy: 0.0001)
        XCTAssertFalse(t.isFinished(now: 1619))
        XCTAssertTrue(t.isFinished(now: 1620))
        XCTAssertEqual(t.activeElapsed(now: 99999), 180, "активное время не больше планового")
        XCTAssertEqual(t.finalStatus(now: 1620), .completed)
    }

    func testEarlyStop() {
        var t = SessionTimer(plannedDuration: 300, now: 0)
        t.pause(now: 50)
        t.stop(now: 80)
        XCTAssertEqual(t.activeElapsed(now: 500), 50)
        XCTAssertEqual(t.finalStatus(now: 500), .endedEarly)
        XCTAssertEqual(SessionTimer(plannedDuration: 300, now: 0).finalStatus(now: 10), .running)
    }

    func testUntimedSession() {
        var t = SessionTimer(plannedDuration: nil, now: 0)
        XCTAssertNil(t.remaining(now: 100))
        XCTAssertFalse(t.isFinished(now: 100000))
        t.stop(now: 240)
        XCTAssertEqual(t.activeElapsed(now: 999), 240)
        XCTAssertEqual(t.finalStatus(now: 999), .completed)
        XCTAssertEqual(SessionTimer.allowedDurations, [60, 180, 300, 600])
    }

    func testMonotonicClockMovesForward() {
        let a = MonotonicClock.now(), b = MonotonicClock.now()
        XCTAssertGreaterThanOrEqual(b, a)
    }
}
