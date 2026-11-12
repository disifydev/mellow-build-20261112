import SwiftUI
import UIKit
import PivchikDomain

/// Практика целиком: оценка «до» → сама практика → оценка «после» → сохранено.
struct PracticeFlowView: View {
    enum Step { case before, run, after, done }

    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss

    let practiceID: UUID
    let seconds: Int
    let autostart: Bool
    let historyID: UUID?

    @State private var step: Step = .before
    @State private var before: Int?
    @State private var after: Int?
    @State private var felt: FeltResult?
    @State private var note = ""
    @State private var timer = SessionTimer(plannedDuration: nil, now: 0)
    @State private var sessionID: UUID?
    @State private var stepTexts: [String] = []
    @State private var activeSeconds: Double = 0
    @State private var endedEarly = false
    @State private var returned = false
    @State private var opened = false

    var body: some View {
        Group {
            if let p = store.practice(id: practiceID) {
                switch step {
                case .before: beforeView(p)
                case .run:
                    if p.type.isTimed {
                        BreathRunView(practice: p, timer: $timer, onFinish: finish, onClose: close)
                    } else {
                        StepsRunView(practice: p, texts: $stepTexts, onFinish: finish, onClose: close)
                    }
                case .after: afterView
                case .done: doneView
                }
            } else {
                CTAButton(title: "Закрыть", small: true) { dismiss() }.padding(20)
            }
        }
        .onAppear(perform: open)
    }

    // MARK: Шаги

    private func open() {
        guard !opened else { return }
        opened = true
        guard autostart || Launch.step != nil else { return }
        if Launch.step != nil { before = 7 }
        start()
        if Launch.step == "after" || Launch.step == "done" { finish() }
        if Launch.step != nil {
            // Только для снимков: показываем сессию так, будто она прошла целиком.
            activeSeconds = Double(seconds)
            endedEarly = false
        }
        if Launch.step == "done" {
            after = 2
            felt = .easier
            save()
        }
    }

    private func start() {
        guard let p = store.practice(id: practiceID) else { return }
        let planned: TimeInterval? = p.type.isTimed ? TimeInterval(seconds) : nil
        timer = SessionTimer(plannedDuration: planned, now: MonotonicClock.now())
        stepTexts = Array(repeating: "", count: p.type.steps.count)
        let rec = PracticeSessionRecord(meta: store.meta(), practiceID: p.meta.id, practiceType: p.type, startedAt: Date(), zoneID: store.zone,
                                        plannedDuration: planned, status: .running, before: before, settingsSnapshot: p.settings,
                                        historyIDs: historyID.map { [$0] } ?? [])
        sessionID = rec.meta.id
        store.mutate { $0.sessions.append(rec) }
        step = .run
    }

    /// Практика закончилась (время вышло или завершена раньше): фиксируем длительность и статус.
    private func finish() {
        guard step == .run else { return }
        let now = MonotonicClock.now()
        if !timer.isFinished(now: now) { timer.stop(now: now) }
        let status = timer.finalStatus(now: now)
        activeSeconds = timer.activeElapsed(now: now)
        endedEarly = status == .endedEarly
        let texts = stepTexts.compactMap { $0.nilIfEmpty }
        let active = activeSeconds
        if let id = sessionID {
            store.update(\Snapshot.sessions, id: id) { s in
                s.endedAt = Date()
                s.activeDuration = active
                s.status = status == .running ? .endedEarly : status
                if !texts.isEmpty { s.notes = texts.joined(separator: "\n") }
            }
        }
        step = .after
    }

    private func save() {
        let extra = note.nilIfEmpty
        let a = after
        let f = felt
        if let id = sessionID {
            store.update(\Snapshot.sessions, id: id) { s in
                s.after = a
                s.feltResult = f
                if let extra {
                    s.notes = [s.notes, extra].compactMap { $0 }.joined(separator: "\n")
                }
            }
        }
        if let a { store.level = a }
        Haptics.success(store.settings.hapticsEnabled)
        step = .done
    }

    private func close() {
        if step == .run {
            let now = MonotonicClock.now()
            let tooShort = timer.activeElapsed(now: now) < 5
            finish()
            if tooShort, let id = sessionID { store.softDelete(\Snapshot.sessions, id: id) }
        }
        dismiss()
    }

    // MARK: До

