import Foundation
import SwiftData
import CadenceCore

/// Suppresses re-prompting after a "Not now" for a cooling-off period, so a
/// dismissed proposal isn't naggy.
enum DismissedProposalStore {
    private static let key = "personalization.dismissed"
    private static let suppressDays: Double = 14

    private static var map: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static func dismiss(_ deficiency: String, now: Date = .now) {
        var m = map; m[deficiency] = now.timeIntervalSince1970; map = m
    }
    static func isDismissed(_ deficiency: String, now: Date = .now) -> Bool {
        guard let t = map[deficiency] else { return false }
        return (now.timeIntervalSince1970 - t) < suppressDays * 86_400
    }
}

/// Drives personalization end-to-end on top of the (already-bounded) engine.
/// `apply` only ever persists the engine's own proposed changes — it never
/// recomputes or exceeds them, so no guardrail is bypassed.
@MainActor
struct PersonalizationCoordinator {
    let context: ModelContext

    /// The active per-quality deltas for an event (empty if none applied).
    func activeDeltas(event: Event) -> [Quality: Int] {
        guard let adj = fetch(event) else { return [:] }
        return adj.deltas.reduce(into: [:]) { acc, kv in
            if let q = Quality(rawValue: kv.key) { acc[q] = kv.value }
        }
    }

    /// Top non-dismissed proposal for the current state, or nil. Pure read.
    func currentProposal(
        event: Event, currentPhase: PlanPhase,
        recentSessions: [TrainingSession], readinessTrend: ReadinessTrend, lowReadinessDays: Set<Date>
    ) -> AdjustmentProposal? {
        guard PersonalizationGate.isAvailable(for: event),
              let ranges = PersonalizationGate.ranges,
              let profile = ranges.profile(for: event.rawValue) else { return nil }

        var weekly = PlanPersonalizer.baselineWeekly(for: currentPhase)
        for (q, d) in activeDeltas(event: event) { weekly.reps[q, default: 0] += d }

        let observations = PersonalizationInputs.observations(
            from: recentSessions, profile: profile, lowReadinessDays: lowReadinessDays)
        let result = PersonalizationEngine(ranges: ranges).evaluate(
            event: event.rawValue, currentPhase: currentPhase.name,
            weekly: weekly, observations: observations, readinessTrend: readinessTrend)

        guard case .proposals(let proposals) = result else { return nil }
        return proposals.first { !DismissedProposalStore.isDismissed($0.deficiency) }
    }

    /// Persist the engine's already-computed, already-bounded changes. Accumulates
    /// onto any existing adjustment for the event.
    func apply(_ proposal: AdjustmentProposal, event: Event) {
        let adjustment = fetch(event) ?? {
            let a = PlanAdjustment(event: event.rawValue, deficiencyName: proposal.deficiency,
                                   reason: proposal.plainLanguage, deltas: [:])
            context.insert(a); return a
        }()
        for change in proposal.changes {
            adjustment.deltas[change.quality.rawValue, default: 0] += change.deltaReps
        }
        adjustment.deficiencyName = proposal.deficiency
        adjustment.reason = proposal.plainLanguage
        adjustment.appliedAt = .now
        try? context.save()
    }

    /// "Not now" — suppress this proposal for the cooling-off period.
    func dismiss(_ proposal: AdjustmentProposal) {
        DismissedProposalStore.dismiss(proposal.deficiency)
    }

    /// Undo / revert to the vetted plan for an event.
    func undo(event: Event) {
        if let adjustment = fetch(event) { context.delete(adjustment); try? context.save() }
    }

    private func fetch(_ event: Event) -> PlanAdjustment? {
        let raw = event.rawValue
        return try? context.fetch(FetchDescriptor<PlanAdjustment>(predicate: #Predicate { $0.event == raw })).first
    }
}
