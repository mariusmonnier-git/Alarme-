import Foundation
import SwiftUI

enum DanceMode: String, CaseIterable, Identifiable {
    case camera, motion
    var id: String { rawValue }
    var label: String { self == .camera ? "📷 Caméra" : "📱 En main" }
    var hint: String {
        self == .camera
            ? "Pose le téléphone face à toi (à 2 m environ) : la caméra vérifie que tout ton corps bouge."
            : "Tiens le téléphone en main et danse : bras, hanches, sauts… il faut que ça secoue !"
    }
}

struct AlarmSound: Identifiable, Hashable {
    let id: String
    let label: String
    let file: String
}

/// Sonneries intégrées + musique perso (copiée dans Library/Sounds pour qu'AlarmKit la trouve).
enum Sounds {
    static let builtIn: [AlarmSound] = [
        .init(id: "classique", label: "🔔 Classique", file: "classique.wav"),
        .init(id: "bipbip", label: "⌚ Bip-bip", file: "bipbip.wav"),
        .init(id: "sirene", label: "🚨 Sirène", file: "sirene.wav"),
        .init(id: "disco", label: "🪩 Disco", file: "disco.wav"),
        .init(id: "cocorico", label: "🐓 Cocorico", file: "cocorico.wav"),
    ]
    static let customID = "custom"
    static let customFile = "danse-reveil-custom.caf"

    static var soundsDir: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }
    static var customURL: URL { soundsDir.appendingPathComponent(customFile) }
    static var hasCustom: Bool { FileManager.default.fileExists(atPath: customURL.path) }

    /// Nom de fichier passé à AlarmKit.
    static func fileName(for id: String) -> String {
        if id == customID, hasCustom { return customFile }
        return builtIn.first { $0.id == id }?.file ?? "classique.wav"
    }

    /// Fichier joué dans l'app pendant la danse.
    static func url(for id: String) -> URL? {
        if id == customID, hasCustom { return customURL }
        let file = builtIn.first { $0.id == id }?.file ?? "classique.wav"
        return Bundle.main.url(forResource: file, withExtension: nil)
    }
}

/// Réglages de l'utilisateur, sauvegardés automatiquement.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var alarmTime: Date { didSet { d.set(alarmTime, forKey: "alarmTime") } }
    @Published var repeatDaily: Bool { didSet { d.set(repeatDaily, forKey: "repeatDaily") } }
    @Published var duration: Int { didSet { d.set(duration, forKey: "duration") } }
    @Published var mode: DanceMode { didSet { d.set(mode.rawValue, forKey: "mode") } }
    @Published var sound: String { didSet { d.set(sound, forKey: "sound") } }
    @Published var customName: String { didSet { d.set(customName, forKey: "customName") } }
    @Published var isArmed: Bool { didSet { d.set(isArmed, forKey: "isArmed") } }

    private init() {
        let seven = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
        alarmTime = d.object(forKey: "alarmTime") as? Date ?? seven
        repeatDaily = d.object(forKey: "repeatDaily") as? Bool ?? true
        duration = d.object(forKey: "duration") as? Int ?? 30
        mode = DanceMode(rawValue: d.string(forKey: "mode") ?? "") ?? .camera
        sound = d.string(forKey: "sound") ?? "classique"
        customName = d.string(forKey: "customName") ?? ""
        isArmed = d.bool(forKey: "isArmed")
    }

    var hour: Int { Calendar.current.component(.hour, from: alarmTime) }
    var minute: Int { Calendar.current.component(.minute, from: alarmTime) }

    /// Prochaine sonnerie (aujourd'hui ou demain).
    func nextAlarmDate(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        var date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if date <= now { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
        return date
    }
}
