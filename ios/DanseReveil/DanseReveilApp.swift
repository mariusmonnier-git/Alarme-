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
                .fontDesign(.rounded)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, Demo.screen == nil else { return }
                    ring.resumeIfNeeded()
                    Task { await AlarmScheduler.ensureScheduled(settings) }
                }
                .task {
                    // Mode démo pour les captures : xcrun simctl launch … -demo dance
                    if let demo = Demo.screen {
                        settings.isArmed = Demo.armed
                        settings.repeatDaily = true
                        ring.showDemo(demo)
                        return
                    }
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
        case .idle where Demo.screen == "sounds":
            NavigationStack { SoundListView() }
        case .idle: HomeView()
        case .ringing: DanceView()
        case .done: DoneView()
        }
    }
}

/// Arguments de lancement utilisés seulement pour les captures d'écran automatiques.
enum Demo {
    static var screen: String? { UserDefaults.standard.string(forKey: "demo") }
    static var armed: Bool { UserDefaults.standard.bool(forKey: "demoArmed") }
}

/// Style du logo : orange vif sur noir, formes rondes et épaisses.
enum Theme {
    static let accent = Color(red: 254 / 255, green: 123 / 255, blue: 2 / 255)  // #FE7B02, l'orange du logo
    static let ok = accent
    static let row = Color(white: 0.09)  // fond des lignes
    static let ink = Color.black  // texte sur fond orange
}

/// Gros bouton orange arrondi, dans l'esprit du logo.
struct PillButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.title3, design: .rounded, weight: .heavy))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(filled ? Theme.ink : Theme.accent)
            .background(filled ? Theme.accent : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(Theme.accent, lineWidth: filled ? 0 : 3))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
