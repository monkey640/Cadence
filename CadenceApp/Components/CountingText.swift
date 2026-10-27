import SwiftUI

/// A number that animates through intermediate values — the race-clock count-up
/// behind the score reveal. Drive it by changing `value` inside `withAnimation`;
/// SwiftUI interpolates `animatableData` and this view re-renders each frame.
/// Monospaced digits (via the caller's font) keep the layout from jittering.
struct CountingText: View, Animatable {
    var value: Double

    // nonisolated: `Animatable` is a nonisolated protocol while `View` pulls the
    // struct onto the main actor — and SwiftUI drives this accessor from the
    // animation system. Safe because `value` is a Sendable stored property of a
    // value type (SE-0434), so no isolated state is touched.
    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    /// Digits after the point. 0 (the default) for scores; 2 for race times.
    var decimals: Int = 0

    var body: some View {
        if decimals == 0 {
            Text("\(Int(value.rounded()))")
        } else {
            Text(String(format: "%.\(decimals)f", value))
        }
    }
}
