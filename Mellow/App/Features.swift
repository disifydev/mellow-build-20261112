import Foundation

/// Переключатели возможностей. Код выключенных функций остаётся в проекте, но не используется.
enum Features {
    /// Вход через Apple. Выключен: релизная подпись не должна требовать новых возможностей App ID.
    /// Чтобы включить, верни ключ com.apple.developer.applesignin в Mellow.entitlements
    /// и CODE_SIGN_ENTITLEMENTS в project.yml.
    static let appleSignIn = false
}
