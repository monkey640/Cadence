import SwiftUI
import SwiftData
import CadenceCore

/// Log completed sets and best times for a session, then mark it complete
/// (which runs PR detection).
struct SessionLogView: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: TrainingSession

    private var orderedSets: [SessionSet] { session.sets.sorted { $0.order < $1.order } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if session.hadCheckIn {
                    readinessSnapshot
                }

                ForEach(orderedSets) { set in
                    SetLogRow(set: set)
                }

                // One-tap session-level confounder flag (off by default).
                Toggle(isOn: $session.flaggedExternalStress) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ill or unusually stressed today?").font(.subheadline)
                        Text("Keeps a bad day from skewing your trends.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.accent)
                .padding(16)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(session.isComplete ? "Update log" : "Mark complete", action: markComplete)
                    .buttonStyle(PrimaryButtonStyle())

                if session.isComplete, let completedAt = session.completedAt {
                    Text("Logged \(completedAt.formatted(.dateTime.month().day().hour().minute()))")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(24)
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .cadenceBackground()
    }

    /// That morning's readiness, as it stood when the session was generated.
    private var readinessSnapshot: some View {
        HStack(spacing: 12) {
            Text("\(Int(session.readinessScore.rounded()))")
                .font(.timingBoard(30, weight: .bold))
                .foregroundStyle(session.verdict.color)
            VerdictBadge(verdict: session.verdict)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("THAT MORNING")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
                Text("Volume ×\(String(format: "%.2f", session.volumeMultiplier))")
                    .font(.caption.weight(.medium)).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .cadenceCard()
    }

    private func markComplete() {
        session.isComplete = true
        session.completedAt = .now
        PersonalRecordTracker.apply(to: session, context: context)
    }
}

/// One editable block: completed-set stepper + best-time field.
private struct SetLogRow: View {
    @Bindable var set: SessionSet

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(set.name).font(.headline)
                if set.wasPR {
                    Label("PR", systemImage: "trophy.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                }
            }
            if let cue = GlossaryStore.entry(for: set.movementID)?.short {
                Text(cue).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }

            Stepper(value: $set.completedSets, in: 0...set.plannedSets) {
                Text("Completed \(set.completedSets) / \(set.plannedSets)")
                    .monospacedDigit()
            }

            HStack {
                Text("Best time").foregroundStyle(.secondary)
                Spacer()
                TextField("seconds", text: timeText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }

            // Endurance blocks only: the soft "faded late?" marker.
            if isEnduranceBlock {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How did it finish?").font(.caption).foregroundStyle(.secondary)
                    Picker("Finish", selection: fadeSelection) {
                        Text("Held pace").tag(FadeMarker?.some(.held))
                        Text("Faded late").tag(FadeMarker?.some(.faded))
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Show the fade marker only for endurance qualities (meaningless on
    /// acceleration / max-velocity).
    private var isEnduranceBlock: Bool {
        self.set.qualityRaw.flatMap(Quality.init(rawValue:))?.isEndurance == true
    }

    /// String⇄Double? bridge writing straight back to the model.
    private var timeText: Binding<String> {
        Binding(
            get: { set.bestTimeSeconds.map { String($0) } ?? "" },
            set: { set.bestTimeSeconds = Double($0.trimmingCharacters(in: .whitespaces)) })
    }

    private var fadeSelection: Binding<FadeMarker?> {
        Binding(get: { set.fadeMarker }, set: { set.fadeMarker = $0 })
    }
}
