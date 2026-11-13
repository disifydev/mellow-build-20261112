import SwiftUI

// MARK: Стекло

struct GlassBackground: ViewModifier {
    @Environment(\.palette) private var pal
    var radius: CGFloat
    var strong: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content.background {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(strong ? pal.glass2 : pal.glass))
                .overlay(shape.strokeBorder(pal.edge, lineWidth: 1))
                .shadow(color: pal.shadow.opacity(0.7), radius: 12, x: 0, y: 8)
        }
    }
}

extension View {
    /// Стеклянная подложка с белой кромкой.
    func glass(_ radius: CGFloat = 28, strong: Bool = false) -> some View {
        modifier(GlassBackground(radius: radius, strong: strong))
    }

    /// Стеклянная карточка на всю ширину.
    func card(_ padding: CGFloat = 16, radius: CGFloat = 28) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius)
    }
}

/// Нажатие: лёгкое сжатие, как в макете.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: Заголовки и подписи

struct BigHeader<Trailing: View>: View {
    @Environment(\.palette) private var pal
    let title: String
    let subtitle: String
    var size: CGFloat = 39
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: -2) {
                Text(title).display(size).foregroundStyle(pal.fg)
                Text(subtitle).display(size).foregroundStyle(pal.fg2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension BigHeader where Trailing == EmptyView {
    init(title: String, subtitle: String, size: CGFloat = 39) {
        self.init(title: title, subtitle: subtitle, size: size, trailing: { EmptyView() })
    }
}

/// Заголовок карточки.
struct H: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).display(18).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
}

/// Мелкая подпись.
struct Cap: View {
    @Environment(\.palette) private var pal
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).txt(12.5).foregroundStyle(pal.fg3).fixedSize(horizontal: false, vertical: true)
    }
}

/// Строка-метка.
struct Lab: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).txt(14.5, .semibold).fixedSize(horizontal: false, vertical: true)
    }
}

/// Большое число с подписью справа.
struct Num: View {
    @Environment(\.palette) private var pal
    let value: String
    var small: String = ""
    var size: CGFloat = 34

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).display(size).monospacedDigit()
            if !small.isEmpty {
                Text(small).txt(13).foregroundStyle(pal.fg3).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct Sep: View {
    @Environment(\.palette) private var pal
    var body: some View {
        Rectangle().fill(pal.edge.opacity(0.7)).frame(height: 1).padding(.vertical, 2)
    }
}

// MARK: Кнопки

struct RoundButton: View {
    @Environment(\.palette) private var pal
    let icon: String
    let label: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint ?? pal.fg)
                .frame(width: 44, height: 44)
                .glass(22)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

struct CTAButton: View {
    @Environment(\.palette) private var pal
    let title: String
    var icon: String? = nil
    var trailingIcon: String? = nil
    var small: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon).font(.system(size: small ? 14 : 16, weight: .bold))
                }
                Text(title).display(small ? 15 : 18).lineLimit(1).minimumScaleFactor(0.7)
                if let trailingIcon {
                    Image(systemName: trailingIcon).font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(pal.fg)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: small ? 46 : 58)
            .glass(30, strong: true)
        }
        .buttonStyle(PressStyle())
    }
}

struct Chip: View {
    @Environment(\.palette) private var pal
    let text: String
    var icon: String? = nil
    var isOn: Bool = false
    var height: CGFloat = 38
    var bold: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(isOn ? .isSelected : [])
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
            }
            Text(text).txt(height < 34 ? 12 : 13.5, bold ? .bold : .medium).lineLimit(1)
        }
        .foregroundStyle(isOn ? pal.onFg : pal.fg)
        .padding(.horizontal, height < 34 ? 11 : 15)
        .frame(height: height)
        .background {
            Capsule().fill(isOn ? pal.on : pal.glass)
                .overlay(Capsule().strokeBorder(pal.edge, lineWidth: 1))
        }
    }
}

/// Тёмная плашка с названием истории.
struct TagPill: View {
    let text: String
    var body: some View {
        Text(text).txt(12).lineLimit(1)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(Theme.ink.opacity(0.88)))
    }
}

