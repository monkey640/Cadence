import SwiftUI
import CadenceCore

/// A complete color scheme. Every surface/text/verdict color the app draws
/// comes from the *current* palette, so swapping schemes reskins the whole app
/// without touching a single call site — `Theme.background` etc. stay stable.
struct Palette: Equatable, Sendable {
    var brand: Color
    var push: Color
    var hold: Color
    var backOff: Color
    var background: Color
    var card: Color
    var surfaceSecondary: Color
    var laneLine: Color
    var textPrimary: Color
    var textSecondary: Color
    /// Drives status bars, system controls, and light/dark-aware defaults.
    var colorScheme: ColorScheme
    /// Card elevation — lighter on light grounds where a heavy shadow reads dirty.
    var cardShadow: Double
}

/// The selectable schemes — each grounded in the track world, each a distinct
/// ground temperature so they read as moods, not recolors. This is the list the
/// Settings picker offers.
enum AppScheme: String, CaseIterable, Identifiable, Sendable {
    case trackAtNight, blueprint, photoFinish, oxblood, gunmetal, sodium, cinder, meetDay

    var id: String { rawValue }

    var name: String {
        switch self {
        case .trackAtNight: return "Track at night"
        case .blueprint: return "Blueprint"
        case .photoFinish: return "Photo finish"
        case .oxblood: return "Oxblood"
        case .gunmetal: return "Gunmetal"
        case .sodium: return "Sodium"
        case .cinder: return "Cinder"
        case .meetDay: return "Meet day"
        }
    }

    var blurb: String {
        switch self {
        case .trackAtNight: return "Warm near-black, Mondo red. Nocturnal, premium."
        case .blueprint: return "Ink-blue, electric cyan. Cool and clinical."
        case .photoFinish: return "Stark black, lane-yellow. High-energy, overtly track."
        case .oxblood: return "The Mondo surface darkened. Deepest, most tactile."
        case .gunmetal: return "Cool steel, safety-orange. The instrument."
        case .sodium: return "Umber under amber lamps. Warmest, nostalgic."
        case .cinder: return "Cool slate, rose accent. The boldest."
        case .meetDay: return "Concrete daylight. Bright, sunlit read."
        }
    }

    var isDark: Bool { self != .meetDay }

    var palette: Palette {
        switch self {
        case .trackAtNight:
            return Palette(brand: .hex(0xC4472B), push: .hex(0x2FBF71), hold: .hex(0xE8A13A), backOff: .hex(0xD94F30),
                           background: .hex(0x0C0B09), card: .hex(0x171512), surfaceSecondary: .hex(0x211E1A),
                           laneLine: .white.opacity(0.12), textPrimary: .hex(0xFAF7F2), textSecondary: .hex(0x94908A),
                           colorScheme: .dark, cardShadow: 0.40)
        case .blueprint:
            return Palette(brand: .hex(0x35C4CE), push: .hex(0x34C77B), hold: .hex(0xEAB44A), backOff: .hex(0xE8583C),
                           background: .hex(0x0A1017), card: .hex(0x111A24), surfaceSecondary: .hex(0x182430),
                           laneLine: .white.opacity(0.11), textPrimary: .hex(0xEAF2F7), textSecondary: .hex(0x7C8B99),
                           colorScheme: .dark, cardShadow: 0.40)
        case .photoFinish:
            return Palette(brand: .hex(0xF5CE3B), push: .hex(0x2FBF71), hold: .hex(0xE0872A), backOff: .hex(0xD6402A),
                           background: .hex(0x0A0A0A), card: .hex(0x151515), surfaceSecondary: .hex(0x1C1C1A),
                           laneLine: .white.opacity(0.11), textPrimary: .hex(0xF7F5EF), textSecondary: .hex(0x8A867E),
                           colorScheme: .dark, cardShadow: 0.45)
        case .oxblood:
            return Palette(brand: .hex(0xE8613A), push: .hex(0x2FBF71), hold: .hex(0xE8A13A), backOff: .hex(0xD94F30),
                           background: .hex(0x130A08), card: .hex(0x20120E), surfaceSecondary: .hex(0x2A1A15),
                           laneLine: .white.opacity(0.10), textPrimary: .hex(0xF6EEE8), textSecondary: .hex(0xA38C82),
                           colorScheme: .dark, cardShadow: 0.45)
        case .gunmetal:
            return Palette(brand: .hex(0xFF6A2B), push: .hex(0x29C06E), hold: .hex(0xE8A13A), backOff: .hex(0xE14A2E),
                           background: .hex(0x0C0E10), card: .hex(0x16191D), surfaceSecondary: .hex(0x1E2328),
                           laneLine: .white.opacity(0.11), textPrimary: .hex(0xEEF1F3), textSecondary: .hex(0x838C93),
                           colorScheme: .dark, cardShadow: 0.40)
        case .sodium:
            return Palette(brand: .hex(0xF2B44A), push: .hex(0x46B978), hold: .hex(0xDE7E28), backOff: .hex(0xD14226),
                           background: .hex(0x120D07), card: .hex(0x1E140A), surfaceSecondary: .hex(0x26190D),
                           laneLine: .white.opacity(0.10), textPrimary: .hex(0xF7EFE2), textSecondary: .hex(0xA79479),
                           colorScheme: .dark, cardShadow: 0.45)
        case .cinder:
            return Palette(brand: .hex(0xEE6E86), push: .hex(0x33C07A), hold: .hex(0xE8A93F), backOff: .hex(0xE1543C),
                           background: .hex(0x0D1114), card: .hex(0x161C21), surfaceSecondary: .hex(0x1E252B),
                           laneLine: .white.opacity(0.11), textPrimary: .hex(0xE9EEF0), textSecondary: .hex(0x808A8F),
                           colorScheme: .dark, cardShadow: 0.40)
        case .meetDay:
            return Palette(brand: .hex(0xC4472B), push: .hex(0x1FA85E), hold: .hex(0xB4761A), backOff: .hex(0xC33F22),
                           background: .hex(0xE9E7E1), card: .hex(0xF3F1EC), surfaceSecondary: .hex(0xDCD8CF),
                           laneLine: .black.opacity(0.12), textPrimary: .hex(0x1B1916), textSecondary: .hex(0x6E6A62),
                           colorScheme: .light, cardShadow: 0.14)
        }
    }
}

