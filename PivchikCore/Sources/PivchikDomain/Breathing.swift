import Foundation

public enum BreathPhase: String, Codable, Sendable, CaseIterable {
    case inhale, holdIn, exhale, holdOut
}

/// Ритм дыхания, секунды. Пауза 0 = выключена: задерживать дыхание никто не вынуждает.
public struct BreathPattern: Codable, Sendable, Hashable {
    public var inhale: Double
    public var holdIn: Double
    public var exhale: Double
    public var holdOut: Double

    public static let phaseRange: ClosedRange<Double> = 1...15

    public init(inhale: Double, holdIn: Double = 0, exhale: Double, holdOut: Double = 0) {
        self.inhale = inhale; self.holdIn = holdIn; self.exhale = exhale; self.holdOut = holdOut
    }

    public static let breathing46 = BreathPattern(inhale: 4, exhale: 6)
    public static let breathing44 = BreathPattern(inhale: 4, exhale: 4)
    public static let box = BreathPattern(inhale: 4, holdIn: 4, exhale: 4, holdOut: 4)

    /// Ритм по умолчанию для вида практики; nil для практик без дыхания.
    public static func preset(for type: PracticeType) -> BreathPattern? {
        switch type {
        case .breathing46: return .breathing46
        case .breathing44, .freeRhythm: return .breathing44
        case .boxBreathing: return .box
        default: return nil
        }
    }

    public var isValid: Bool {
        BreathPattern.phaseRange.contains(inhale) && BreathPattern.phaseRange.contains(exhale)
            && (holdIn == 0 || BreathPattern.phaseRange.contains(holdIn))
            && (holdOut == 0 || BreathPattern.phaseRange.contains(holdOut))
    }

    /// Тот же ритм без пауз.
    public var withoutHolds: BreathPattern { BreathPattern(inhale: inhale, exhale: exhale) }

    public var cycleDuration: Double { inhale + holdIn + exhale + holdOut }

    /// Фазы цикла по порядку, выключенные паузы пропущены.
    public var phases: [(phase: BreathPhase, duration: Double)] {
        let all: [(BreathPhase, Double)] = [(.inhale, inhale), (.holdIn, holdIn), (.exhale, exhale), (.holdOut, holdOut)]
        return all.filter { $0.1 > 0 }.map { (phase: $0.0, duration: $0.1) }
    }

    /// Положение в ритме через `elapsed` секунд активного времени.
    public func position(at elapsed: Double) -> BreathPosition {
        let cycle = cycleDuration
        guard cycle > 0, isValid else {
            return BreathPosition(phase: .inhale, phaseElapsed: 0, phaseDuration: 0, cycleIndex: 0)
        }
        let t = max(0, elapsed)
        let cycleIndex = Int(t / cycle)
        var rest = t - Double(cycleIndex) * cycle
        for p in phases {
            if rest < p.duration {
                return BreathPosition(phase: p.phase, phaseElapsed: rest, phaseDuration: p.duration, cycleIndex: cycleIndex)
            }
            rest -= p.duration
        }
        // Погрешность округления на границе цикла.
        return BreathPosition(phase: .inhale, phaseElapsed: 0, phaseDuration: inhale, cycleIndex: cycleIndex + 1)
    }
}

public struct BreathPosition: Sendable, Equatable {
    public let phase: BreathPhase
    public let phaseElapsed: Double
    public let phaseDuration: Double
    public let cycleIndex: Int

    public var phaseRemaining: Double { max(0, phaseDuration - phaseElapsed) }

    /// Секунды для показа на экране: обратный отсчёт с округлением вверх.
    public var secondsLeftDisplay: Int { Int(phaseRemaining.rounded(.up)) }

    /// Доля фазы 0…1.
    public var phaseProgress: Double { phaseDuration > 0 ? min(1, phaseElapsed / phaseDuration) : 0 }

    /// Размер круга 0…1: растёт на вдохе, держится на паузе, сжимается на выдохе.
    public var circleScale: Double {
        switch phase {
        case .inhale: return phaseProgress
        case .holdIn: return 1
        case .exhale: return 1 - phaseProgress
        case .holdOut: return 0
        }
    }
}

/// Таймер сессии. Работает на монотонном времени, которое передаётся снаружи (`MonotonicClock.now()`),
/// поэтому при блокировке экрана и возврате остаток времени верный, а перевод часов не влияет.
public struct SessionTimer: Sendable, Equatable, Codable {
    public static let allowedDurations: [TimeInterval] = [60, 180, 300, 600]

    /// Плановая длительность; nil — без ограничения (практики без таймера).
    public let plannedDuration: TimeInterval?
    public private(set) var startedAt: Double
    public private(set) var pausedAt: Double?
    public private(set) var pausedTotal: Double
    public private(set) var stoppedAt: Double?

    public init(plannedDuration: TimeInterval?, now: Double) {
        self.plannedDuration = plannedDuration
        self.startedAt = now
        self.pausedAt = nil
        self.pausedTotal = 0
        self.stoppedAt = nil
    }

    public var isPaused: Bool { pausedAt != nil && stoppedAt == nil }
    public var isStopped: Bool { stoppedAt != nil }

    public mutating func pause(now: Double) {
        guard pausedAt == nil, stoppedAt == nil, !isFinished(now: now) else { return }
        pausedAt = now
    }

    public mutating func resume(now: Double) {
        guard let p = pausedAt, stoppedAt == nil else { return }
        pausedTotal += max(0, now - p)
        pausedAt = nil
    }

    /// Досрочное завершение.
    public mutating func stop(now: Double) {
        guard stoppedAt == nil else { return }
        stoppedAt = now
    }

    /// Активное время без пауз, не больше плановой длительности.
    public func activeElapsed(now: Double) -> Double {
        let end = stoppedAt ?? now
        let frozen = pausedAt.map { min($0, end) } ?? end
        let raw = max(0, frozen - startedAt - pausedTotal)
        if let plannedDuration { return min(raw, plannedDuration) }
        return raw
    }

    public func remaining(now: Double) -> Double? {
        plannedDuration.map { max(0, $0 - activeElapsed(now: now)) }
    }

    /// Доля сессии 0…1; nil без плановой длительности.
    public func progress(now: Double) -> Double? {
        guard let plannedDuration, plannedDuration > 0 else { return nil }
        return min(1, activeElapsed(now: now) / plannedDuration)
    }

    /// Время вышло.
    public func isFinished(now: Double) -> Bool {
        guard let plannedDuration else { return false }
        return activeElapsed(now: now) >= plannedDuration
    }

    /// Итоговый статус для записи сессии.
    public func finalStatus(now: Double) -> SessionStatus {
        if isFinished(now: now) { return .completed }
        if plannedDuration == nil && isStopped { return .completed }
        return isStopped ? .endedEarly : .running
    }
}

/// Монотонные секунды, которые продолжают идти, пока устройство спит.
public enum MonotonicClock {
    private static let origin = ContinuousClock.now

    public static func now() -> Double {
        let d = ContinuousClock.now - origin
        return Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
    }
}
