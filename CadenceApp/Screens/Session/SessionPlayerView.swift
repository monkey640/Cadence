import SwiftUI
import SwiftData
import UIKit
import CadenceCore

/// The full-screen session player — the retention core. Guides every rep with
/// a rest timer, keeps the screen awake track-side, persists continuously, and
/// resumes exactly where it left off.
struct SessionPlayerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    let firstName: String
    @State private var model: SessionPlayerModel
    @State private var showModifySheet = false
    @State private var confirmFinish = false

    init(session: TrainingSession, displayBlocks: [TodayViewModel.DisplayBlock], firstName: String) {
        self.firstName = firstName
        _model = State(initialValue: SessionPlayerModel(session: session, displayBlocks: displayBlocks))
    }

    var body: some View {
        Group {
            if model.phase == .finished {
                SessionSummaryView(session: model.session, firstName: firstName) { dismiss() }
            } else {
                player
            }
        }
        .cadenceBackground()
        .preferredColorScheme(Theme.scheme)
        .onAppear {
            model.start(context: context)
            UIApplication.shared.isIdleTimerDisabled = true   // track-side: never sleep mid-session
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.suspend(context: context)
        }
    }

    // MARK: - Player

    private var player: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 12)

            if model.isPaused {
                pausedBanner
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            if model.phase == .resting {
                restMode   // full-screen, room-readable countdown
            } else {
                GeometryReader { geo in
                    ScrollView {
                        // Flat registers ruled by lane lines — no card stack, matching
                        // Today. A short session no longer strands half the screen:
                        // the content fills the height and Finish sits at the
                        // bottom, under the thumb. Long sessions scroll as before.
                        VStack(alignment: .leading, spacing: 0) {
                            currentExerciseRegister
                            LaneLine().padding(.vertical, 18)
                            exerciseListRegister
                            Spacer(minLength: 18)
                            LaneLine().padding(.bottom, 18)
                            finishArea
                        }
                        .padding(20)
                        .frame(width: geo.size.width)
                        .frame(minHeight: geo.size.height, alignment: .top)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
    }

    /// Recovery days read calmer: an amber accent instead of the back-off red, so
    /// an easy day doesn't shout. Training days keep their verdict colour.
    private var accent: Color {
        model.session.isRecovery ? Theme.hold : model.session.verdict.color
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()   // progress is already persisted; Today resumes it
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.card)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close — progress is saved")

            VStack(alignment: .leading, spacing: 1) {
                Text(model.session.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if model.session.hadCheckIn {
                    HStack(spacing: 6) {
                        Text("\(Int(model.session.readinessScore.rounded()))")
                            .font(.caption.weight(.bold)).monospacedDigit()
                            .foregroundStyle(model.session.verdict.color)
                        Text(model.session.verdict.badgeText)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(model.session.verdict.color)
                    }
                }
            }

            Spacer()

            Text(elapsedText)
                .font(.timingBoard(22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityLabel("Elapsed \(elapsedText)")

            Button {
                model.isPaused ? model.resume() : model.pause(context: context)
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Theme.card)
                    .clipShape(Circle())
            }
            .accessibilityLabel(model.isPaused ? "Resume" : "Pause")
        }
    }

    private var pausedBanner: some View {
        Label("Paused — the clock is stopped.", systemImage: "pause.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.hold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Current exercise

    @ViewBuilder private var currentExerciseRegister: some View {
        if let set = model.currentSet {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.session.isRecovery ? "Recovery" : "Now").sectionLabel()

                VStack(alignment: .leading, spacing: 4) {
                    Text(set.name)
                        .font(.displayBlack(28))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    let target = targetLine(set)
                    if !target.isEmpty {
                        Text(target)
                            .font(.timingBoard(20, weight: .bold))
                            .foregroundStyle(accent)
                    }

                    if let scalingNote {
                        Text(scalingNote)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let target = model.info?.target {
                        Text("Target: \(target)")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if model.session.isRecovery, let note = model.info?.note {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }

                setDots(set)
                logButtons(set)
                howTo
            }
        }
    }

    // MARK: - Full-screen rest

    /// Whole seconds left in the rest, rounded up so "0" only shows at the end.
    private var restSeconds: Int { Int(model.restRemaining.rounded(.up)) }

    /// Timing-board clock: "1:30", "0:45", "12:00". Matches the Lock Screen and
    /// Dynamic Island countdown, which the system always renders as m:ss.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func spoken(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let (m, r) = (s / 60, s % 60)
        switch (m, r) {
        case (0, _): return "\(r) seconds"
        case (_, 0): return m == 1 ? "1 minute" : "\(m) minutes"
        default: return "\(m) minute\(m == 1 ? "" : "s") \(r) seconds"
        }
    }

    /// Rest takes over the whole screen with a colossal, room-readable countdown
    /// (readable from a gym bag three metres away) and a draining lane bar — lanes
    /// over rings, per the design language. Calm amber, never the verdict red.
    private var restMode: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Rest").sectionLabel()
            Text(Self.clock(restSeconds))
                .font(.timingBoard(96))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: restSeconds)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("Rest: \(Self.spoken(restSeconds)) left")

            restLaneBar
                .padding(.top, 20)
                .padding(.bottom, 8)

            if let next = model.currentSet?.name {
                Text("Next · \(next)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 12) {
                restPill("+15s") { model.extendRest() }
                restPill("Skip rest") { model.skipRest() }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 20)
    }

    private var restLaneBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceSecondary).frame(height: 8)
                // Amber means "wait" — the same as the Lock Screen and Dynamic
                // Island countdown. The session colour is saved for "go".
                Capsule().fill(Theme.hold)
                    .frame(width: geo.size.width * CGFloat(model.restTotal > 0 ? model.restRemaining / model.restTotal : 0),
                           height: 8)
                    .animation(.linear(duration: 0.25), value: model.restRemaining)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private func restPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold)).monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(Theme.surfaceSecondary)
            .clipShape(Capsule())
    }

    private func targetLine(_ set: SessionSet) -> String {
        if let distance = set.distanceMeters {
            return "\(set.plannedSets) × \(Int(distance))m"
        }
        return model.session.isRecovery ? "" : "\(set.plannedSets) sets"
    }

    /// "Scaled from 8 reps — Hold day (75%)" — only when scaling changed the number.
    private var scalingNote: String? {
        guard model.session.wasAdjusted,
              let unscaled = model.info?.unscaledReps,
              let scaled = model.info?.scaledReps,
              unscaled != scaled else { return nil }
        let percent = Int((model.session.volumeMultiplier * 100).rounded())
        return "Scaled from \(unscaled) reps — \(model.session.verdict.displayName) day (\(percent)%)"
    }

    /// Set progress as a timing-board readout: a big count, and one lane per set
    /// that fills as it's logged. Logging is routine, not an achievement, so the
    /// count ticks with a numeric transition rather than a celebration.
    private func setDots(_ set: SessionSet) -> some View {
        let planned = max(set.plannedSets, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(set.completedSets)")
                    .font(.timingBoard(56))
                    .foregroundStyle(set.completedSets > 0 ? accent : Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("/ \(planned)")
                    .font(.timingBoard(24))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(set.completedSets >= planned ? "block done" : "sets")
                    .sectionLabel()
            }
            HStack(spacing: 6) {
                ForEach(0..<planned, id: \.self) { index in
                    Capsule()
                        .fill(index < set.completedSets ? accent : Theme.surfaceSecondary)
                        .frame(height: 6)
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: set.completedSets)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(set.completedSets) of \(set.plannedSets) sets done")
    }

    private func logButtons(_ set: SessionSet) -> some View {
        VStack(spacing: 10) {
            Button(model.session.isRecovery ? "Done — next" : "Log set") {
                model.logSet(context: context)
            }
            .buttonStyle(PrimaryButtonStyle(tint: accent))
            .disabled(model.isPaused || set.completedSets >= set.plannedSets)

            Button("Modify this set") { showModifySheet = true }
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .sheet(isPresented: $showModifySheet) {
            if let current = model.currentSet {
                SetModifySheet(set: current)
                    .presentationDetents([.medium])
            }
        }
    }

    @ViewBuilder private var howTo: some View {
        if let entry = GlossaryStore.entry(for: model.currentSet?.movementID) {
            DisclosureGroup {
                GlossaryDetail(entry: entry)
                    .padding(.top, 8)
            } label: {
                Label("How to do it", systemImage: "book")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.textSecondary)
        }
    }

    // MARK: - Exercise list (a start list, lane-ruled — no card)

    private var exerciseListRegister: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Session").sectionLabel().padding(.bottom, 4)

            ForEach(Array(model.orderedSets.enumerated()), id: \.element.persistentModelID) { index, set in
                if index > 0 { LaneLine() }
                Button {
                    model.jump(to: index, context: context)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: set.completedSets >= set.plannedSets
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(set.completedSets >= set.plannedSets ? accent : Theme.textSecondary)
                        Text(set.name)
                            .font(.subheadline.weight(index == model.currentIndex ? .semibold : .regular))
                            .foregroundStyle(index == model.currentIndex ? Theme.textPrimary : Theme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(set.completedSets)/\(set.plannedSets)")
                            .font(.caption.weight(.medium)).monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                        if set.wasPR {
                            Image(systemName: "trophy.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.brand)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Finish

    private var finishArea: some View {
        VStack(spacing: 8) {
            Button(model.allDone ? "Finish session" : "Finish early") {
                if model.allDone {
                    model.finish(context: context)
                } else {
                    confirmFinish = true
                }
            }
            .buttonStyle(PrimaryButtonStyle(
                tint: model.allDone ? accent : Theme.surfaceSecondary))
        }
        .confirmationDialog("Some sets aren't logged yet.", isPresented: $confirmFinish,
                            titleVisibility: .visible) {
            Button("Finish with what I logged") { model.finish(context: context) }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var elapsedText: String {
        let total = Int(model.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Modify sheet

/// "Log what you actually did": completed reps, best time, and the endurance
/// fade marker — writes straight back to the persisted set.
struct SetModifySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var set: SessionSet
    /// Local editing buffer for the time field so partial input ("2.") doesn't
    /// fight a model-derived binding; committed to the model only when valid.
    @State private var timeString = ""

    /// Sane upper bound for a single logged rep, seconds (a long 400m + rest).
    private static let maxRepSeconds: Double = 600

    var body: some View {
        NavigationStack {
            Form {
                Section(set.name) {
                    // Reps done can never exceed the planned count.
                    Stepper(value: completedBinding, in: 0...set.plannedSets) {
                        HStack {
                            Text("Reps done")
                            Spacer()
                            Text("\(set.completedSets)")
                                .monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                    }
                    // Lowering planned below reps-done pulls reps-done down with it.
                    Stepper(value: plannedBinding, in: 1...30) {
                        HStack {
                            Text("Planned")
                            Spacer()
                            Text("\(set.plannedSets)")
                                .monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                    }
                    HStack {
                        Text("Best time")
                        Spacer()
                        TextField("seconds", text: $timeString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .onChange(of: timeString) { _, new in commitTime(new) }
                    }
                }

                if isEnduranceBlock {
                    Section("How did it finish?") {
                        Picker("Finish", selection: fadeSelection) {
                            Text("Held pace").tag(FadeMarker?.some(.held))
                            Text("Faded late").tag(FadeMarker?.some(.faded))
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Modify set")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { timeString = set.bestTimeSeconds.map(Self.formatTime) ?? "" }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(Theme.scheme)
    }

    private var isEnduranceBlock: Bool {
        self.set.qualityRaw.flatMap(Quality.init(rawValue:))?.isEndurance == true
    }

    /// Reps done, clamped to [0, planned].
    private var completedBinding: Binding<Int> {
        Binding(get: { set.completedSets },
                set: { set.completedSets = min(max(0, $0), set.plannedSets) })
    }

    /// Planned reps [1, 30]; lowering it never leaves reps-done stranded above.
    private var plannedBinding: Binding<Int> {
        Binding(get: { set.plannedSets },
                set: { new in
                    let clamped = min(max(1, new), 30)
                    set.plannedSets = clamped
                    if set.completedSets > clamped { set.completedSets = clamped }
                })
    }

    /// Sanitize the time field and commit only a valid, in-range value; keep the
    /// field showing what was typed so partial entries aren't clobbered mid-type.
    private func commitTime(_ raw: String) {
        var cleaned = "", seenDot = false
        for ch in raw where ch.isNumber || ch == "." {
            if ch == "." { if seenDot { continue }; seenDot = true }
            cleaned.append(ch)
        }
        if cleaned != raw { timeString = cleaned; return }   // re-enters onChange
        if cleaned.isEmpty { set.bestTimeSeconds = nil; return }
        if let v = Double(cleaned), v > 0, v <= Self.maxRepSeconds {
            set.bestTimeSeconds = v
        }
        // Out of range or unparseable-partial ("2."): leave the model untouched.
    }

    /// Compact seconds string (2.18 → "2.18", 6.0 → "6").
    private static func formatTime(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }

    private var fadeSelection: Binding<FadeMarker?> {
        Binding(get: { set.fadeMarker }, set: { set.fadeMarker = $0 })
    }
}
