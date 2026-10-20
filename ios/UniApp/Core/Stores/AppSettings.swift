import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private static let languageKey = "settings.language"
    private static let biometricKey = "settings.biometricLock"

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey) }
    }

    var biometricLock: Bool {
        didSet { UserDefaults.standard.set(biometricLock, forKey: Self.biometricKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        language = defaults.string(forKey: Self.languageKey).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        biometricLock = defaults.bool(forKey: Self.biometricKey)
    }

    var strings: Strings {
        Strings(language: language)
    }
}
