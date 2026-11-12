import SwiftUI
import PivchikDomain

/// Вертикальный барабан карточек: карточки лежат на цилиндре с горизонтальной осью.
/// Тянешь вниз — следующая карточка приходит сверху. Инерция и доводка до целой карточки.
struct DrumView: View {
    @Environment(\.palette) private var pal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let items: [PracticeDefinitionRecord]
    @Binding var index: Int
    var haptics: Bool

    /// Дробное положение барабана: 0 — первая карточка в центре.
    @State private var pos: Double = 0
    @State private var dragStart: Double?

    private let radius: Double = 205
    private let stepAngle: Double = 40
    private let pixelsPerCard: Double = 105

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.meta.id) { i, item in
                card(item, offset: Double(i) - pos)
                    .onTapGesture { snap(to: i) }
            }
            indicator
        }
        .frame(maxWidth: .infinity)
        .frame(height: 286)
        .mask(
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                   .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
        .contentShape(Rectangle())
        .highPriorityGesture(drag)
        .onChange(of: items.map { $0.meta.id }) { _, _ in
            pos = 0
            index = 0
        }
        .onAppear { pos = Double(index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Практики. Листай вниз и вверх")
        .accessibilityValue(items.indices.contains(index) ? items[index].title : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: snap(to: index + 1)
            case .decrement: snap(to: index - 1)
            @unknown default: break
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { g in
                if dragStart == nil { dragStart = pos }
                let maxPos = Double(max(0, items.count - 1))
                var p = (dragStart ?? pos) + Double(g.translation.height) / pixelsPerCard
                // Резинка за краями.
                if p < 0 { p /= 3 }
                if p > maxPos { p = maxPos + (p - maxPos) / 3 }
                pos = p
            }
            .onEnded { g in
                let start = dragStart ?? pos
                dragStart = nil
                // Инерция: смотрим, куда карточка «докатилась бы».
                let predicted = start + Double(g.predictedEndTranslation.height) / pixelsPerCard
                let limited = min(max(predicted, pos - 1.2), pos + 1.2)
                snap(to: Int(limited.rounded()))
            }
    }

    private func snap(to target: Int) {
        guard !items.isEmpty else { return }
        let t = min(max(target, 0), items.count - 1)
        if t != index { Haptics.tick(haptics) }
        index = t
        if reduceMotion {
            pos = Double(t)
        } else {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { pos = Double(t) }
        }
    }

    private func card(_ item: PracticeDefinitionRecord, offset o: Double) -> some View {
        let ab = abs(o)
        let angle = o * stepAngle
        let rad = angle * Double.pi / 180
        let y = -radius * sin(rad)
        let depth = radius * (1 - cos(rad))
        let scale = 820 / (820 + depth)
        let opacity = ab > 1.7 ? 0 : 1 - max(0, ab - 0.9) * 0.9
        return PracticeCard(item: item)
            .brightness(-min(ab, 2) * 0.1)
            .scaleEffect(scale)
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .center, anchorZ: 0, perspective: 0.45)
            .offset(y: y)
            .opacity(opacity)
            .zIndex(20 - ab * 4)
            .padding(.horizontal, 20)
            .allowsHitTesting(ab < 1.5)
    }

    private var indicator: some View {
        VStack(spacing: 5) {
            ForEach(items.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? pal.fg : pal.fg2)
                    .frame(width: 5, height: i == index ? 20 : 5)
            }
        }
        .animation(.easeOut(duration: 0.3), value: index)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 8)
        .zIndex(30)
        .allowsHitTesting(false)
    }
}

/// Горизонтальная карточка практики.
struct PracticeCard: View {
    let item: PracticeDefinitionRecord

    var body: some View {
        let info = item.type.info
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title).display(23)
                .fixedSize(horizontal: false, vertical: true)
            Text(blurb).txt(12.5).opacity(0.66)
                .padding(.top, 5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(item.type.isTimed ? "с таймером" : "по шагам").txt(11.5, .semibold).opacity(0.7)
        }
        .padding(.trailing, 120)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 140)
        .background(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                Color(hex: info.color)
                CatImage(name: info.cat, width: 128)
                    .offset(x: 6, y: 22)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Color(hex: 0x280A46).opacity(0.2), radius: 14, x: 0, y: 14)
    }

    private var blurb: String {
        if item.type == .freeRhythm {
            let p = item.pattern
            return "Вдох \(Int(p.inhale)) с, выдох \(Int(p.exhale)) с. Фазы от 1 до 15 секунд."
        }
        return item.type.info.blurb
    }
}