    private func beforeView(_ p: PracticeDefinitionRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                RoundButton(icon: "xmark", label: "Закрыть") { dismiss() }
                Spacer()
                Cap(p.type.isTimed ? "\(seconds / 60) мин" : "по шагам")
            }
            BigHeader(title: p.title, subtitle: "перед началом")
            CatImage(name: p.type.info.cat, width: 170)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            LevelCard(title: "Тревога сейчас", value: $before, fallback: store.level,
                      hint: "Можно пропустить. Тогда сессия сохранится, но в расчёт изменений не войдёт.")
            CTAButton(title: "Начать", icon: "play.fill", action: start)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    // MARK: После

    private var afterView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                BigHeader(title: "Готово.", subtitle: "Как ты сейчас?")
                CatImage(name: "PivLove", width: 150)
                    .frame(maxWidth: .infinity)
                LevelCard(title: "Тревога после", value: $after, fallback: 3)
                SegControl(items: FeltResult.allCases.map { (Optional($0), $0.title) }, selection: $felt)
                MField(title: "Что помогло", text: $note, placeholder: "Например: длинный выдох", lines: 2)
                CTAButton(title: "Сохранить", action: save)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Сохранено

    private var doneView: some View {
        let change: Int? = (before != nil && after != nil) ? (before ?? 0) - (after ?? 0) : nil
        return ZStack {
            VStack(alignment: .leading, spacing: 14) {
                BigHeader(title: "Сохранено.", subtitle: (change ?? 0) > 0 ? "Стало тише" : "Ты это сделала")
                CatImage(name: "PivStar", width: 190)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 6) {
                    if let change, let b = before, let a = after {
                        Text("\(b) → \(a)").display(40).monospacedDigit()
                        Cap(changeText(change))
                    } else {
                        Lab("Оценка пропущена")
                        Cap("Сессия в дневнике, в расчёт изменений не входит.")
                    }
                }
                .frame(maxWidth: .infinity)
                .card()
                if returned {
                    Cap("Отмечено: «вернулась к своему делу». Это достижение за действие, а не за отсутствие тревоги.")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    CTAButton(title: "Я вернулась к своему делу", icon: "star") {
                        store.addReturned(sourceID: sessionID)
                        Haptics.success(store.settings.hapticsEnabled)
                        returned = true
                    }
                }
                CTAButton(title: "Закрыть", small: true) { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            StarBurst().id(returned)
        }
    }

    private func changeText(_ change: Int) -> String {
        var parts: [String] = []
        if change > 0 {
            parts.append("тревога ниже на \(change)")
        } else if change < 0 {
            parts.append("тревога выше на \(-change)")
        } else {
            parts.append("без изменений")
        }
        parts.append(Fmt.duration(max(1, activeSeconds)))
        if endedEarly { parts.append("завершена раньше") }
        return parts.joined(separator: " · ")
    }
}

/// Дыхание: три стеклянных круга сходятся на вдохе и расходятся на выдохе.
/// Время берётся из SessionTimer на монотонных часах, положение в ритме — из BreathPattern.position(at:).
struct BreathRunView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let practice: PracticeDefinitionRecord
    @Binding var timer: SessionTimer
    var onFinish: () -> Void
    var onClose: () -> Void

