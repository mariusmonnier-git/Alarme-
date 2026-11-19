import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI

struct DanceMetadata: AlarmMetadata {}

/// Une alarme programmée dans iOS (principale ou relance).
struct ScheduledAlarm: Codable {
    let id: UUID
    let date: Date
}

/// État partagé entre l'app et les boutons de l'alarme (intents).
enum AlarmState {
    private static let d = UserDefaults.standard

    static var mainID: UUID? {
        get { d.string(forKey: "mainAlarmID").flatMap(UUID.init(uuidString:)) }
        set { d.set(newValue?.uuidString, forKey: "mainAlarmID") }
    }

    /// Heure de la prochaine (ou dernière) sonnerie principale.
    static var nextFire: Date? {
        get { d.object(forKey: "nextFire") as? Date }
        set { d.set(newValue, forKey: "nextFire") }
    }

    /// Relances programmées toutes les 30 s après la sonnerie principale.
    static var chain: [ScheduledAlarm] {
        get {
            guard let data = d.data(forKey: "alarmChain") else { return [] }
            return (try? JSONDecoder().decode([ScheduledAlarm].self, from: data)) ?? []
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "alarmChain") }
    }

    static var danceDoneAt: Date? {
        get { d.object(forKey: "danceDoneAt") as? Date }
        set { d.set(newValue, forKey: "danceDoneAt") }
    }

    /// L'alarme a sonné et tu n'as pas encore dansé (fenêtre de 2 h).
    /// Calculé à partir de l'heure, donc vrai même si aucun bouton n'a été touché.
    static var needsDance: Bool {
        guard d.bool(forKey: "isArmed"), let fire = nextFire else { return false }
        let now = Date()
        guard fire <= now, now.timeIntervalSince(fire) < 2 * 3600 else { return false }
        if let done = danceDoneAt, done >= fire { return false }
        return true
    }
}

enum AlarmScheduler {
    static var manager: AlarmManager { AlarmManager.shared }

    /// Intervalle entre deux relances, et nombre de relances programmées d'avance (15 min).
    static let retryInterval: TimeInterval = 30
    static let chainLength = 30

    static func requestAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .authorized: return true
        case .denied: return false
        default: return (try? await manager.requestAuthorization()) == .authorized
        }
    }

    static func configuration(id: UUID, date: Date, title: LocalizedStringResource)
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
            tintColor: Theme.accent
        )
        let soundID = UserDefaults.standard.string(forKey: "sound") ?? "classique"
        return .alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: OpenDanceIntent(alarmID: id.uuidString),
            sound: .named(Sounds.fileName(for: soundID))
        )
    }

    /// Programme la prochaine sonnerie + ses relances (remplace tout ce qui existait).
    static func arm(_ settings: AppSettings) async throws {
        cancelAll()
        let date = settings.nextAlarmDate()
        let id = UUID()
        _ = try await manager.schedule(
            id: id, configuration: configuration(id: id, date: date, title: "Debout ! Danse pour arrêter"))
        AlarmState.mainID = id
        AlarmState.nextFire = date
        await scheduleChain(from: date.addingTimeInterval(retryInterval), count: chainLength)
    }

    static func disarm() {
        cancelAll()
        AlarmState.nextFire = nil
    }

    /// Ajoute `count` relances, toutes les 30 s à partir de `start`.
    static func scheduleChain(from start: Date, count: Int) async {
        var chain = AlarmState.chain
        for i in 0..<count {
            let id = UUID()
            let date = start.addingTimeInterval(Double(i) * retryInterval)
            let cfg = configuration(id: id, date: date, title: "Pas si vite ! Il faut danser")
            if (try? await manager.schedule(id: id, configuration: cfg)) != nil {
                chain.append(ScheduledAlarm(id: id, date: date))
            }
        }
        AlarmState.chain = chain
    }

    static func cancelChain() {
        for alarm in AlarmState.chain { try? manager.cancel(id: alarm.id) }
        AlarmState.chain = []
    }

    static func cancelAll() {
        if let id = AlarmState.mainID { try? manager.cancel(id: id) }
        AlarmState.mainID = nil
        cancelChain()
    }

    /// Repousse les relances : la prochaine sonnera dans `seconds`.
    static func postponeChain(by seconds: TimeInterval) async {
        cancelChain()
        await scheduleChain(from: Date().addingTimeInterval(seconds), count: chainLength)
    }

    /// S'il reste peu de relances à venir, on en rajoute.
    static func extendChainIfNeeded() async {
        let now = Date()
        let chain = AlarmState.chain
        let future = chain.filter { $0.date > now }
        guard future.count < 4 else { return }
        let last = chain.map(\.date).max() ?? now
        let start = max(last, now).addingTimeInterval(retryInterval)
        await scheduleChain(from: start, count: chainLength - future.count)
    }

    /// À l'ouverture de l'app : programme l'alarme du jour suivant si besoin,
    /// ou désactive une alarme unique déjà passée.
    static func ensureScheduled(_ settings: AppSettings) async {
        guard settings.isArmed, !AlarmState.needsDance else { return }
        if let fire = AlarmState.nextFire, fire > Date() { return }
        if settings.repeatDaily {
            try? await arm(settings)
        } else {
            cancelAll()
            settings.isArmed = false
        }
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
    static var description = IntentDescription("Ouvre Dance Up pour arrêter l'alarme en dansant.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "alarmID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        AlarmScheduler.stopAlerting()
        // Pendant que tu danses, pas de relance avant 3 min. Si tu te rendors, ça repart.
        await AlarmScheduler.postponeChain(by: 180)
        return .result()
    }
}

/// Bouton « Arrêter » (imposé par iOS) : coupe le son, mais les relances
/// déjà programmées font resonner l'alarme toutes les 30 s tant que tu n'as pas dansé.
struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Arrêter"
    static var description = IntentDescription("Arrête la sonnerie. Elle revient tant que tu n'as pas dansé.")

    @Parameter(title: "alarmID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: id) }
        if AlarmState.needsDance { await AlarmScheduler.extendChainIfNeeded() }
        return .result()
    }
}
