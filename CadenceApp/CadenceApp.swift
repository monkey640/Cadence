import SwiftUI
import SwiftData

@main
struct CadenceApp: App {
    /// Owns the SwiftData container — the real store, or the demo store when
    /// demo mode is on (DEBUG only).
    @State private var store = StoreController()

    /// Owns the color scheme; its init themes the first frame before any view draws.
    @State private var theme = ThemeManager()

    init() {
        // Must register the background-task handler before launch finishes.
        MorningNotificationService.shared.registerBackgroundTask()
        MorningNotificationService.shared.scheduleNext()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // A store switch rebuilds the whole tree so every @Query refetches
                // from the newly opened store.
                .id(store.generation)
                .modelContainer(store.container)
                .environment(store)
                .environment(theme)
                // Apply the scheme's light/dark app-wide, and rebuild the tree
                // when it changes so every `Theme.*` read picks up the new palette.
                .preferredColorScheme(theme.scheme.palette.colorScheme)
                .id(theme.scheme)
        }
    }
}

/// Opens the app's single SwiftData container and, in DEBUG builds, swaps it
/// for the demo store and back. The real store is never written by demo mode.
@MainActor
@Observable
final class StoreController {
    private(set) var container: ModelContainer
    /// Bumped on every store switch; the root view is keyed on it.
    private(set) var generation = 0

    init() {
        container = Self.makeContainer(demo: DemoMode.isOn)
        #if DEBUG
        // Demo flag set but the demo store is empty (e.g. it was deleted): reseed.
        if DemoMode.isOn,
           (try? container.mainContext.fetchCount(FetchDescriptor<AthleteProfile>())) ?? 0 == 0 {
            DemoMode.populate(container.mainContext, from: nil)
        }
        #endif
    }

    private static func makeContainer(demo: Bool) -> ModelContainer {
        do {
            #if DEBUG
            if demo { return try DemoMode.makeContainer() }
            #endif
            return try ModelContainer(for: AppSchema.schema)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    #if DEBUG
    var isDemo: Bool { DemoMode.isOn }

    /// Turns demo mode on (copying the real profile into a freshly seeded demo
    /// store) or off (reopening the real store untouched).
    func setDemo(_ on: Bool) {
        guard on != DemoMode.isOn else { return }
        let snapshot = on ? DemoMode.ProfileSnapshot.read(from: container.mainContext) : nil
        DemoMode.isOn = on
        container = Self.makeContainer(demo: on)
        if on { DemoMode.populate(container.mainContext, from: snapshot) }
        generation += 1
    }

    /// Re-seeds the demo store — after changing today's verdict, say.
    func rebuildDemo() {
        guard DemoMode.isOn else { return }
        let snapshot = DemoMode.ProfileSnapshot.read(from: container.mainContext)
        DemoMode.populate(container.mainContext, from: snapshot)
        generation += 1
    }
    #endif
}

/// Routes to onboarding until the profile is complete, then to the main tabs.
/// (Tab screens are stubbed here and filled in over the next build steps.)
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [AthleteProfile]
    @State private var monitor: LiveReadinessMonitor?
    private var profile: AthleteProfile? { profiles.first }

    var body: some View {
        Group {
            if let profile, profile.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        #if DEBUG
        .task {
            if DemoSeed.isRequested && profiles.isEmpty { DemoSeed.seed(into: context) }
        }
        #endif
        // Once onboarding is done, keep today's readiness live: observe HealthKit
        // so late-synced wearable data recomputes it with no user action.
        .task(id: profile?.hasCompletedOnboarding ?? false) {
            // Demo mode holds today still for filming — real HealthKit data must
            // not recompute the seeded day.
            guard profile?.hasCompletedOnboarding == true, !DemoMode.isOn else { return }
            let monitor = monitor ?? LiveReadinessMonitor(container: context.container)
            self.monitor = monitor
            monitor.start()
        }
    }
}

/// Shared tab selection so empty states can route the athlete (e.g. History's
/// "check in" button jumps to Today).
@MainActor
@Observable
final class TabRouter {
    enum Tab: String, Hashable { case today, plan, trends, history, settings }

    /// Persisted so a scheme change (which rebuilds the tree) lands the athlete
    /// back on the tab they were on, not bounced to Today.
    var selection: Tab {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: "tab.selection") }
    }

    init() {
        #if DEBUG
        // Sim-only CLI hook (pairs with DemoSeed): launch with CADENCE_DEMO_TAB=
        // today|plan|trends|history|settings to land on a specific tab.
        if let forced = ProcessInfo.processInfo.environment["CADENCE_DEMO_TAB"]
            .flatMap(Tab.init(rawValue:)) {
            selection = forced
            return
        }
        #endif
        selection = UserDefaults.standard.string(forKey: "tab.selection")
            .flatMap(Tab.init(rawValue:)) ?? .today
    }
}

struct MainTabView: View {
    @State private var router = TabRouter()

    var body: some View {
        TabView(selection: $router.selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(TabRouter.Tab.today)
            PlanTabView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(TabRouter.Tab.plan)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(TabRouter.Tab.trends)
            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet") }
                .tag(TabRouter.Tab.history)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(TabRouter.Tab.settings)
        }
        .environment(router)
        .tint(Theme.brand)
        .preferredColorScheme(Theme.scheme)   // dark-mode-first
    }
}
