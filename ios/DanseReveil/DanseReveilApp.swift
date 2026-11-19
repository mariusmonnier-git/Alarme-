import AlarmKit
import SwiftUI

@main
struct DanseReveilApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var ring = RingController.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(ring)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    ring.resumeIfNeeded()
                    Task { await AlarmScheduler.ensureScheduled(settings) }
                }
                .task {
                    ring.resumeIfNeeded()
                    await AlarmScheduler.ensureScheduled(settings)
                    // Si l'alarme sonne pendant que l'app est ouverte, on passe direct à la danse.
                    for await alarms in AlarmManager.shared.alarmUpdates {
                        guard alarms.contains(where: { $0.state == .alerting }),
                              scenePhase == .active else { continue }
                        if ring.phase == .ringing {
                            AlarmScheduler.stopAlerting()
                            await AlarmScheduler.postponeChain(by: 180)
                        } else {
                            ring.start()
                        }
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var ring: RingController

    var body: some View {
        switch ring.phase {
        case .idle: HomeView()
        case .ringing: DanceView()
        case .done: DoneView()
        }
    }
}

/// Style sobre façon app Horloge : noir, gris système, un seul accent orange.
enum Theme {
    static let accent = Color(red: 1, green: 0.624, blue: 0.039)  // orange système #FF9F0A
    static let ok = Color(red: 0.188, green: 0.82, blue: 0.345)  // vert système #30D158
}
