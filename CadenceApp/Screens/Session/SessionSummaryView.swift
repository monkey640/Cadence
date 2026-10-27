import SwiftUI
import CadenceCore

/// End-of-session summary: totals, PR celebration, and — on PR days only — the
/// shareable scoreboard card.
///
/// A PR is one of the two moments the app spends motion on (the other is the
/// daily reveal), so on a PR day the new time *is* the screen: a full-width
/// timing-board readout that counts down from the old record to the new one,
/// with confetti and a success haptic. Every other day stays quiet.
struct SessionSummaryView: View {
    let session: TrainingSession
    let firstName: String
    /// False when reopened later from Today: the PR shows at rest. The
    /// celebration belongs to the moment the session ends, once.
    var celebrates: Bool = true
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrate = false
    /// The time on the board. Starts at the old record and counts down to the
    /// new one — the PR literally happens on screen.
    @State private var shownTime: Double = 0

    private var orderedSets: [SessionSet] { session.sets.sorted { $0.order < $1.order } }
    private var prSets: [SessionSet] { orderedSets.filter(\.wasPR) }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let hero = heroPR {
                        prHero(hero).padding(.top, 28)
                    } else {
                        Text(session.isRecovery ? "Recovery logged." : "Session done.")
                            .font(.displayBlack(34))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.top, 32)
                    }

                    LaneLine().padding(.vertical, 22)
                    totalsCard
                    LaneLine().padding(.vertical, 22)

                    if !prSets.isEmpty {
                        prCard
                        LaneLine().padding(.vertical, 22)
                    }

                    exerciseRecap

                    Button("Done", action: onDone)
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 28)
                }
                .padding(20)
            }

            if celebrate { ConfettiView() }
        }
        .onAppear(perform: startCelebration)
    }

    // MARK: - PR hero

    /// The headline PR: the first PR block that has a timed distance.
    private var heroPR: SessionSet? {
        prSets.first { $0.bestTimeSeconds != nil && $0.distanceMeters != nil }
    }

    private func startCelebration() {
        guard let hero = heroPR, let time = hero.bestTimeSeconds else { return }
        guard celebrates else { shownTime = time; return }
        Haptics.success()
        celebrate = true
        guard !reduceMotion, let previous = hero.previousBestSeconds, previous > time else {
            shownTime = time
            return
        }
        shownTime = previous
        withAnimation(.easeOut(duration: 1.4).delay(0.35)) { shownTime = time }
    }

    private func prHero(_ set: SessionSet) -> some View {
        let time = set.bestTimeSeconds ?? 0
        let distance = Int(set.distanceMeters ?? 0)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                Text("New PR")
            }
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .textCase(.uppercase)
            .tracking(2)
            .foregroundStyle(Theme.brand)

            Text("\(distance)m")
                .font(.displayBlack(28))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 4)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                CountingText(value: shownTime == 0 ? time : shownTime, decimals: 2)
                    .font(.timingBoard(96))
                    .foregroundStyle(Theme.brand)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("s")
                    .font(.timingBoard(40))
                    .foregroundStyle(Theme.brand.opacity(0.8))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("New \(distance) metre personal record, \(String(format: "%.2f", time)) seconds")

            if let previous = set.previousBestSeconds, previous > time {
                HStack(spacing: 10) {
                    Text("was \(String(format: "%.2f", previous))")
                        .foregroundStyle(Theme.textSecondary)
                        .strikethrough(true, color: Theme.textSecondary.opacity(0.6))
                    Text("−\(String(format: "%.2f", previous - time))s")
                        .foregroundStyle(Theme.push)
                }
                .font(.timingBoard(18, weight: .bold))
            } else {
                Text("Your first \(distance)m on record")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Totals

    private var totalsCard: some View {
        let planned = orderedSets.reduce(0) { $0 + $1.plannedSets }
        let completed = orderedSets.reduce(0) { $0 + $1.completedSets }
        let meters = orderedSets.reduce(0.0) { sum, set in
            sum + (set.distanceMeters ?? 0) * Double(set.completedSets)
        }
        return HStack(spacing: 0) {
            summaryStat("\(completed)/\(planned)", session.isRecovery ? "items" : "reps")
            if meters > 0 {
                verticalLane
                summaryStat("\(Int(meters))m", "volume")
            }
            verticalLane
            summaryStat(durationText, "duration")
        }
    }

    private var verticalLane: some View {
        Rectangle().fill(Theme.laneLine).frame(width: 1, height: 44)
    }

    private func summaryStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.timingBoard(24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var durationText: String {
        let minutes = Int(session.activeSeconds) / 60
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: - PR celebration + share

    private var prCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prSets.count > 1 ? "Records today" : "Share it").sectionLabel()

            ForEach(prSets, id: \.persistentModelID) { set in
                if let time = set.bestTimeSeconds, let distance = set.distanceMeters {
                    // With one PR the hero already shows the time; repeating it
                    // here would just be noise. Several PRs need the list.
                    if prSets.count > 1 {
                        HStack {
                            Text("\(Int(distance))m")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(String(format: "%.2fs", time))
                                .font(.timingBoard(22, weight: .bold))
                                .foregroundStyle(Theme.brand)
                        }
                    }

                    // One renderer, three canvases — pick the surface to post to.
                    HStack(spacing: 8) {
                        ForEach(PRCardVariant.allCases) { variant in
                            if let image = PRCardRenderer.image(
                                firstName: firstName, effortLabel: "\(Int(distance))m",
                                timeSeconds: time, date: session.date, variant: variant) {
                                ShareLink(
                                    item: Image(uiImage: image),
                                    preview: SharePreview("New \(Int(distance))m PR",
                                                          image: Image(uiImage: image))
                                ) {
                                    Text(variant.label)
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Theme.brand)
                                        .foregroundStyle(Theme.textPrimary)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recap list

    private var exerciseRecap: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Logged").sectionLabel()
                .padding(.bottom, 8)

            ForEach(orderedSets, id: \.persistentModelID) { set in
                HStack {
                    Text(set.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if let time = set.bestTimeSeconds {
                        Text(String(format: "%.2fs", time))
                            .font(.caption.weight(.medium)).monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text("\(set.completedSets)/\(set.plannedSets)")
                        .font(.caption.weight(.medium)).monospacedDigit()
                        .foregroundStyle(set.completedSets >= set.plannedSets
                                         ? Theme.push : Theme.textSecondary)
                }
                .padding(.vertical, 10)
                if set.persistentModelID != orderedSets.last?.persistentModelID { LaneLine() }
            }
        }
    }
}
