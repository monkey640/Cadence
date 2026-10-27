import Foundation
import Observation
import SwiftData
import CadenceCore

/// One wellness question. Anchor labels are phrased so the raw 1–5 selection is
/// already in the engine's higher-is-better convention (5 = fresh/calm/great) —
/// no flipping needed between UI and `WellnessCheckIn`.
struct WellnessQuestion: Identifiable {
    let id: String
    let text: String
    let lowAnchor: String
    let highAnchor: String
    let icon: String

    static let all: [WellnessQuestion] = [
        .init(id: "sleep", text: "How did you sleep?",
              lowAnchor: "Terrible", highAnchor: "Great", icon: "moon.zzz.fill"),
        .init(id: "soreness", text: "How sore are your legs?",
              lowAnchor: "Wrecked", highAnchor: "Fresh", icon: "figure.strengthtraining.functional"),
        .init(id: "fatigue", text: "How fatigued do you feel?",
              lowAnchor: "Exhausted", highAnchor: "Energized", icon: "bolt.fill"),
        .init(id: "stress", text: "How stressed are you?",
              lowAnchor: "High stress", highAnchor: "Calm", icon: "brain.head.profile"),
        .init(id: "mood", text: "How's your mood?",
              lowAnchor: "Low", highAnchor: "High", icon: "face.smiling.fill"),
    ]
}

/// Drives the morning check-in ritual: five wellness questions → tap test →
/// jump test → score reveal. Saves the `CheckIn` row, then runs the readiness
/// pipeline so the reveal shows the real, persisted score.
@MainActor
@Observable
final class CheckInFlowModel {

    enum Step: Equatable {
        case question(Int)      // 0..<5
        case tapTest
        case jumpTest
        case computing
        case reveal
    }

    private(set) var step: Step = .question(0)
    /// Direction of the last step change, so the container can slide accordingly.
    private(set) var movingForward = true

    // Answers (1...5, engine convention), by question index.
    var answers: [Int?] = Array(repeating: nil, count: WellnessQuestion.all.count)

    // Phone-test results. nil = skipped.
    var tapCount: Int?
    var jumpHeightCm: Double?

    /// Prior-day tap counts, for the "above/below your baseline" line.
    private(set) var tapBaseline: Double?

    /// The computed result backing the reveal.
    private(set) var output: ReadinessOutput?
    private(set) var computeError: String?

    /// For the "checked in in 48s" footnote — the spec says time the ritual.
    private let flowStart = Date()
    private(set) var completionSeconds: Int?

    private let health: HealthDataProviding
    init(health: HealthDataProviding = HealthKitService()) { self.health = health }

    // MARK: - Navigation

    /// Total dot count: five questions + tap + jump.
    var progressCount: Int { WellnessQuestion.all.count + 2 }

    var progressIndex: Int {
        switch step {
        case .question(let i): return i
        case .tapTest: return WellnessQuestion.all.count
        case .jumpTest, .computing, .reveal: return WellnessQuestion.all.count + 1
        }
    }

    func advanceFromQuestion(_ index: Int) {
        movingForward = true
        if index + 1 < WellnessQuestion.all.count {
            step = .question(index + 1)
        } else {
            step = .tapTest
        }
    }

    /// Progress-dot / swipe-back navigation — only to already-answered ground.
    func goBack() {
        movingForward = false
        switch step {
        case .question(let i) where i > 0: step = .question(i - 1)
        case .tapTest: step = .question(WellnessQuestion.all.count - 1)
        case .jumpTest: step = .tapTest
        default: break
        }
    }

    func jumpToQuestion(_ index: Int) {
        guard index < WellnessQuestion.all.count, index <= progressIndex else { return }
        movingForward = index > progressIndex
        step = .question(index)
    }

    func finishTapTest(count: Int?) {
        tapCount = count
        movingForward = true
        step = .jumpTest
    }

    func finishJumpTest(heightCm: Double?, context: ModelContext) {
        jumpHeightCm = heightCm
        movingForward = true
        step = .computing
        Task { await completeCheckIn(context: context) }
    }

    // MARK: - Data

    /// Average of prior-day tap counts (the same history the engine baselines on).
    func loadTapBaseline(context: ModelContext, now: Date = .now) {
        let today = Calendar.current.startOfDay(for: now)
        let all = (try? context.fetch(FetchDescriptor<CheckIn>())) ?? []
        let prior = all.filter { $0.day < today }.compactMap(\.fingerTapCount)
        tapBaseline = prior.isEmpty ? nil : prior.reduce(0, +) / Double(prior.count)
    }

    /// Persist the check-in, run the readiness pipeline, land on the reveal.
    private func completeCheckIn(context: ModelContext, now: Date = .now) async {
        let today = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.day == today })
        let row = (try? context.fetch(descriptor).first) ?? {
            let fresh = CheckIn(day: today)
            context.insert(fresh)
            return fresh
        }()

        row.wellnessSleep = answers[0]
        row.wellnessSoreness = answers[1]
        row.wellnessFatigue = answers[2]
        row.wellnessStress = answers[3]
        row.wellnessMood = answers[4]
        row.fingerTapCount = tapCount.map(Double.init)
        row.jumpHeightCm = jumpHeightCm
        row.completedAt = .now
        try? context.save()

        let coordinator = ReadinessCoordinator(health: health)
        do {
            let result = try await coordinator.computeToday(
                asOf: now, phone: .from(context: context, now: now))
            try coordinator.persist(result, on: now, into: context)
            output = result.output
        } catch {
            // The check-in itself is saved; a HealthKit failure only costs the
            // wearable signals. Fall back to a phone-only evaluation so the
            // athlete still gets a verdict (conservative, low/moderate confidence).
            let phone = ReadinessCoordinator.PhoneInputs.from(context: context, now: now)
            let input = ReadinessInput(
                date: today,
                hrvSDNN: nil, hrvBaseline: nil,
                sleepSeconds: nil, sleepBaseline: nil,
                sleepQualitySeconds: nil, sleepQualityBaseline: nil,
                restingHR: nil, rhrBaseline: nil,
                respiratoryRate: nil, respiratoryRateBaseline: nil,
                wristTemperature: nil, wristTemperatureBaseline: nil,
                loadRatio: nil,
                wellness: phone.wellness,
                fingerTapCount: phone.fingerTapToday,
                fingerTapBaseline: BaselineCalculator.baseline(from: phone.fingerTapHistory),
                countermovementJumpCm: phone.jumpToday,
                cmjBaseline: BaselineCalculator.baseline(from: phone.jumpHistory))
            let fallback = ReadinessEngine().evaluate(input)
            let existing = FetchDescriptor<DailyReadiness>(predicate: #Predicate { $0.date == today })
            (try? context.fetch(existing))?.forEach { context.delete($0) }
            context.insert(DailyReadiness(
                date: today, output: fallback, hrvSDNN: nil, sleepSeconds: nil, restingHR: nil))
            try? context.save()
            output = fallback
            computeError = error.localizedDescription
        }
        if let output {
            WidgetBridge.publish(score: output.score, verdict: output.verdict,
                                 multiplier: output.volumeMultiplier, on: now)
        }
        completionSeconds = Int(Date().timeIntervalSince(flowStart))
        movingForward = true
        step = .reveal
    }
}
