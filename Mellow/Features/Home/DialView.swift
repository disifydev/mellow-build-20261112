import SwiftUI

/// Дуга 270° вокруг цифры: уровень тревоги 0…10.
struct DialArc: Shape {
    var fraction: CGFloat
    var inset: CGFloat = 26

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width, rect.height) / 2 - inset
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                 startAngle: .degrees(135), endAngle: .degrees(135 + 270 * Double(max(0.0001, fraction))), clockwise: false)
        return p
    }
}

/// Зона касания: кольцо вдоль дуги.
struct DialHitShape: Shape {
    func path(in rect: CGRect) -> Path {
        DialArc(fraction: 1).path(in: rect).strokedPath(StrokeStyle(lineWidth: 68, lineCap: .round))
    }
}

struct DialView: View {
    @Environment(\.palette) private var pal
    @Binding var level: Int
    var haptics: Bool

    private let side: CGFloat = 300
    private let radius: CGFloat = 124

    var body: some View {
        ZStack {
            DialArc(fraction: 1)
                .stroke(pal.track, style: StrokeStyle(lineWidth: 20, lineCap: .round))
            DialArc(fraction: CGFloat(level) / 10)
                .stroke(LinearGradient(colors: [Theme.dialStart.color, Theme.lav, Theme.pink], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .animation(.easeOut(duration: 0.3), value: level)
            ForEach(0...10, id: \.self) { i in
                tick(i)
            }
            knob
            endLabel("0", degrees: 135)
            endLabel("10", degrees: 405)
        }
        .frame(width: side, height: side)
        .contentShape(DialHitShape())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { g in
                set(value(at: g.location))
            }
        )
        .accessibilityElement()
        .accessibilityLabel("Уровень тревоги")
        .accessibilityValue("\(level) из 10, \(LevelInfo.of(level).name)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(level + 1)
            case .decrement: set(level - 1)
            @unknown default: break
            }
        }
    }

    private func point(_ degrees: Double, r: CGFloat) -> CGPoint {
        let a = degrees * Double.pi / 180
        return CGPoint(x: side / 2 + r * CGFloat(cos(a)), y: side / 2 + r * CGFloat(sin(a)))
    }

    private func tick(_ i: Int) -> some View {
        let p = point(135 + 270 * Double(i) / 10, r: radius)
        let on = i <= level
        let d: CGFloat = i % 5 == 0 ? 5.2 : 3.2
        return Circle()
            .fill(on ? Color.white.opacity(0.9) : pal.fg.opacity(0.3))
            .frame(width: d, height: d)
            .position(p)
    }

    private var knob: some View {
        let p = point(135 + 270 * Double(level) / 10, r: radius)
        let dot = Theme.dialStart.mix(Theme.dialEnd, Double(level) / 10).color
        return Circle().fill(Color.white)
            .frame(width: 34, height: 34)
            .shadow(color: Color(hex: 0x3C1E6E).opacity(0.35), radius: 4, x: 0, y: 4)
            .overlay(Circle().fill(dot).frame(width: 14, height: 14))
            .position(p)
            .animation(.easeOut(duration: 0.25), value: level)
    }

    private func endLabel(_ text: String, degrees: Double) -> some View {
        let p = point(degrees, r: radius + 24)
        return Text(text).txt(12, .semibold)
            .foregroundStyle(pal.fg.opacity(0.55))
            .position(x: p.x + (degrees < 200 ? 6 : -6), y: p.y + 2)
    }

    private func value(at location: CGPoint) -> Int {
        let x = Double(location.x - side / 2)
        let y = Double(location.y - side / 2)
        var a = (atan2(y, x) * 180 / Double.pi - 135 + 720).truncatingRemainder(dividingBy: 360)
        if a > 270 { a = a > 315 ? 0 : 270 }
        return Int((a / 270 * 10).rounded())
    }

    private func set(_ new: Int) {
        let v = min(10, max(0, new))
        guard v != level else { return }
        level = v
        Haptics.tick(haptics)
    }
}
