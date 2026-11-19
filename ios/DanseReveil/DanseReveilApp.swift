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
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { ring.resumeIfNeeded() }
                }
                .task {
                    ring.resumeIfNeeded()
                    // Si l'alarme sonne pendant que l'app est ouverte, on passe direct à la danse.
                    for await alarms in AlarmManager.shared.alarmUpdates {
                        guard alarms.contains(where: { $0.state == .alerting }),
                              scenePhase == .active else { continue }
                        AlarmState.needsDance = true
                        if ring.phase == .ringing {
                            AlarmScheduler.stopAlerting()
                            await AlarmScheduler.scheduleRetry(after: 180)
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
        ZStack {
            Theme.background.ignoresSafeArea()
            switch ring.phase {
            case .idle: HomeView()
            case .ringing: DanceView()
            case .done: DoneView()
            }
        }
    }
}

enum Theme {
    static let pink = Color(red: 1, green: 0.31, blue: 0.64)
    static let orange = Color(red: 1, green: 0.70, blue: 0.28)
    static let green = Color(red: 0.24, green: 0.88, blue: 0.56)
    static let muted = Color(red: 0.70, green: 0.67, blue: 0.84)
    static let card = Color.white.opacity(0.07)
    static let gradient = LinearGradient(colors: [pink, orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let background = RadialGradient(
        colors: [Color(red: 0.13, green: 0.10, blue: 0.27), Color(red: 0.08, green: 0.06, blue: 0.16)],
        center: .topLeading, startRadius: 0, endRadius: 700)
}