    @State private var lastPhaseKey = ""
    @State private var finished = false
    @State private var tone = TonePlayer()
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var pattern: BreathPattern { practice.pattern }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                RoundButton(icon: "xmark", label: "Закрыть", action: onClose)
                Spacer()
                RoundButton(icon: store.settings.soundEnabled ? "speaker.wave.2" : "speaker.slash",
                            label: store.settings.soundEnabled ? "Выключить звук" : "Включить звук") {
                    store.updateSettings { $0.soundEnabled.toggle() }
                }
                .opacity(store.settings.soundEnabled ? 1 : 0.5)
            }
            BigHeader(title: practice.title, subtitle: pattern.phases.map { String(Int($0.duration)) }.joined(separator: " · "), size: 30)
            TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : nil, paused: false)) { _ in
                live(now: MonotonicClock.now())
            }
            controls
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .onReceive(ticker) { _ in tick() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            tone.stop()
        }
    }

    /// Всё, что меняется каждый кадр.
    private func live(now: Double) -> some View {
        let elapsed = timer.activeElapsed(now: now)
        let pos = pattern.position(at: elapsed)
        let q = reduceMotion ? 0.5 : openness(pos)
        let left = Int((timer.remaining(now: now) ?? 0).rounded(.up))
        let progress = timer.progress(now: now) ?? 0
        return VStack(spacing: 14) {
            ZStack {
                circle(q, x: 0, y: -62)
                circle(q, x: -56, y: 34)
                circle(q, x: 56, y: 34)
                VStack(spacing: 6) {
                    Text(timer.isPaused ? "Пауза" : practice.type.phaseName(pos.phase)).display(24)
                    Text("\(pos.secondsLeftDisplay)").display(52).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 270)
            HStack {
                Cap("осталось \(left / 60):\(left % 60 < 10 ? "0" : "")\(left % 60)")
                Spacer()
                Cap("Пивчик дышит с тобой")
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(pal.track)
                    Capsule().fill(pal.fg).frame(width: max(6, geo.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 6)
            .accessibilityLabel("Прогресс сессии")
            .accessibilityValue("\(Int(progress * 100)) процентов")
        }
    }

    /// 0 — круги разошлись (выдох), 1 — сошлись (вдох). Плавность по краям фазы.
    private func openness(_ pos: BreathPosition) -> Double {
        let k = pos.phaseProgress
        let eased = k < 0.5 ? 2 * k * k : 1 - pow(-2 * k + 2, 2) / 2
        switch pos.phase {
        case .inhale: return eased
        case .holdIn: return 1
        case .exhale: return 1 - eased
        case .holdOut: return 0
        }
    }

    private func circle(_ q: Double, x: CGFloat, y: CGFloat) -> some View {
        let spread = CGFloat((1 - q) * 1.25)
        return Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle().fill(RadialGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.2), Color.white.opacity(0.08)],
                                             center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: 90))
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: 1))
            .frame(width: 128, height: 128)
            .shadow(color: pal.shadow, radius: 14, x: 0, y: 12)
            .scaleEffect(CGFloat(0.82 + q * 0.42))
            .offset(x: x * spread, y: y * spread)
            .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            control(timer.isPaused ? "play.fill" : "pause", timer.isPaused ? "Продолжить" : "Пауза") {
                let now = MonotonicClock.now()
                if timer.isPaused { timer.resume(now: now) } else { timer.pause(now: now) }
            }
            control("stop.fill", "Завершить раньше") { done() }
            control("checkmark", "Готово") { done() }
        }
    }

    private func control(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .glass(24)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    private func done() {
        guard !finished else { return }
        finished = true
        onFinish()
    }

    /// Десять раз в секунду: конец сессии и смена фазы (тон и вибрация).
    private func tick() {
        guard !finished else { return }
        let now = MonotonicClock.now()
        if timer.isFinished(now: now) {
            done()
            return
        }
        guard !timer.isPaused else { return }
        let pos = pattern.position(at: timer.activeElapsed(now: now))
        let key = "\(pos.cycleIndex)-\(pos.phase.rawValue)"
        guard key != lastPhaseKey else { return }
        lastPhaseKey = key
        let inhale = pos.phase == .inhale
        if (inhale || pos.phase == .exhale) && store.settings.soundEnabled {
            tone.play(up: inhale)
        }
        Haptics.soft(store.settings.hapticsEnabled, strong: inhale)
    }
}

/// Практики без таймера: простые шаги, часть — с полем для записи.
struct StepsRunView: View {
    @Environment(\.palette) private var pal
    let practice: PracticeDefinitionRecord
    @Binding var texts: [String]
    var onFinish: () -> Void
    var onClose: () -> Void

    @State private var index = 0

    var body: some View {
        let steps = practice.type.steps
        let i = min(index, max(0, steps.count - 1))
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                RoundButton(icon: "xmark", label: "Закрыть", action: onClose)
                Spacer()
                Cap("шаг \(i + 1) из \(steps.count)")
            }
            BigHeader(title: practice.title, subtitle: "по шагам", size: 30)
            HStack(spacing: 5) {
                ForEach(steps.indices, id: \.self) { k in
                    Capsule().fill(k <= i ? pal.fg : pal.track).frame(height: 5)
                }
            }
            .accessibilityHidden(true)
            if steps.indices.contains(i) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(steps[i].title).display(24).fixedSize(horizontal: false, vertical: true)
                    Text(steps[i].hint).txt(15).foregroundStyle(pal.fg3).fixedSize(horizontal: false, vertical: true)
                }
                .card()
                if steps[i].input && texts.indices.contains(i) {
                    MField(title: "Мои слова", text: $texts[i], placeholder: "Можно пропустить", lines: 3)
                }
            }
            CatImage(name: practice.type.info.cat, width: 140)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 10) {
                if i > 0 {
                    CTAButton(title: "Назад", small: true) { index = i - 1 }
                }
                CTAButton(title: i + 1 < steps.count ? "Дальше" : "Готово", small: true) {
                    if i + 1 < steps.count { index = i + 1 } else { onFinish() }
                }
            }
            Cap("Любой шаг можно пропустить.")
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }
}
