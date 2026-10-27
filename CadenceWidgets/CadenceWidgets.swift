import WidgetKit
import SwiftUI

/// The Home Screen readiness widget — the app's most-seen surface.
///
/// Reads today's score/verdict from the shared app group that `WidgetBridge`
/// publishes to (keys mirrored below; keep the two in sync). Before the morning
/// check-in it shows the "Check in" prompt instead of a stale score.
///
/// NOTE: widget extensions can't see the app's `Theme`, and the athlete's chosen
/// colour scheme lives in the app's own defaults — so the widget renders the
/// default "track at night" palette. Verdict colour is always paired with the
/// verdict word, so colour is never the only signal.
/// Shared by the readiness widget and the rest-timer Live Activity.
enum WidgetTheme {
    static let background = Color(red: 0.047, green: 0.043, blue: 0.035)  // #0C0B09
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.58, green: 0.565, blue: 0.541) // #94908A
    static let brand = Color(red: 0.769, green: 0.278, blue: 0.169)        // #C4472B
    static let push = Color(red: 0.184, green: 0.749, blue: 0.443)         // #2FBF71
    static let hold = Color(red: 0.910, green: 0.631, blue: 0.227)         // #E8A13A
    static let backOff = Color(red: 0.851, green: 0.310, blue: 0.188)      // #D94F30

    static func color(forVerdict raw: String) -> Color {
        switch raw {
        case "push": return push
        case "backOff": return backOff
        default: return hold
        }
    }
    static func word(forVerdict raw: String) -> String {
        switch raw {
        case "push": return "PUSH"
        case "backOff": return "BACK OFF"
        default: return "HOLD"
        }
    }
}

/// Mirrors `WidgetBridge` in the app target (separate targets can't share it
/// without extra coupling; the contract is four keys in one app group).
private enum SharedStore {
    static let appGroupID = "group.net.adnanahmad.Cadence"

    static func read(now: Date = .now) -> ReadinessEntry {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return ReadinessEntry(date: now, checkedIn: false, score: nil, verdictRaw: "hold")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)
        // A payload from an earlier day is stale — show the check-in prompt.
        let isToday = defaults.string(forKey: "widget.day") == today
        let checkedIn = isToday && defaults.bool(forKey: "widget.checkedIn")
        let hasVolume = defaults.object(forKey: "widget.volume") != nil
        return ReadinessEntry(
            date: now,
            checkedIn: checkedIn,
            score: checkedIn ? defaults.double(forKey: "widget.score") : nil,
            volume: checkedIn && hasVolume ? defaults.double(forKey: "widget.volume") : nil,
            verdictRaw: defaults.string(forKey: "widget.verdict") ?? "hold")
    }
}

struct ReadinessEntry: TimelineEntry {
    let date: Date
    let checkedIn: Bool
    let score: Double?
    /// Today's volume, % of plan. Nil for a payload written before the app
    /// published it — the widget then falls back to the readiness score.
    var volume: Double? = nil
    let verdictRaw: String
}

struct ReadinessProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadinessEntry {
        ReadinessEntry(date: .now, checkedIn: true, score: 88, volume: 100, verdictRaw: "push")
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadinessEntry) -> Void) {
        completion(SharedStore.read())
    }

    /// One entry now, and a refresh at midnight so the widget flips back to the
    /// check-in prompt for the new day. The app also pokes WidgetKit on publish.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadinessEntry>) -> Void) {
        let entry = SharedStore.read()
        let midnight = Calendar.current.nextDate(
            after: .now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct CadenceWidgetsEntryView: View {
    var entry: ReadinessEntry

    var body: some View {
        if entry.checkedIn, let score = entry.score {
            scoreView(score)
        } else {
            promptView
        }
    }

    /// Leads with today's volume — the same number as Today and the check-in
    /// reveal — so the Home Screen and the app never disagree at a glance.
    private func scoreView(_ score: Double) -> some View {
        let color = WidgetTheme.color(forVerdict: entry.verdictRaw)
        let word = WidgetTheme.word(forVerdict: entry.verdictRaw)
        return VStack(alignment: .leading, spacing: 0) {
            Text(entry.volume != nil ? "TODAY" : "READINESS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(WidgetTheme.textSecondary)
            Spacer(minLength: 2)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int((entry.volume ?? score).rounded()))")
                    .font(.system(size: 50, weight: .black).monospacedDigit())
                    .tracking(-1.5)
                if entry.volume != nil {
                    Text("%")
                        .font(.system(size: 20, weight: .black))
                }
            }
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(word)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(color)
            if entry.volume != nil {
                Text("Readiness \(Int(score.rounded()))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(WidgetTheme.textSecondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel(entry.volume.map {
            "Today: \(Int($0.rounded())) percent of plan, \(word). Readiness \(Int(score.rounded()))."
        } ?? "Readiness \(Int(score.rounded())) out of 100, \(word)")
    }

    private var promptView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 20))
                .foregroundStyle(WidgetTheme.brand)
            Spacer(minLength: 2)
            Text("Check in")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(WidgetTheme.textPrimary)
            Text("60 seconds to today's verdict")
                .font(.system(size: 11))
                .foregroundStyle(WidgetTheme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel("Check in — 60 seconds to today's verdict")
    }
}

struct CadenceWidgets: Widget {
    let kind: String = "CadenceWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReadinessProvider()) { entry in
            CadenceWidgetsEntryView(entry: entry)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("How much of today's session to run, and the verdict — or a nudge to check in.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    CadenceWidgets()
} timeline: {
    ReadinessEntry(date: .now, checkedIn: true, score: 88, verdictRaw: "push")
    ReadinessEntry(date: .now, checkedIn: true, score: 61, verdictRaw: "backOff")
    ReadinessEntry(date: .now, checkedIn: false, score: nil, verdictRaw: "hold")
}
