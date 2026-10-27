import SwiftUI
import SwiftData
import CadenceCore

/// One-decision-per-screen onboarding (<2 min). On finish it creates the single
/// `AthleteProfile`, seeds an optional starting PR, and flips to the main tabs.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    @State private var step: Step = .welcome
    @State private var firstName = ""
    @State private var event: Event = .sprint100
    @State private var goalTimeText = ""
    @State private var prTimeText = ""
    @State private var selectedWeekdays: Set<Int> = [0, 2, 4]   // Mon/Wed/Fri
    @State private var experience: ExperienceLevel = .developing
    @State private var focus: FocusArea = .topSpeed
    @State private var hasMeet = false
    @State private var meetDate = Calendar.current.date(byAdding: .weekOfYear, value: 6, to: .now) ?? .now
    @State private var healthRequested = false
    @State private var wearableDetected: Bool?
    @State private var disclaimerAccepted = false

    private let health: HealthDataProviding = HealthKitService()
    private static let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    enum Step: Int, CaseIterable {
        case welcome, name, event, days, experience, focus, pr, meet, health, disclaimer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progressBar
            // The scroll view is greedy vertically, so centre the step's content
            // inside it (minHeight = the available height lets the spacers do the
            // centring). Taller steps — the disclaimer — exceed it and scroll as usual.
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 16)
                        content
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                        Spacer(minLength: 16)
                    }
                    // Pin the width too: inside a GeometryReader the scroll view
                    // would otherwise propose an unbounded width and headlines
                    // would truncate instead of wrapping.
                    .frame(width: geo.size.width, alignment: .leading)
                    .frame(minHeight: geo.size.height, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            footer
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cadenceBackground()
        .preferredColorScheme(Theme.scheme)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: - Chrome

    private var progressBar: some View {
        GeometryReader { geo in
            let fraction = CGFloat(step.rawValue + 1) / CGFloat(Step.allCases.count)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.laneLine).frame(height: 3)
                Capsule().fill(Theme.brand).frame(width: geo.size.width * fraction, height: 3)
            }
        }
        .frame(height: 3)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            headline("Train when your body is ready.",
                     "Cadence reads your recovery each morning and scales today's training to match. No guessing, nothing leaves your phone.")
            verdictBoard.padding(.top, 28)
        case .name:
            headline("What should we call you?", "First name only — it's for your Today screen and PR cards.")
            TextField("First name", text: $firstName)
                .font(.system(size: 34, weight: .bold))
                .textInputAutocapitalization(.words)
                .padding(.top, 16)
        case .event:
            headline("What's your event?", "Your 12-week plan is built for it.")
            Picker("Event", selection: $event) {
                ForEach(PlanLibraryLoader.plannedEvents, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.top, 24)
        case .days:
            headline("Which days do you train?", "Tap your usual days — the plan fits itself to them.")
            weekdayGrid.padding(.top, 16)
        case .experience:
            headline("How long have you trained sprints?",
                     "We'll set your starting load to match — you can change it anytime.")
            VStack(spacing: 8) {
                ForEach(ExperienceLevel.allCases, id: \.self) { level in
                    optionRow(level.label, selected: experience == level) { experience = level }
                }
            }
            .padding(.top, 16)
        case .focus:
            headline("What do you most want to improve?",
                     "We'll start your plan with a gentle emphasis here, then refine it from your real sessions.")
            VStack(spacing: 8) {
                ForEach(FocusArea.allCases, id: \.self) { area in
                    optionRow(area.label, selected: focus == area) { focus = area }
                }
            }
            .padding(.top, 16)
        case .pr:
            headline("Current \(event.rawValue) PR?",
                     "Optional — in seconds (e.g. 11.84). Beating it later triggers the PR card.")
            TextField("Seconds", text: $prTimeText)
                .keyboardType(.decimalPad)
                .font(.timingBoard(44))
                .padding(.top, 16)
        case .meet:
            headline("When's your next meet?",
                     "Optional. In the last week before it, Cadence switches to race mode — volume eases off and the countdown shows on Today.")
            Toggle("I have a meet coming up", isOn: $hasMeet)
                .tint(Theme.brand)
                .padding(.top, 16)
            if hasMeet {
                DatePicker("Meet date", selection: $meetDate,
                           in: Date.now..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.brand)
            }
        case .health:
            healthStep
        case .disclaimer:
            headline("One important thing", Disclaimer.full)
            Toggle(isOn: $disclaimerAccepted) {
                Text("I understand Cadence is not medical advice.").font(.subheadline)
            }
            .tint(Theme.brand)
            .padding(.top, 24)
        }
    }

    // MARK: - Welcome board

    /// The whole product in one glance, before any setup: the three verdicts and
    /// what each does to the day. Static on purpose — motion is saved for the
    /// first real reveal.
    private var verdictBoard: some View {
        VStack(spacing: 0) {
            boardRow(.push, figure: "100%", detail: "The full session")
            LaneLine()
            boardRow(.hold, figure: "80%", detail: "Trimmed to match")
            LaneLine()
            boardRow(.backOff, figure: "—", detail: "Recovery instead")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Push: the full session. Hold: trimmed to match, for example 80 percent. Back off: recovery instead.")
    }

    private func boardRow(_ verdict: Verdict, figure: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verdict.displayName.uppercased())
                .font(.timingBoard(15, weight: .bold))
                .foregroundStyle(verdict.color)
                .frame(width: 96, alignment: .leading)
            Text(figure)
                .font(.timingBoard(22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 64, alignment: .leading)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Days grid

    private var weekdayGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let selected = selectedWeekdays.contains(index)
                Button {
                    Haptics.tick()
                    if selected { selectedWeekdays.remove(index) }
                    else { selectedWeekdays.insert(index) }
                } label: {
                    Text(Self.weekdayLabels[index])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selected ? Theme.brand : Theme.card)
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: - Health step

    @ViewBuilder private var healthStep: some View {
        headline("Connect Apple Health",
                 "Everything stays on your phone — nothing is uploaded, ever.")
        VStack(alignment: .leading, spacing: 10) {
            signalRow("waveform.path.ecg", "HRV + resting heart rate", "how recovered your nervous system is")
            signalRow("bed.double.fill", "Sleep", "whether recovery had the time it needed")
            signalRow("figure.run", "Workouts", "your recent training load")
        }
        .padding(.top, 16)

        Button(healthRequested ? "Health connected" : "Connect Apple Health") {
            Task { await requestHealth() }
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.top, 20)
        .disabled(healthRequested)

        if let wearableDetected {
            Label(
                wearableDetected
                    ? "Great — your Apple Watch will power the full score."
                    : "No watch? No problem — we'll use your check-in and tap test.",
                systemImage: wearableDetected ? "applewatch" : "iphone")
                .font(.subheadline)
                .foregroundStyle(Theme.push)
                .padding(.top, 12)
        }
    }

    private func signalRow(_ icon: String, _ title: String, _ why: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Theme.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                Text(why).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Footer / flow

    private var footer: some View {
        Button(step == .disclaimer ? "Start training" : "Continue", action: advance)
            .buttonStyle(PrimaryButtonStyle(enabled: canAdvance))
            .disabled(!canAdvance)
            .padding(.top, 24)
    }

    private func headline(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.displayBlack(32))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func optionRow(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.brand : Theme.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var canAdvance: Bool {
        switch step {
        case .days: return !selectedWeekdays.isEmpty
        case .disclaimer: return disclaimerAccepted
        default: return true
        }
    }

    private func advance() {
        if step == .disclaimer { finish(); return }
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    private func requestHealth() async {
        try? await health.requestAuthorization()   // proceed regardless; data can be granted later
        healthRequested = true
        // Wearable detection: any HRV in the last week means a watch is feeding Health.
        let hrv = (try? await health.dailyHRV(days: 7)) ?? []
        wearableDetected = !hrv.isEmpty
    }

    private func finish() {
        let profile = AthleteProfile(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            meetDate: hasMeet ? Calendar.current.startOfDay(for: meetDate) : nil,
            event: event,
            goalTimeSeconds: Double(goalTimeText.trimmingCharacters(in: .whitespaces)),
            weeklyTrainingDays: max(1, selectedWeekdays.count),
            experienceLevel: experience,
            planStartDate: Calendar.current.startOfDay(for: .now),
            hasCompletedOnboarding: true,
            hasAcknowledgedDisclaimer: true)
        profile.trainingWeekdays = selectedWeekdays
        context.insert(profile)
        seedStartingPR()
        applyStartingEmphasis()
        try? context.save()
    }

    /// An entered PR becomes the stored record for the event distance, so the
    /// first faster time in a session triggers the real PR moment.
    private func seedStartingPR() {
        guard let seconds = Double(prTimeText.trimmingCharacters(in: .whitespaces)),
              seconds > 0 else { return }
        context.insert(PersonalRecord(
            key: event.rawValue, bestTimeSeconds: seconds, achievedOn: .now))
    }

    /// One-time bounded starting emphasis from the athlete's focus — within the
    /// coach bands + speed floor, stored as a (reversible) PlanAdjustment. No-op
    /// for events without an adjustment profile (Hurdles/Relay) or no room.
    private func applyStartingEmphasis() {
        guard let ranges = PersonalizationGate.ranges,
              let eventProfile = ranges.profile(for: event.rawValue),
              let quality = focus.quality(in: eventProfile) else { return }
        let deltas = OnboardingEmphasis.startingTrade(profile: eventProfile, focus: quality)
        guard !deltas.isEmpty else { return }

        let adjustment = PlanAdjustment(
            event: event.rawValue,
            deficiencyName: "onboarding_focus",
            reason: "Starting emphasis on \(quality.displayName) from your onboarding — we'll refine it from your real sessions.",
            deltas: Dictionary(uniqueKeysWithValues: deltas.map { ($0.key.rawValue, $0.value) }))
        context.insert(adjustment)
    }
}
