import Foundation
import SwiftData
import CadenceCore

/// Keeps today's readiness a *living value*: registers HealthKit observer queries
/// + background delivery on the core recovery signals so late-syncing wearable
/// data recomputes today's `DailyReadiness` with zero user action. This is the
/// path that fixes the Garmin case — Garmin only writes to Apple Health when its
/// companion app opens, often hours after the morning check-in.
///
/// **Device-only.** HealthKit returns nothing in the simulator and background
/// delivery requires a real device + the HealthKit capability (no extra
/// entitlement — never the clinical `.access` array). Validate with the spec's
/// acceptance tests on a physical phone.
@MainActor
final class LiveReadinessMonitor {
    private let container: ModelContainer
    private let health: HealthKitService
    private var started = false

    init(container: ModelContainer, health: HealthKitService = HealthKitService()) {
        self.container = container
        self.health = health
    }

    /// Idempotent. Turns on background delivery and observer queries; each new
    /// batch of samples triggers a silent in-place recompute of today's readiness.
    func start() {
        guard !started, health.isAvailable else { return }
        started = true
        health.enableBackgroundDelivery()
        health.startObserving { [weak self] in
            Task { @MainActor in await self?.recompute() }
        }
    }

    /// Rebuild today's readiness in place from the latest HealthKit data, reusing
    /// the already-stored check-in (never re-prompts). No-op unless today's
    /// check-in is complete — readiness is gated on the check-in, same as in-app —
    /// and the in-place persist preserves any session-start freeze, so a session
    /// already underway is never rescaled.
    private func recompute() async {
        let context = ModelContext(container)
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)

        let checkIns = (try? context.fetch(
            FetchDescriptor<CheckIn>(predicate: #Predicate { $0.day == today }))) ?? []
        guard checkIns.first?.completedAt != nil else { return }

        let coordinator = ReadinessCoordinator(health: health)
        guard let result = try? await coordinator.computeToday(
                asOf: now, phone: .from(context: context, now: now)),
              let row = try? coordinator.persist(result, on: now, into: context)
        else { return }

        WidgetBridge.publish(score: row.score, verdict: row.effectiveVerdict,
                             multiplier: row.effectiveMultiplier, on: now)
    }
}