/// Переключатель-сегменты в стеклянной капсуле.
struct SegControl<T: Hashable>: View {
    @Environment(\.palette) private var pal
    let items: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                segment(item.0, item.1)
            }
        }
        .padding(4)
        .glass(22)
    }

    private func segment(_ value: T, _ title: String) -> some View {
        let on = selection == value
        return Button {
            withAnimation(.easeOut(duration: 0.25)) { selection = value }
        } label: {
            Text(title).txt(12.5, .semibold).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(on ? pal.onFg : pal.fg)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background {
                    if on {
                        Capsule().fill(pal.on).shadow(color: pal.shadow, radius: 5, x: 0, y: 4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Горизонтальная лента, выходящая за поля экрана.
struct HScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
        }
        .padding(.horizontal, -20)
    }
}

// MARK: Ползунок 0…10

struct LevelSlider: View {
    @Environment(\.palette) private var pal
    @Binding var value: Int
    let label: String
    var onChange: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = CGFloat(value) / 10
            let knobX = 13 + (w - 26) * frac
            ZStack(alignment: .leading) {
                Capsule().fill(pal.track).frame(height: 8)
                LinearGradient(colors: [Theme.mint, Theme.lav, Theme.pink], startPoint: .leading, endPoint: .trailing)
                    .frame(width: w, height: 8)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: max(8, knobX), height: 8)
                    }
                Circle().fill(Color.white)
                    .frame(width: 26, height: 26)
                    .shadow(color: Color(hex: 0x3C1E6E).opacity(0.3), radius: 5, x: 0, y: 4)
                    .offset(x: knobX - 13)
            }
            .frame(width: w, height: 30)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let raw = (g.location.x - 13) / max(1, w - 26)
                    let v = Int((min(max(raw, 0), 1) * 10).rounded())
                    if v != value {
                        value = v
                        onChange?()
                    }
                }
            )
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(value) из 10")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(10, value + 1)
            case .decrement: value = max(0, value - 1)
            @unknown default: break
            }
            onChange?()
        }
    }
}

/// Карточка оценки: подпись, число и ползунок. Оценку можно не ставить.
struct LevelCard: View {
    @Environment(\.palette) private var pal
    let title: String
    @Binding var value: Int?
    var fallback: Int = 5
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Lab(title)
                Spacer()
                if let value {
                    Text("\(value)").display(30).monospacedDigit()
                } else {
                    Text("не отмечено").txt(13).foregroundStyle(pal.fg3)
                }
            }
            LevelSlider(value: Binding(get: { value ?? fallback }, set: { value = $0 }), label: title)
            if let hint { Cap(hint) }
        }
        .card()
    }
}

// MARK: Поля ввода

struct MField: View {
    @Environment(\.palette) private var pal
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var lines: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).txt(12.5, .semibold).foregroundStyle(pal.fg3)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(pal.fg2), axis: .vertical)
                .lineLimit(lines...max(lines, 6))
                .txt(14.5)
                .foregroundStyle(pal.fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(18)
                .accessibilityLabel(title)
        }
    }
}

/// Подпись над группой элементов формы.
struct FieldGroup<Content: View>: View {
    @Environment(\.palette) private var pal
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).txt(12.5, .semibold).foregroundStyle(pal.fg3)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Строка «победы» с галочкой.
struct WinRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.mint))
            Text(text).txt(14.5).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

/// Знак настроения: мягкий белый круг с символом. Заменил кота — без персонажа, чище.
struct Emblem: View {
    let name: String
    var width: CGFloat

    static func symbol(_ name: String) -> String {
        switch name {
        case "PivBreathe": return "wind"
        case "PivCalm": return "leaf"
        case "PivHappy": return "sun.max"
        case "PivStar": return "star"
        case "PivRead": return "book"
        case "PivSleep": return "moon"
        case "PivTea": return "cup.and.saucer"
        case "PivLove": return "heart"
        case "PivPeek": return "eye"
        default: return "sparkle"
        }
    }

    var body: some View {
        let d = width * 0.62
        ZStack {
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0.5)],
                                         center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: d * 0.8))
            Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
            Image(systemName: Self.symbol(name))
                .font(.system(size: d * 0.34, weight: .medium))
                .foregroundStyle(Theme.ink.opacity(0.75))
        }
        .frame(width: d, height: d)
        .shadow(color: Color(hex: 0x280A46).opacity(0.12), radius: d * 0.12, x: 0, y: d * 0.08)
        .accessibilityHidden(true)
    }
}

/// Шапка листа: заголовок в две строки.
struct SheetScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Мягкая подложка под строкой состояния: прокрученный текст не залезает под часы и «островок».
struct TopFade: View {
    @Environment(\.palette) private var pal

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: pal.bg, location: 0),
                                       .init(color: pal.bg.opacity(0.85), location: 0.6),
                                       .init(color: pal.bg.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.safeAreaInsets.top + 12)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Прокрутка вкладки с отступом под таббар; умеет прокрутить к блоку по аргументу -anchor.
struct TabScroll<Content: View>: View {
    var bottom: CGFloat = 116
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) { content() }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, bottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .top) { TopFade() }
            .onAppear {
                guard let anchor = Launch.anchor else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
        }
    }
}
