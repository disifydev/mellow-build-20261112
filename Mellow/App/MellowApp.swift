import SwiftUI
import CoreText

@main
struct MellowApp: App {
    @StateObject private var store: AppStore
    @StateObject private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        MellowApp.registerFonts()
        _store = StateObject(wrappedValue: AppStore(demo: Launch.seedDemo))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.enterBackground() } else if phase != .active { store.saveNow() }
        }
    }

    /// Подстраховка к UIAppFonts: регистрирует все .ttf из сборки (в том числе шрифт заголовков, когда он появится).
    private static func registerFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
