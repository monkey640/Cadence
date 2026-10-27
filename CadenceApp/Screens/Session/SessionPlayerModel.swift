import Foundation
import Observation
import SwiftData
import AudioToolbox
import CadenceCore

/// Drives the session player. All progress writes go straight to the SwiftData
/// session (completed sets, active seconds, resume index), continuously — a
/// killed or crashed app resumes exactly where it left off.
@MainActor
@Observable
final class SessionPlayerModel {

    enum Phase: Equatable {
        case working          // logging sets on the current block
        case resting          // countdown running between sets
        case finished         // summary
    }

    let session: TrainingSession
    /// Display metadata (scaled-from, intensity, target, rest note) by set order.
    private let blockInfo: [Int: TodayViewModel.DisplayBlock]

    private(set) var phase: Phase = .working
    private(set) var currentIndex: Int
    private(set) var isPaused = false

    /// Live elapsed seconds (persisted `activeSeconds` + the running segment).
    private(set) var elapsed: Double = 0

    // Rest timer.
    private var restStartDate: Date?
    private(set) var restEndDate: Date?
    private(set) var restTotal: Double = 0
    private(set) var restRemaining: Double = 0

    /// Default rest when the plan block didn't specify one.
    static let defaultRest: Double = 90

    private var ticker: Task<Void, Never>?
    private var segmentStart: Date?
    private var lastPersist = Date()
    private let liveActivity = RestTimerActivityController()

    var orderedSets: [SessionSet] { session.sets.sorted { $0.order < $1.order } }
    var currentSet: SessionSet? {
        let sets = orderedSets
        return currentIndex < sets.count ? sets[currentIndex] : sets.last
    }
    var info: TodayViewModel.DisplayBlock? {
        currentSet.map { blockInfo[$0.order] } ?? nil
    }
    var allDone: Bool { orderedSets.allSatisfy { $0.completedSets >= $0.plannedSets } }

    init(session: TrainingSession, displayBlocks: [TodayViewModel.DisplayBlock]) {
        self.session = session
        // Sets were created from the rep-carrying blocks in order; align by position.
        let repBlocks = displayBlocks.filter { $0.scaledReps != nil }
        var map: [Int: TodayViewModel.DisplayBlock] = [:]
        for (index, block) in repBlocks.enumerated() { map[index] = block }
        self.blockInfo = map
        self.currentIndex = min(session.resumeBlockIndex, max(0, session.sets.count - 1))
    }

    // MARK: - Lifecycle

    func start(context: ModelContext) {
        if session.startedAt == nil { session.startedAt = .now }
        liveActivity.prepareAlerts()
        elapsed = session.activeSeconds
        segmentStart = .now
        try? context.save()
        runTicker(context: context)
        #if DEBUG
        // Sim-only: CADENCE_DEMO_PLAYER=rest drops straight into the rest countdown
        // so the full-screen rest mode can be screenshotted.
        if ProcessInfo.processInfo.environment["CADENCE_DEMO_PLAYER"] == "rest",
           let set = currentSet, !session.isRecovery {
            startRest(for: set)
        }
        #endif
    }

    func pause(context: ModelContext) {
        guard !isPaused else { return }
        bank(restart: false)
        isPaused = true
        persist(context: context)
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        segmentStart = .now
    }

    /// Called on disappear: bank time, persist, stop the ticker. Not a completion.
    func suspend(context: ModelContext) {
        bank(restart: false)
        persist(context: context)
        ticker?.cancel()
        liveActivity.end()
    }

    // MARK: - Set logging

    /// Log one set on the current block (medium haptic). Starts rest unless the
    /// whole session just finished or the block is a recovery item.
    func logSet(context: ModelContext) {
        guard let set = currentSet, set.completedSets < set.plannedSets else { return }
        set.completedSets += 1
        Haptics.set()
        persist(context: context)

        if set.completedSets >= set.plannedSets {
            advance(context: context)
        } else if !session.isRecovery {
            startRest(for: set)
        }
    }

    /// Move to the next unfinished block (or finish readiness to summary).
    func advance(context: ModelContext) {
        cancelRest()
        let sets = orderedSets
        if let next = sets.indices.first(where: { $0 > currentIndex && sets[$0].completedSets < sets[$0].plannedSets })
            ?? sets.indices.first(where: { sets[$0].completedSets < sets[$0].plannedSets }) {
            currentIndex = next
            session.resumeBlockIndex = next
            persist(context: context)
        }
        // All blocks done → let the athlete hit "Finish session" (no surprise jump).
    }

    func jump(to index: Int, context: ModelContext) {
        guard index >= 0, index < orderedSets.count else { return }
        cancelRest()
        currentIndex = index
        session.resumeBlockIndex = index
        persist(context: context)
    }

    // MARK: - Rest timer

    private func startRest(for set: SessionSet) {
        let duration = set.restSeconds ?? Self.defaultRest
        restTotal = duration
        restRemaining = duration
        let now = Date()
        restStartDate = now
        restEndDate = now.addingTimeInterval(duration)
        phase = .resting
        liveActivity.start(
            sessionTitle: session.title,
            verdictRaw: session.isRecovery ? Verdict.hold.rawValue : session.verdictRaw,
            state: .init(startDate: now, endDate: restEndDate ?? now, blockName: set.name,
                         setsDone: set.completedSets, setsTotal: set.plannedSets))
    }

    /// Real rest never matches the plan — +15s bumps the countdown.
    func extendRest() {
        guard let end = restEndDate else { return }
        restEndDate = end.addingTimeInterval(15)
        restTotal += 15
        if let set = currentSet {
            liveActivity.update(state: .init(
                startDate: restStartDate ?? .now, endDate: restEndDate ?? .now, blockName: set.name,
                setsDone: set.completedSets, setsTotal: set.plannedSets))
        }
    }

    func skipRest() {
        cancelRest()
    }

    private func cancelRest() {
        restEndDate = nil
        phase = .working
        liveActivity.end()
    }

    private func restExpired() {
        // Audible cue + strong haptic — this fires with the phone in a pocket.
        AudioServicesPlaySystemSound(1005)
        Haptics.stamp()
        cancelRest()
    }

    // MARK: - Completion

    func finish(context: ModelContext) {
        bank(restart: false)
        session.isComplete = true
        session.completedAt = .now
        PersonalRecordTracker.apply(to: session, context: context)
        persist(context: context)
        liveActivity.end()
        phase = .finished
    }

    var prSets: [SessionSet] { orderedSets.filter { $0.wasPR } }

    // MARK: - Clock

    private func runTicker(context: ModelContext) {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.25))
                guard let self, !Task.isCancelled else { return }
                self.tick(context: context)
            }
        }
    }

    private func tick(context: ModelContext) {
        if !isPaused, let start = segmentStart {
            elapsed = session.activeSeconds + Date().timeIntervalSince(start)
        }
        if phase == .resting, let end = restEndDate {
            restRemaining = max(0, end.timeIntervalSinceNow)
            if restRemaining <= 0 { restExpired() }
        }
        // Continuous persistence, throttled: every 10s of wall time.
        if Date().timeIntervalSince(lastPersist) > 10 {
            bank(restart: !isPaused)
            persist(context: context)
        }
    }

    /// Fold the running segment into the persisted total; optionally start a new one.
    private func bank(restart: Bool) {
        if let start = segmentStart {
            session.activeSeconds += Date().timeIntervalSince(start)
        }
        segmentStart = restart ? .now : nil
        elapsed = session.activeSeconds
    }

    private func persist(context: ModelContext) {
        lastPersist = .now
        try? context.save()
    }
}
