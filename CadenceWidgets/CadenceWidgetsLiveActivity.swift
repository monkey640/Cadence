import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen + Dynamic Island rendering for the rest timer, so the athlete
/// never has to unlock mid-workout. Driven by `RestTimerActivityController` in
/// the app; `RestTimerAttributes` is shared by both targets.
///
/// Everything that moves — the countdown and the draining lane bar — is drawn by
/// the system from `startDate`/`endDate`, so it keeps going while the app is
/// suspended. When rest runs out the activity goes stale (its stale date is the
/// end date) and flips to "Go" without the app having to wake up.
///
/// Colour carries the state, matching the in-app rest screen: calm amber while
/// the athlete waits, the session's verdict colour once it's time to go.
struct CadenceWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            LockScreenRest(context: context)
                .activityBackgroundTint(WidgetTheme.background)
                .activitySystemActionForegroundColor(WidgetTheme.textPrimary)
        } dynamicIsland: { context in
            let accent = restColor(context)
            let window = RestWindow(context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.isStale ? "REST DONE" : "REST")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(WidgetTheme.textSecondary)
                        Text(context.state.blockName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WidgetTheme.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if context.isStale {
                            Text("GO")
                        } else {
                            Text(timerInterval: window.range, countsDown: true)
                        }
                    }
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 96, alignment: .trailing)
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        LaneBar(window: window, accent: accent, done: context.isStale)
                        Text(setLine(context))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(WidgetTheme.textSecondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            } compactLeading: {
                RestRing(window: window, accent: accent, done: context.isStale)
            } compactTrailing: {
                Group {
                    if context.isStale {
                        Text("GO")
                    } else {
                        Text(timerInterval: window.range, countsDown: true)
                    }
                }
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(accent)
                .frame(maxWidth: 46)
            } minimal: {
                RestRing(window: window, accent: accent, done: context.isStale)
            }
            .keylineTint(accent)
        }
    }

    private func setLine(_ context: ActivityViewContext<RestTimerAttributes>) -> String {
        let line = nextSetLine(context.state)
        return context.isStale ? "\(line) · you're up" : line
    }
}

/// Amber while resting; the session's verdict colour once rest is done.
private func restColor(_ context: ActivityViewContext<RestTimerAttributes>) -> Color {
    context.isStale ? WidgetTheme.color(forVerdict: context.attributes.verdictRaw) : WidgetTheme.hold
}

/// "Next · set 3 of 5". Mid-rest a bare "Set 2 of 5" reads as either the set
/// just finished or the one coming; naming the next one removes the doubt and
/// matches the rest-end notification.
private func nextSetLine(_ state: RestTimerAttributes.ContentState) -> String {
    "Next · set \(min(state.setsDone + 1, state.setsTotal)) of \(state.setsTotal)"
}

/// The rest interval, guaranteed well-formed. `start...end` with end before
/// start traps at runtime, which in an extension means a blank Live Activity —
/// so the upper bound is clamped rather than trusted.
private struct RestWindow {
    let range: ClosedRange<Date>

    init(_ state: RestTimerAttributes.ContentState) {
        range = state.startDate...max(state.startDate, state.endDate)
    }
}

private struct LockScreenRest: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        let accent = restColor(context)
        let window = RestWindow(context.state)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.isStale ? "REST DONE" : "REST")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(WidgetTheme.textSecondary)
                        .lineLimit(1)
                    Text(context.state.blockName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(WidgetTheme.textPrimary)
                        .lineLimit(1)
                    Text(nextSetLine(context.state))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
                Spacer(minLength: 8)
                Group {
                    if context.isStale {
                        Text("GO")
                    } else {
                        Text(timerInterval: window.range, countsDown: true)
                    }
                }
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(context.isStale ? accent : WidgetTheme.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            LaneBar(window: window, accent: accent, done: context.isStale)
        }
        .padding(16)
    }
}

/// The lane bar from the in-app rest screen: drains left to right as rest runs
/// out. `ProgressView(timerInterval:)` is animated by the system itself.
private struct LaneBar: View {
    let window: RestWindow
    let accent: Color
    let done: Bool

    var body: some View {
        if done {
            Capsule().fill(accent).frame(height: 4)
        } else {
            ProgressView(timerInterval: window.range, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(accent)
        }
    }
}

/// Compact / minimal Dynamic Island: the same countdown as a draining ring.
private struct RestRing: View {
    let window: RestWindow
    let accent: Color
    let done: Bool

    var body: some View {
        if done {
            Image(systemName: "figure.run")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
        } else {
            ProgressView(timerInterval: window.range, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(accent)
            .frame(width: 18, height: 18)
        }
    }
}
