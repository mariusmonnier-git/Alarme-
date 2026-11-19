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

    /// Au-delà, une alarme qui n'a pas été suivie d'une danse est considérée comme ratée.
    static let missedAfter: TimeInterval = 3 * 3600

    static var mainID: UUID? {
        get { d.string(forKey: "mainAlarmID").flatMap(UUID.init(uuidString:)) }
        set { d.set(newValue?.uuidString, forKey: "mainAlarmID") }
    }

    /// Heure de la prochaine (ou dernière) sonnerie principale.
    static var nextFire: Date? {
        get { d.object(forKey: "nextFire") as? Date }
        set { d.set(newValue, forKey: "nextFire") }
    }

    /// Relances programmées (sert seulement à savoir combien il en reste à venir).
    static var chain: [ScheduledAlarm] {
        get {
            guard let data = d.data(forKey: "alarmChain") else { return [] }
            return (try? JSONDecoder().decode([ScheduledAlarm].self, from: data)) ?? []
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "alarmChain") }
    }

    /// Première sonnerie constatée et pas encore suivie d'une danse validée.
    static var ringingSince: Date? {
        get { d.object(forKey: "ringingSince") as? Date }
        set { d.set(newValue, forKey: "ringingSince") }
    }

    /// Le bouton « Danser » a été touché (l'app doit s'ouvrir sur la danse).
    static var danceRequestedAt: Date? {
        get { d.object(forKey: "danceRequestedAt") as? Date }
        set { d.set(newValue, forKey: "danceRequestedAt") }
    }

    static var danceDoneAt: Date? {
        get { d.object(forKey: "danceDoneAt") as? Date }
        set { d.set(newValue, forKey: "danceDoneAt") }
    }

    /// Note qu'une alarme a sonné (garde la première sonnerie de la série).
    static func markRinging(at date: Date = Date()) {
        if !needsDance { ringingSince = date }
    }

    /// Une alarme a sonné et la danse n'est pas encore validée.
    /// Ne dépend PAS de l'alarme activée/désactivée : impossible d'y échapper en désactivant.
    static var needsDance: Bool {
        let now = Date()
        var candidates: [Date] = []
        if let since = ringingSince { candidates.append(since) }
        // La sonnerie principale est passée, même si personne n'a touché l'alarme.
        if d.bool(forKey: "isArmed"), let fire = nextFire, fire <= now { candidates.append(fire) }
        guard let since = candidates.max(), now.timeIntervalSince(since) < missedAfter else { return false }
        if let done = danceDoneAt, done >= since { return false }
        return true
    }
}

/// Exécute les reprogrammations l'une après l'autre (jamais deux en même temps).
actor SchedulerQueue {
    static let shared = SchedulerQueue()
    private var tail: Task<Void, Never>?

    func run(_ operation: @escaping () async -> Void) async {
        let previous = tail
        let task = Task {
            await previous?.value
            await operation()
        }
        tail = task
        await task.value
    }
}

enum AlarmSchedulerError: LocalizedError {
    case appExpires(Date)
    var errorDescription: String? {
        switch self {
        case .appExpires(let date):
            return "L'app expire le \(date.formatted(date: .abbreviated, time: .shortened)). Réinstalle-la avec Sideloadly avant, sinon tu ne pourras pas danser pour arrêter l'alarme."
        }
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

    /// Toutes les alarmes de l'app connues d'iOS (y compris d'éventuelles relances « perdues »).
    static var allAlarms: [Alarm] { (try? manager.alarms) ?? [] }

    static var isAlerting: Bool { allAlarms.contains { $0.state == .alerting } }

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
        let date = settings.nextAlarmDate()
        if let expiry = Provisioning.expirationDate, date >= expiry {
            throw AlarmSchedulerError.appExpires(expiry)
        }
        var failure: Error?
        await SchedulerQueue.shared.run {
            cancelEverything()
            let id = UUID()
            do {
                _ = try await manager.schedule(
                    id: id, configuration: configuration(id: id, date: date, title: "Debout ! Danse pour arrêter"))
                AlarmState.mainID = id
                AlarmState.nextFire = date
                await scheduleChain(from: date.addingTimeInterval(retryInterval), count: chainLength)
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
    }

    static func disarm() {
        cancelEverything()
        AlarmState.nextFire = nil
    }

    /// Annule absolument toutes les alarmes de l'app, sans se fier aux identifiants enregistrés.
    static func cancelEverything() {
        for alarm in allAlarms { try? manager.cancel(id: alarm.id) }
        AlarmState.mainID = nil
        AlarmState.chain = []
    }

    /// Annule toutes les relances, mais garde la sonnerie principale si elle est encore à venir.
    static func cancelRelances() {
        let keep = (AlarmState.nextFire.map { $0 > Date() } ?? false) ? AlarmState.mainID : nil
        for alarm in allAlarms where alarm.id != keep { try? manager.cancel(id: alarm.id) }
        AlarmState.chain = []
    }

    /// Ajoute `count` relances, toutes les 30 s à partir de `start`.
    private static func scheduleChain(from start: Date, count: Int) async {
        var added: [ScheduledAlarm] = []
        for i in 0..<count {
            let id = UUID()
            let date = start.addingTimeInterval(Double(i) * retryInterval)
            let cfg = configuration(id: id, date: date, title: "Pas si vite ! Il faut danser")
            if (try? await manager.schedule(id: id, configuration: cfg)) != nil {
                added.append(ScheduledAlarm(id: id, date: date))
            }
        }
        AlarmState.chain = AlarmState.chain + added  // relu juste avant d'écrire : on ajoute, on n'écrase pas
    }

    /// Repousse les relances : la prochaine sonnera dans `seconds`.
    static func postponeChain(by seconds: TimeInterval) async {
        await SchedulerQueue.shared.run {
            cancelRelances()
            await scheduleChain(from: Date().addingTimeInterval(seconds), count: chainLength)
        }
    }

    /// S'il reste peu de relances à venir, on en rajoute.
    static func extendChainIfNeeded() async {
        await SchedulerQueue.shared.run {
            let now = Date()
            let chain = AlarmState.chain
            let future = chain.filter { $0.date > now }
            guard future.count < 4 else { return }
            let last = chain.map(\.date).max() ?? now
            await scheduleChain(from: max(last, now).addingTimeInterval(retryInterval), count: chainLength - future.count)
        }
    }

    /// À l'ouverture de l'app : nettoie et reprogramme ce qu'il faut.
    static func ensureScheduled(_ settings: AppSettings) async {
        guard !AlarmState.needsDance else { return }
        guard settings.isArmed else {
            // Alarme désactivée et pas de danse due : aucune alarme ne doit rester.
            if !allAlarms.isEmpty { cancelEverything() }
            return
        }
        if let fire = AlarmState.nextFire, fire > Date() { return }
        // La sonnerie est passée (danse faite, ou ratée depuis plus de 3 h).
        if settings.repeats {
            do { try await arm(settings) } catch { disarmAndForget(settings) }
        } else {
            disarmAndForget(settings)
        }
    }

    private static func disarmAndForget(_ settings: AppSettings) {
        disarm()
        settings.isArmed = false
    }

    /// Coupe le son système des alarmes en cours (l'app prend le relais).
    static func stopAlerting() {
        for alarm in allAlarms where alarm.state == .alerting {
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
        AlarmState.markRinging()
        AlarmState.danceRequestedAt = Date()
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
        AlarmState.markRinging()
        await AlarmScheduler.extendChainIfNeeded()
        return .result()
    }
}
