import SwiftUI
import UIKit

/// Фон-аура: три размытых пятна, которые медленно плывут, и лёгкое зерно.
struct AuraBackground: View {
    @Environment(\.palette) private var pal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                pal.bg
                blob(pal.blobs[0], 340)
                    .position(x: 70 + (drift ? 60 : 0), y: 120 + (drift ? 50 : 0))
                blob(pal.blobs[1], 380)
                    .position(x: w - 40 - (drift ? 70 : 0), y: 430 - (drift ? 40 : 0))
                blob(pal.blobs[2], 320)
                    .position(x: 90 + (drift ? 50 : 0), y: h - 60 - (drift ? 60 : 0))
                Image(uiImage: Grain.image)
                    .resizable(resizingMode: .tile)
                    .opacity(pal.isDark ? 0.10 : 0.17)
                    .blendMode(.overlay)
            }
            .frame(width: w, height: h)
            .clipped()
            .animation(.easeInOut(duration: 1.0), value: pal)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func blob(_ color: Color, _ size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 56)
            .opacity(pal.blobOpacity)
    }
}

/// Плитка зерна: рисуется один раз.
enum Grain {
    static let image: UIImage = {
        let side = 96
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { ctx in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            for y in 0..<side {
                for x in 0..<side {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let v = CGFloat((seed >> 33) & 0xFF) / 255
                    UIColor(white: v, alpha: 0.55).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
}

/// Обёртка экрана: считает палитру, кладёт фон и задаёт цвет текста.
struct Themed<Content: View>: View {
    @EnvironmentObject private var store: AppStore
    var background: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        let pal = store.palette
        ZStack {
            if background {
                AuraBackground()
            }
            content()
        }
        .environment(\.palette, pal)
        .foregroundStyle(pal.fg)
        .tint(pal.fg)
        .preferredColorScheme(pal.isDark ? .dark : .light)
        .dynamicTypeSize(.xSmall ... .xxLarge)
    }
}
