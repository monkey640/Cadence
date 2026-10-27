import Foundation
import BackgroundTasks
import UserNotifications
import SwiftData
import CadenceCore

/// Schedules and delivers the once-daily morning readiness notification.
///
/// A `BGAppRefreshTask` near the user's chosen time computes today's readiness
/// (overnight HRV/sleep are already in HealthKit) and posts a local
/// notification whose text includes the actual verdict. `NotificationGate`
/// enforces a hard one-per-day cap even if iOS runs the task more than once.
@MainActor
final class MorningNotificationService {
    static let shared = MorningNotificationService()
    static let taskIdentifier = "net.adnanahmad.Cadence.morningReadiness"

    private let defaults = UserDefaults.standard
    private enum Key {
        static let enabled = "morning.enabled"
        static let hour = "morning.hour"
        static let minute = "morning.minute"
        static let lastDelivered = "morning.lastDelivered"
        static let contextual = "notif.contextual.enabled"
    }

    /// Stable identifiers for the contextual suite — reused so a refresh replaces
    /// rather than stacks them.
    private enum ContextID {
        static let windDown = "cadence.windDown"
        static let streak = "cadence.streakRisk"
        static let meet = "cadence.meetWeek"
        static var all: [String] { [windDown, streak, meet] }
    }

    // MARK: - Settings (persisted)

    var isEnabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }
    /// Defaults to 07:00.
    var hour: Int {
        get { defaults.object(forKey: Key.hour) as? Int ?? 7 }
        set { defaults.set(newValue, forKey: Key.hour) }
    }
    var minute: Int {
        get { defaults.object(forKey: Key.minute) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: Key.minute) }
    }
    private var lastDelivered: Date? {
        get { (defaults.object(forKey: Key.lastDelivered) as? Double).map(Date.init(timeIntervalSince1970:)) }
        set { defaults.set(newValue?.timeIntervalSince1970, forKey: Key.lastDelivered) }
    }

    // MARK: - Setup

    /// Called once at launch to register the background task handler.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let self, let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            MainActor.assumeIsolated { self.handle(refresh) }
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Enable/disable the morning notification and (re)schedule accordingly.
    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        if enabled { _ = await requestAuthorization() }
        scheduleNext()
    }

    func setTime(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
        scheduleNext()
    }

    // MARK: - Scheduling

    /// Queue the next background refresh at the user's chosen time (or cancel if off).
    func scheduleNext() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = nextFireDate()
        try? BGTaskScheduler.shared.submit(request)
    }

    private func nextFireDate() -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.nextDate(after: .now, matching: comps, matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(24 * 3600)
    }

    // MARK: - Background execution

    private func handle(_ task: BGAppRefreshTask) {
        scheduleNext()   // always queue tomorrow first, so the chain never breaks
        let work = Task { @MainActor in
            await runMorningCheck()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Deliver the morning check-in prompt — subject to the one-per-day cap.
    /// Safe to call repeatedly; it no-ops after the first delivery each day.
    ///
    /// The score is revealed by the check-in flow, so the notification invites
    /// the ritual rather than pre-announcing a verdict. Copy is specific, never
    /// hype: it acknowledges yesterday's session when there was one.
    func runMorningCheck(now: Date = .now) async {
        guard isEnabled else { return }
        guard NotificationGate.shouldDeliver(now: now, lastDelivered: lastDelivered) else { return }

        deliver(body: bodyText(now: now))
        lastDelivered = now   // record the cap only after a successful post
    }

    /// "Big day yesterday" when a non-recovery session was completed yesterday,
    /// else the standard check-in prompt.
    private func bodyText(now: Date) -> String {
        let standard = "Morning check-in — 60 seconds to today's verdict."
        guard let container = try? ModelContainer(for: AppSchema.schema) else { return standard }
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)) else {
            return standard
        }
        let descriptor = FetchDescriptor<TrainingSession>(
            predicate: #Predicate { $0.date == yesterday && $0.isComplete && !$0.isRecovery })
        let hadSession = ((try? container.mainContext.fetch(descriptor)) ?? []).isEmpty == false
        return hadSession ? "Big day yesterday. Let's see how you recovered." : standard
    }

    private func deliver(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Cadence"
        content.body = body
        content.sound = .default
        // nil trigger → deliver immediately (we're already at the chosen time).
        let request = UNNotificationRequest(identifier: "cadence.morning", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Contextual suite (all optional, all local)

    /// Master opt-in for the contextual nudges (wind-down / streak / meet week),
    /// separate from and respectful of the morning check-in. Off by default.
    var contextualEnabled: Bool {
        get { defaults.object(forKey: Key.contextual) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.contextual) }
    }

    func setContextualEnabled(_ enabled: Bool, context: ModelContext) async {
        contextualEnabled = enabled
        if enabled { _ = await requestAuthorization() }
        await refreshContextual(context: context)
    }

    /// Re-evaluate the three contextual cues against current state and (re)schedule
    /// them for this evening / the coming morning. Idempotent — safe to call on
    /// every app open; it clears and rebuilds the set, so stale cues never fire.
    /// All fire in the evening (distinct from the 7-ish AM morning check-in).
    func refreshContextual(context: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ContextID.all)
        guard contextualEnabled else { return }
        guard let profile = try? context.fetch(FetchDescriptor<AthleteProfile>()).first else { return }
        let cal = Calendar.current

        // 1. Evening wind-down the night before a training day.
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
           isTrainingDay(tomorrow, profile: profile) {
            schedule(id: ContextID.windDown,
                     body: "Session tomorrow — an early night sets you up.",
                     hour: 20, minute: 0)
        }

        // 2. Streak-at-risk — only a real streak (≥7) that isn't yet protected today.
        let streak = StreakService.currentStreak(context: context, today: now).days
        if streak >= 7, !checkedInToday(context: context, now: now) {
            schedule(id: ContextID.streak,
                     body: "Your \(streak)-day streak is still alive — a 60-second check-in keeps it going.",
                     hour: 19, minute: 0)
        }

        // 3. Meet-week daily cue.
        if let meet = profile.meetDate {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                          to: cal.startOfDay(for: meet)).day ?? -1
            if days == 0 {
                schedule(id: ContextID.meet, body: "Race day. Warm up, trust the work, and go.",
                         hour: 18, minute: 0)
            } else if (1...7).contains(days) {
                schedule(id: ContextID.meet,
                         body: "\(days) day\(days == 1 ? "" : "s") to race. Taper on — sharpen, don't strain.",
                         hour: 18, minute: 0)
            }
        }
    }

    /// Bit 0 = Monday … bit 6 = Sunday (matching AthleteProfile.trainingWeekdayMask).
    private func isTrainingDay(_ date: Date, profile: AthleteProfile) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)  // 1=Sun … 7=Sat
        let index = (weekday + 5) % 7                                   // → 0=Mon … 6=Sun
        return profile.trainingWeekdayMask & (1 << index) != 0
    }

    private func checkedInToday(context: ModelContext, now: Date) -> Bool {
        let today = Calendar.current.startOfDay(for: now)
        let d = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.day == today })
        return ((try? context.fetch(d))?.first?.completedAt) != nil
    }

    private func schedule(id: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Cadence"
        content.body = body
        content.sound = .default
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
