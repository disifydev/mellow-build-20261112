import Foundation
import AuthenticationServices

/// Необязательный вход через Apple. Хранится только идентификатор и имя (в связке ключей);
/// данные дневника к аккаунту в этой версии не привязаны и при выходе остаются.
extension AppStore {
    static let appleUserKey = "appleUserID"
    static let appleNameKey = "appleName"

    func loadAppleAccount() {
        if isDemo {
            if Launch.args.contains("-demoAccount") {
                appleUserID = "demo"
                appleName = "Алекс"
            }
            return
        }
        appleUserID = Keychain.get(AppStore.appleUserKey)
        appleName = Keychain.get(AppStore.appleNameKey)
    }

    func signedInWithApple(_ credential: ASAuthorizationAppleIDCredential) {
        appleUserID = credential.user
        Keychain.set(AppStore.appleUserKey, credential.user)
        // Имя Apple отдаёт только при первом входе — потом остаётся сохранённое.
        if let given = credential.fullName?.givenName?.nilIfEmpty {
            appleName = given
            Keychain.set(AppStore.appleNameKey, given)
        }
    }

    func signOutApple() {
        appleUserID = nil
        appleName = nil
        Keychain.delete(AppStore.appleUserKey)
        Keychain.delete(AppStore.appleNameKey)
    }

    /// При запуске: если доступ отозван в настройках Apple ID — выходим локально.
    func checkAppleCredential() {
        guard !isDemo, let id = appleUserID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: id) { [weak self] state, _ in
            guard state == .revoked else { return }
            Task { @MainActor in
                self?.signOutApple()
            }
        }
    }
}