/// The "timing board" design language, now scheme-driven. The static accessors
/// read the *current* palette so every existing `Theme.background` call site
/// re-themes for free when the athlete picks a scheme.
enum Theme {
    /// The live palette. Set by `ThemeManager`; defaults so previews and the
    /// first frame are always themed.
    /// `nonisolated(unsafe)`: only written by the @MainActor `ThemeManager` and
    /// read during main-actor view rendering, so access is effectively confined
    /// to the main actor — no cross-actor race despite the mutable global.
    nonisolated(unsafe) static var current: Palette = AppScheme.trackAtNight.palette

    // Brand — brand moments only (streak, PR, start line), never a verdict.
    static var brand: Color { current.brand }
    static var accent: Color { current.brand }   // legacy alias

    // Verdicts — the only place these three colors mean push/hold/backOff.
    static var push: Color { current.push }
    static var hold: Color { current.hold }
    static var backOff: Color { current.backOff }

    // Surfaces.
    static var background: Color { current.background }
    static var card: Color { current.card }
    static var surfaceSecondary: Color { current.surfaceSecondary }
    static var laneLine: Color { current.laneLine }
    static var hairline: Color { current.laneLine }   // legacy alias

    // Text.
    static var textPrimary: Color { current.textPrimary }
    static var textSecondary: Color { current.textSecondary }

    /// The current scheme's light/dark, for `.preferredColorScheme`.
    static var scheme: ColorScheme { current.colorScheme }

    static func color(for verdict: Verdict) -> Color {
        switch verdict {
        case .push: return push
        case .hold: return hold
        case .backOff: return backOff
        }
    }
}

extension Color {
    /// 0xRRGGBB convenience so palettes read as their hex.
    static func hex(_ value: UInt) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

extension Verdict {
    /// Heavy-caps badge text. The verdict word always accompanies its color.
    var badgeText: String {
        switch self {
        case .push: return "PUSH"
        case .hold: return "HOLD"
        case .backOff: return "BACK OFF"
        }
    }

    var color: Color { Theme.color(for: self) }
}

extension ReadinessConfidence {
    var label: String {
        switch self {
        case .high: return "High confidence"
        case .moderate: return "Moderate confidence"
        case .low: return "Low — limited data"
        }
    }
}

// MARK: - Buttons

/// The single prominent action button. Defaults to brand; Today's "Start
/// session" tints it with the day's verdict color instead.
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(enabled ? (tint ?? Theme.brand) : Theme.surfaceSecondary)
            .foregroundStyle(enabled ? labelColor : Theme.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    /// On light grounds a near-black label reads better on the accent fill.
    private var labelColor: Color {
        Theme.current.colorScheme == .light ? Theme.background : Theme.textPrimary
    }
}

// MARK: - Shared modifiers

extension View {
    /// Full-bleed background used by every screen.
    func cadenceBackground() -> some View {
        self.background(Theme.background.ignoresSafeArea())
    }

    /// Standard card: 20pt corners, no border, elevation via a soft shadow tuned
    /// per scheme (lighter on light grounds).
    func cadenceCard(padding: CGFloat = 16, surface: Color? = nil) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface ?? Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(Theme.current.cardShadow), radius: 12, y: 4)
    }
}

/// A 1pt lane-line rule — the divider motif everywhere a separator is needed.
struct LaneLine: View {
    var body: some View {
        Rectangle().fill(Theme.laneLine).frame(height: 1)
    }
}
