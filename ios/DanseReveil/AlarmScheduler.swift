import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI

struct DanceMetadata: AlarmMetadata {}

/// État partagé entre l'app et les intents des boutons de l'alarme.
enum AlarmState {
    private static let d = UserDefaults.standard

    static var mainID: UUID? {
        get { d.string(forKey: "mainAlarmID").flatMap(UUID.init(uuidString:)) }
        set { d.set(newValue?.uuidString, forKey: "mainAlarmID") }
    }
    static var retryIDs: [UUID] {
        get { (d.stringArray(forKey: "retryAlarmIDs") ?? []).compactMap(UUID.init(uuidString:)) }
        set { d.set(newValue.map(\.uuidString), forKey: "retryAlarmIDs") }
    }
    /// L'alarme a sonné et tu n'as pas encore dansé.
    static var needsDance: Bool {
        get { d.bool(forKey: "needsDance") }
        set { d.set(newValue, forKey: "needsDance") }
    }
    static var danceDoneAt: Date? {
        get { d.object(forKey: "danceDoneAt") as? Date }
        set { d.set(newValue, forKey: "danceDoneAt") }
    }
    static var dancedRecently: Bool {
        guard let done = danceDoneAt else { return false }
        return Date().timeIntervalSince(done) < 10 * 60
    }
}

enum AlarmScheduler {
    static var manager: AlarmManager { AlarmManager.shared }

    static func requestAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .authorized: return true
        case .denied: return false
        default: return (try? await manager.requestAuthorization()) == .authorized
        }
    }

    static func configuration(id: UUID, schedule: Alarm.Schedule, title: LocalizedStringResource)
        -> AlarmManager.AlarmConfiguration<DanceMetadata>
    {
        let alert = AlarmPresentation.Alert(
            title: title,
            secondaryButton: AlarmButton(text: "Danser", textColor: .white, systemImageName: "figure.dance"),
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<DanceMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: DanceMetadata(),
            tintColor: Color(red: 1, green: 0.31, blue: 0.64)
        )
        let soundID = UserDefaults.standard.string(forKey: "sound") ?? "classique"
        return .alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: OpenDanceIntent(alarmID: id.uuidString),
            sound: .named(Sounds.fileName(for: soundID))
        )
    }

    /// Programme l'alarme principale (remplace la précédente).
    static func arm(_ settings: AppSettings) async throws {
        if let old = AlarmState.mainID { try? manager.cancel(id: old) }
        let schedule: Alarm.Schedule
        if settings.repeatDaily {
            let time = Alarm.Schedule.Relative.Time(hour: settings.hour, minute: settings.minute)
            let days: [Locale.Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
            schedule = .relative(.init(time: time, repeats: .weekly(days)))
        } else {
            schedule = .fixed(settings.nextAlarmDate())
        }
        let id = UUID()
        _ = try await manager.schedule(
            id: id, configuration: configuration(id: id, schedule: schedule, title: "Debout ! Il faut danser 💃"))
        AlarmState.mainID = id
    }

    static func disarm() {
        if let id = AlarmState.mainID { try? manager.cancel(id: id) }
        AlarmState.mainID = nil
        cancelRetries()
        AlarmState.needsDance = false
    }

    /// Relance : l'alarme resonne dans `seconds` tant que tu n'as pas dansé.
    static func scheduleRetry(after seconds: TimeInterval) async {
        cancelRetries()
        let id = UUID()
        let cfg = configuration(
            id: id, schedule: .fixed(Date().addingTimeInterval(seconds)), title: "Pas si vite ! Danse pour arrêter 🕺")
        if (try? await manager.schedule(id: id, configuration: cfg)) != nil {
            AlarmState.retryIDs = [id]
        }
    }

    static func cancelRetries() {
        for id in AlarmState.retryIDs { try? manager.cancel(id: id) }
        AlarmState.retryIDs = []
    }

    /// Coupe le son système des alarmes en cours (l'app prend le relais).
    static func stopAlerting() {
        let alarms = (try? manager.alarms) ?? []
        for alarm in alarms where alarm.state == .alerting {
            try? manager.stop(id: alarm.id)
        }
    }
}

// MARK: - Boutons de l'alarme sur l'écran verrouillé

/// Bouton « Danser » : ouvre l'app sur l'écran de danse.
struct OpenDanceIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Danser"
    static var description = IntentDescription("Ouvre Danse Réveil pour arrêter l'alarme en dansant.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "alarmID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        AlarmState.needsDance = true
        AlarmScheduler.stopAlerting()
        // Filet de sécurité : si tu te rendors sans danser, ça resonne dans 3 min.
        await AlarmScheduler.scheduleRetry(after: 180)
        return .result()
    }
}

/// Bouton « Arrêter » : arrête le son… mais l'alarme revient dans 1 min si tu n'as pas dansé.
struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Arrêter"
    static var description = IntentDescription("Arrête l'alarme. Elle revient si tu n'as pas dansé.")

    @Parameter(title: "alarmID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: id) }
        if !AlarmState.dancedRecently {
            AlarmState.needsDance = true
            await AlarmScheduler.scheduleRetry(after: 60)
        }
        return .result()
    }
}
