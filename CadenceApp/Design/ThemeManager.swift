import SwiftUI
import Observation

/// Owns the selected color scheme, persists it, and keeps `Theme.current` in
/// sync so every `Theme.*` accessor reflects the choice app-wide. Injected at
/// the root; the Settings picker mutates `scheme`.
@MainActor
@Observable
final class ThemeManager {
    private static let key = "appearance.scheme"

    var scheme: AppScheme {
        didSet {
            guard scheme != oldValue else { return }
            Theme.current = scheme.palette
            UserDefaults.standard.set(scheme.rawValue, forKey: Self.key)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
            .flatMap(AppScheme.init(rawValue:)) ?? .trackAtNight
        self.scheme = saved
        Theme.current = saved.palette   // theme the very first frame
    }
}
