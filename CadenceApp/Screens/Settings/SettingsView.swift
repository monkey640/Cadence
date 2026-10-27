import SwiftUI
import SwiftData
import CadenceCore
#if canImport(UIKit)
import UIKit
#endif

/// Settings, rebuilt in the timing-board language: no stock `Form`. Sections are
/// mono `sectionLabel` headers over flat cards of lane-ruled rows, values set in
/// the app's own type — so Settings reads as the same product as Today.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme
    @Query private var profiles: [AthleteProfile]
    @Query private var adjustments: [PlanAdjustment]
    @State private var showResetPlanConfirm = false
    @State private var showResetAllConfirm = false
    @State private var healthRequested = false
    @State private var wearableDetected: Bool?
    @State private var morningEnabled = false
    @State private var morningTime = Date()
    @State private var nudgesEnabled = false
    @State private var personalizationEnabled = false
    @State private var exportURL: URL?

    private let health: HealthDataProviding = HealthKitService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if let profile = profiles.first {
                        profileSection(profile)
                        planSection(profile)
                    }
                    appearanceSection
                    morningSection
                    if let profile = profiles.first { personalizationSection(profile) }
                    healthSection
                    dataSection
                    disclaimerSection
                    aboutSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cadenceBackground()
            .navigationTitle("Settings")
            .onAppear {
                morningEnabled = MorningNotificationService.shared.isEnabled
                morningTime = Calendar.current.date(
                    bySettingHour: MorningNotificationService.shared.hour,
                    minute: MorningNotificationService.shared.minute, second: 0, of: .now) ?? .now
                personalizationEnabled = PersonalizationGate.isEnabled
                nudgesEnabled = MorningNotificationService.shared.contextualEnabled
            }
            .task {
                let hrv = (try? await health.dailyHRV(days: 7)) ?? []
                wearableDetected = !hrv.isEmpty
            }
            .sheet(isPresented: Binding(
                get: { exportURL != nil },
                set: { if !$0 { exportURL = nil } })
            ) {
                if let url = exportURL { CSVShareSheet(url: url) }
            }
        }
        .preferredColorScheme(Theme.scheme)
    }

    // MARK: - Reusable building blocks

    /// A mono section label over a flat card of lane-ruled rows.
    private func section<Content: View>(_ label: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).sectionLabel()
            VStack(spacing: 0) { content() }
                .cadenceCard(padding: 0)
        }
    }

    /// One row: title left, arbitrary trailing control right.
    private func row<Trailing: View>(_ title: String, first: Bool = false,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(spacing: 0) {
            if !first { LaneLine() }
            HStack(spacing: 12) {
                Text(title).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 12)
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    /// A full-width tappable action row (brand, or red when destructive).
    private func actionRow(_ title: String, first: Bool = false,
                           destructive: Bool = false, disabled: Bool = false,
                           action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            if !first { LaneLine() }
            Button(action: action) {
                HStack {
                    Text(title)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .foregroundStyle(disabled ? Theme.textSecondary
                                 : (destructive ? Theme.backOff : Theme.brand))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
    }

    // MARK: - Profile

    private func profileSection(_ profile: AthleteProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Athlete").sectionLabel()
            VStack(spacing: 0) {
                row("First name", first: true) {
                    TextField("Name", text: Binding(
                        get: { profile.firstName },
                        set: { profile.firstName = $0; save() }))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 150)
                }
                row("Next meet") {
                    Toggle("", isOn: Binding(
                        get: { profile.meetDate != nil },
                        set: { on in
                            profile.meetDate = on
                                ? Calendar.current.date(byAdding: .weekOfYear, value: 6, to: .now)
                                : nil
                            save()
                        }))
                        .labelsHidden().tint(Theme.brand)
                }
                if profile.meetDate != nil {
                    row("Meet date") {
                        DatePicker("", selection: Binding(
                            get: { profile.meetDate ?? .now },
                            set: { profile.meetDate = Calendar.current.startOfDay(for: $0); save() }),
                            displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                row("Event") {
                    Picker("", selection: Binding(
                        get: { profile.event },
                        set: { profile.event = $0; save() })) {
                        ForEach(PlanLibraryLoader.selectableEvents(including: profile.event),
                                id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(Theme.brand)
                }
                row("Goal time") {
                    TextField("—", text: Binding(
                        get: { profile.goalTimeSeconds.map { String($0) } ?? "" },
                        set: { profile.goalTimeSeconds = Double($0.trimmingCharacters(in: .whitespaces)); save() }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 90)
                }
                row("Training days / week") {
                    HStack(spacing: 12) {
                        Text("\(profile.weeklyTrainingDays)")
                            .font(.timingBoard(17, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Stepper("", value: Binding(
                            get: { profile.weeklyTrainingDays },
                            set: { profile.weeklyTrainingDays = $0; save() }), in: 1...7)
                            .labelsHidden()
                    }
                }
                row("Experience") {
                    Picker("", selection: Binding(
                        get: { profile.experienceLevel },
                        set: { profile.experienceRaw = $0.rawValue; save() })) {
                        ForEach(ExperienceLevel.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(Theme.brand)
                }
            }
            .cadenceCard(padding: 0)
        }
    }

    // MARK: - Plan

    @ViewBuilder
    private func planSection(_ profile: AthleteProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan").sectionLabel()
            VStack(spacing: 0) {
                if let template = PlanLibraryLoader.template(for: profile.event) {
                    row("Plan", first: true) {
                        valueText("\(template.event) · \(template.durationWeeks) weeks")
                    }
                    if let start = profile.planStartDate {
                        row("Started") { valueText(start.formatted(.dateTime.month().day().year())) }
                    }
                    if let adjustment = adjustments.first(where: { $0.event == profile.event.rawValue }) {
                        actionRow("Undo personalization — back to the vetted plan", destructive: true) {
                            context.delete(adjustment); save()
                        }
                    }
                    actionRow("Restart plan from today") { showResetPlanConfirm = true }
                        .confirmationDialog(
                            "Restart from week 1, today?",
                            isPresented: $showResetPlanConfirm, titleVisibility: .visible
                        ) {
                            Button("Restart plan", role: .destructive) {
                                profile.planStartDate = Calendar.current.startOfDay(for: .now)
                                for adj in adjustments where adj.event == profile.event.rawValue {
                                    context.delete(adj)
                                }
                                save()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Today becomes week 1, day 1. Your logged sessions, PRs and readiness history stay; any applied personalization for \(profile.event.rawValue) is cleared.")
                        }
                } else {
                    row("Plan", first: true) { valueText("Rotating by day") }
                }
            }
            .cadenceCard(padding: 0)

            if PlanLibraryLoader.template(for: profile.event) == nil {
                footnote("No structured plan for \(profile.event.rawValue) yet — sessions rotate by day until one ships.")
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        section("Appearance") {
            NavigationLink { SchemePickerView() } label: {
                HStack(spacing: 12) {
                    Text("Color scheme").foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Circle().fill(theme.scheme.palette.brand).frame(width: 14, height: 14)
                    Text(theme.scheme.name).foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Morning notification

    private var morningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Morning check-in").sectionLabel()
            VStack(spacing: 0) {
                row("Daily readiness notification", first: true) {
                    Toggle("", isOn: Binding(
                        get: { morningEnabled },
                        set: { on in morningEnabled = on; Task { await MorningNotificationService.shared.setEnabled(on) } }))
                        .labelsHidden().tint(Theme.brand)
                }
                if morningEnabled {
                    row("Time") {
                        DatePicker("", selection: Binding(
                            get: { morningTime },
                            set: { t in
                                morningTime = t
                                let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                                MorningNotificationService.shared.setTime(hour: c.hour ?? 7, minute: c.minute ?? 0)
                            }), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
            }
            .cadenceCard(padding: 0)
            footnote("One notification a day with today's verdict, at a moment iOS picks near your chosen time. Check in before \(TodayViewModel.checkInCutoffLabel) to scale the day's session to your recovery — after that, the plan shows at full volume.")

            VStack(spacing: 0) {
                row("Smart nudges", first: true) {
                    Toggle("", isOn: Binding(
                        get: { nudgesEnabled },
                        set: { on in
                            nudgesEnabled = on
                            Task { await MorningNotificationService.shared.setContextualEnabled(on, context: context) }
                        }))
                        .labelsHidden().tint(Theme.brand)
                }
            }
            .cadenceCard(padding: 0)
            footnote("Optional evening cues, all on-device: wind down the night before a session, a nudge if a long streak is about to break, and a daily countdown in race week.")
        }
    }

    // MARK: - Personalization (draft / testers) — only for events that support it

    @ViewBuilder
    private func personalizationSection(_ profile: AthleteProfile) -> some View {
        if PersonalizationGate.ranges?.profile(for: profile.event.rawValue) != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Experimental").sectionLabel()
                VStack(spacing: 0) {
                    row("Draft plan personalization", first: true) {
                        Toggle("", isOn: Binding(
                            get: { personalizationEnabled },
                            set: { personalizationEnabled = $0; PersonalizationGate.isEnabled = $0 }))
                            .labelsHidden().tint(Theme.brand)
                    }
                }
                .cadenceCard(padding: 0)
                footnote("DRAFT — for testers. Lets Cadence suggest small, bounded tweaks to your plan from patterns in your logged sessions, always asking first. Not coach-validated yet, and only for 100m / 200m / 400m.")
            }
        }
    }

    // MARK: - Health

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apple Health").sectionLabel()
            VStack(spacing: 0) {
                if let wearableDetected {
                    row("Wearable", first: true) {
                        Label(wearableDetected ? "Connected" : "Not detected",
                              systemImage: wearableDetected ? "applewatch" : "iphone")
                            .font(.subheadline)
                            .foregroundStyle(wearableDetected ? Theme.push : Theme.textSecondary)
                    }
                    actionRow(healthRequested ? "Apple Health requested" : "Connect Apple Health",
                              disabled: healthRequested) {
                        Task { try? await health.requestAuthorization(); healthRequested = true }
                    }
                } else {
                    actionRow(healthRequested ? "Apple Health requested" : "Connect Apple Health",
                              first: true, disabled: healthRequested) {
                        Task { try? await health.requestAuthorization(); healthRequested = true }
                    }
                }
                actionRow("Manage access in Settings", action: openSystemSettings)
            }
            .cadenceCard(padding: 0)
            footnote(wearableDetected == false
                 ? "No watch data found — phone-only mode works fully: check-in, tap test and jump test power your score. Cadence reads everything on-device."
                 : "Cadence reads HRV, sleep, and resting heart rate on-device. iOS controls read access — use “Manage access” to change it in the Health app’s privacy settings.")
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data").sectionLabel()
            VStack(spacing: 0) {
                actionRow("Export history as CSV", first: true) {
                    exportURL = CSVExporter.export(context: context)
                }
                actionRow("Reset all data", destructive: true) { showResetAllConfirm = true }
                    .confirmationDialog(
                        "Delete every session, check-in, readiness score and PR on this device? This can't be undone.",
                        isPresented: $showResetAllConfirm, titleVisibility: .visible
                    ) {
                        Button("Delete everything", role: .destructive) { resetAllData() }
                        Button("Cancel", role: .cancel) {}
                    }
            }
            .cadenceCard(padding: 0)
            footnote("The CSV contains your sessions, sets and readiness history — the same data shown in the app, nothing else.")
        }
    }

    private func resetAllData() {
        try? context.delete(model: TrainingSession.self)
        try? context.delete(model: SessionSet.self)
        try? context.delete(model: DailyReadiness.self)
        try? context.delete(model: CheckIn.self)
        try? context.delete(model: PersonalRecord.self)
        try? context.delete(model: PlanAdjustment.self)
        try? context.delete(model: AthleteProfile.self)   // returns to onboarding
        try? context.save()
        UserDefaults.standard.removeObject(forKey: "streak.freeze.bridgedDays")
        UserDefaults.standard.removeObject(forKey: "today.reveal.lastDayOrdinal")
    }

    // MARK: - Disclaimer & About

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Important").sectionLabel()
            VStack(alignment: .leading, spacing: 10) {
                Text(Disclaimer.full)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if PlanLibraryLoader.shared?.meta.isDraft == true {
                    Text("Training plans are a coach-review draft — a starting structure, not coaching advice. Have a qualified coach individualize before following them.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .cadenceCard(padding: 0)
        }
    }

    private var aboutSection: some View {
        section("About") {
            row("Version", first: true) { valueText(appVersion) }
            row("Data") { valueText("Stored only on this device") }
        }
    }

    // MARK: - Helpers

    private func save() { try? context.save() }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
