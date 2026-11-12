import SwiftUI
import UIKit

/// Цвет в виде трёх чисел — чтобы смешивать палитры (аура теплеет с уровнем тревоги).
struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    func mix(_ other: RGB, _ t: Double) -> RGB {
        let k = min(max(t, 0), 1)
        return RGB(r: r + (other.r - r) * k, g: g + (other.g - g) * k, b: b + (other.b - b) * k)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

extension Color {
    init(hex: UInt32) {
        self = RGB(hex).color
    }
}

/// Постоянные цвета макета v3.
enum Theme {
    /// PostScript-имя шрифта заголовков — единственное место, где оно задано.
    /// Нет такого шрифта в сборке — заголовки идут системным жирным с плотным трекингом.
    static let headingFontName = "MellowSans-Bold"

    static let ink = Color(hex: 0x1E1530)
    static let mint = Color(hex: 0xA9DCC6)
    static let pink = Color(hex: 0xF29AC4)
    static let lav = Color(hex: 0xB9A3E7)
    static let peach = Color(hex: 0xF9C6A8)
    static let gold = Color(hex: 0xF8D66D)
    static let dialStart = RGB(0x8FD3B6)
    static let dialEnd = RGB(0xF29AC4)
}

/// Время суток для фона.
enum TimeOfDay: String {
    case morn, day, eve, night

    /// Тёмная палитра включается после 19:00, только если включена настройка «Тёмная тема вечером».
    static func current(date: Date, darkEvening: Bool) -> TimeOfDay {
        let hour = Calendar.current.component(.hour, from: date)
        if darkEvening {
            if hour >= 23 || hour < 5 { return .night }
            if hour >= 19 { return .eve }
        }
        return (5..<12).contains(hour) ? .morn : .day
    }

    var isDark: Bool { self == .eve || self == .night }

    var background: RGB {
        switch self {
        case .morn: return RGB(0xF4E7EA)
        case .day: return RGB(0xEADFF6)
        case .eve: return RGB(0x1B1328)
        case .night: return RGB(0x0E0A15)
        }
    }

    var blobs: [RGB] {
        switch self {
        case .morn: return [RGB(0xF9D9B8), RGB(0xBFE3D0), RGB(0xF7DDEB)]
        case .day: return [RGB(0xA9DCC6), RGB(0xB9A3E7), RGB(0xF7DDEB)]
        case .eve: return [RGB(0x5FA890), RGB(0x6B4FB8), RGB(0xB96A9A)]
        case .night: return [RGB(0x356E60), RGB(0x44318A), RGB(0x74426E)]
        }
    }
}

/// Палитра экрана: зависит от времени суток и уровня тревоги.
struct Palette: Equatable {
    var bg: Color
    var blobs: [Color]
    var isDark: Bool

    static let tense: [RGB] = [RGB(0xF29AC4), RGB(0x8E6FD6), RGB(0xF9C6A8)]

    static func make(level: Int, tod: TimeOfDay) -> Palette {
        let k = max(0, Double(level - 2) / 8) * (tod.isDark ? 0.75 : 1)
        let base = tod.blobs
        var mixed: [Color] = []
        for i in 0..<3 {
            mixed.append(base[i].mix(tense[i], k).color)
        }
        return Palette(bg: tod.background.color, blobs: mixed, isDark: tod.isDark)
    }

    var fg: Color { isDark ? Color.white : Theme.ink }
    var fg2: Color { fg.opacity(isDark ? 0.42 : 0.44) }
    var fg3: Color { fg.opacity(isDark ? 0.68 : 0.64) }
    var glass: Color { Color.white.opacity(isDark ? 0.09 : 0.42) }
    var glass2: Color { Color.white.opacity(isDark ? 0.16 : 0.66) }
    var edge: Color { Color.white.opacity(isDark ? 0.2 : 0.85) }
    var track: Color { Color.white.opacity(isDark ? 0.14 : 0.5) }
    var shadow: Color { isDark ? Color.black.opacity(0.3) : Color(hex: 0x462882).opacity(0.16) }
    var on: Color { Color.white }
    var onFg: Color { Theme.ink }
    var blobOpacity: Double { isDark ? 0.72 : 1 }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.make(level: 3, tod: .day)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Шрифты: заголовки — Theme.headingFontName (если файл есть в сборке), иначе системный жирный; текст — Involve.
enum MFont {
    static let hasDisplay: Bool = UIFont(name: Theme.headingFontName, size: 12) != nil

    static func display(_ size: CGFloat) -> Font {
        if hasDisplay {
            return Font.custom(Theme.headingFontName, size: size, relativeTo: .title2)
        }
        let scaled = UIFontMetrics(forTextStyle: .title2).scaledValue(for: size)
        return Font.system(size: scaled, weight: .bold)
    }

    static func text(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Involve-Bold"
        case .semibold: name = "Involve-SemiBold"
        case .regular, .light, .thin, .ultraLight: name = "Involve-Regular"
        default: name = "Involve-Medium"
        }
        return Font.custom(name, size: size, relativeTo: .body)
    }
}

extension View {
    /// Заголовочный шрифт с плотным трекингом.
    func display(_ size: CGFloat) -> some View {
        self.font(MFont.display(size)).tracking(-size * 0.01)
    }

    /// Текстовый шрифт Involve.
    func txt(_ size: CGFloat, _ weight: Font.Weight = .medium) -> some View {
        self.font(MFont.text(size, weight))
    }
}

/// Вибрация: всегда через настройку пользователя.
enum Haptics {
    static func tick(_ enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func soft(_ enabled: Bool, strong: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: strong ? .medium : .soft).impactOccurred()
    }

    static func success(_ enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
