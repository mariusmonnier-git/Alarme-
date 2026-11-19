import Foundation
import SwiftUI

enum DanceMode: String, CaseIterable, Identifiable {
    case camera, motion
    var id: String { rawValue }
    var label: String { self == .camera ? "Caméra" : "Téléphone en main" }
    var symbol: String { self == .camera ? "camera" : "iphone.radiowaves.left.and.right" }
    var hint: String {
        self == .camera
            ? "Pose l'iPhone face à toi, à environ 2 mètres. La caméra vérifie que tout ton corps bouge."
            : "Tiens l'iPhone en main et danse. Il faut que ça bouge franchement."
    }
}

struct AlarmSound: Identifiable, Hashable {
    let id: String
    let label: String
    let file: String
    var symbol: String = "bell"
}

/// Sonneries intégrées + musique perso (copiée dans Library/Sounds pour qu'AlarmKit la trouve).
enum Sounds {
    static let builtIn: [AlarmSound] = [
        .init(id: "classique", label: "Classique", file: "classique.wav", symbol: "bell"),
        .init(id: "bipbip", label: "Bip-bip", file: "bipbip.wav", symbol: "applewatch"),
        .init(id: "sirene", label: "Sirène", file: "sirene.wav", symbol: "light.beacon.max"),
        .init(id: "disco", label: "Disco", file: "disco.wav", symbol: "music.quarternote.3"),
        .init(id: "cocorico", label: "Cocorico", file: "cocorico.wav", symbol: "sunrise"),
    ]
    static let customID = "custom"

    static var soundsDir: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// Nom du fichier de la musique perso. Il change à chaque import pour qu'iOS ne garde pas l'ancien en cache.
    static var customFile: String? {
        get { UserDefaults.standard.string(forKey: "customFile") }
        set { UserDefaults.standard.set(newValue, forKey: "customFile") }
    }
    static var customURL: URL? { customFile.map { soundsDir.appendingPathComponent($0) } }
    static var hasCustom: Bool { customURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    /// Nom de fichier passé à AlarmKit.
    static func fileName(for id: String) -> String {
        if id == customID, hasCustom, let file = customFile { return file }
        return builtIn.first { $0.id == id }?.file ?? "classique.wav"
    }

    /// Fichier joué dans l'app pendant la danse.
    static func url(for id: String) -> URL? {
        if id == customID, hasCustom, let url = customURL { return url }
        let file = builtIn.first { $0.id == id }?.file ?? "classique.wav"
        return Bundle.main.url(forResource: file, withExtension: nil)
    }
}

/// Réglages de l'utilisateur, sauvegardés automatiquement.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    /// Ordre d'affichage des jours (lundi → dimanche), au format `Calendar` (1 = dimanche … 7 = samedi).
    static let weekOrder = [2, 3, 4, 5, 6, 7, 1]
    static let dayLetters = [2: "L", 3: "M", 4: "M", 5: "J", 6: "V", 7: "S", 1: "D"]
    static let dayNames = [2: "lun.", 3: "mar.", 4: "mer.", 5: "jeu.", 6: "ven.", 7: "sam.", 1: "dim."]

    @Published var alarmTime: Date { didSet { d.set(alarmTime, forKey: "alarmTime") } }
    /// Jours cochés. Vide = une seule fois, aujourd'hui ou demain.
    @Published var weekdays: Set<Int> { didSet { d.set(Array(weekdays), forKey: "weekdays") } }
    @Published var repeatWeekly: Bool { didSet { d.set(repeatWeekly, forKey: "repeatWeekly") } }
    @Published var duration: Int { didSet { d.set(duration, forKey: "duration") } }
    @Published var mode: DanceMode { didSet { d.set(mode.rawValue, forKey: "mode") } }
    @Published var sound: String { didSet { d.set(sound, forKey: "sound") } }
    @Published var customName: String { didSet { d.set(customName, forKey: "customName") } }
    @Published var isArmed: Bool { didSet { d.set(isArmed, forKey: "isArmed") } }

    private init() {
        let seven = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
        alarmTime = d.object(forKey: "alarmTime") as? Date ?? seven
        if let saved = d.array(forKey: "weekdays") as? [Int] {
            weekdays = Set(saved)
        } else {
            // Ancienne version : « Tous les jours » activé par défaut.
            let daily = d.object(forKey: "repeatDaily") as? Bool ?? true
            weekdays = daily ? Set(1...7) : []
        }
        repeatWeekly = d.object(forKey: "repeatWeekly") as? Bool ?? true
        duration = d.object(forKey: "duration") as? Int ?? 30
        mode = DanceMode(rawValue: d.string(forKey: "mode") ?? "") ?? .camera
        sound = d.string(forKey: "sound") ?? "classique"
        customName = d.string(forKey: "customName") ?? ""
        isArmed = d.bool(forKey: "isArmed")
    }

    var hour: Int { Calendar.current.component(.hour, from: alarmTime) }
    var minute: Int { Calendar.current.component(.minute, from: alarmTime) }

    /// L'alarme se reprogramme toute seule après chaque réveil.
    var repeats: Bool { !weekdays.isEmpty && repeatWeekly }

    /// Prochaine sonnerie : le prochain jour coché (7 jours max), ou aujourd'hui/demain si aucun jour.
    func nextAlarmDate(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        for offset in 0...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: now),
                  let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  date > now else { continue }
            if weekdays.isEmpty || weekdays.contains(cal.component(.weekday, from: date)) { return date }
        }
        return now.addingTimeInterval(86400)
    }

    /// Sonneries à programmer : la prochaine, plus (si répétition) toutes celles des 7 jours suivants.
    func upcomingAlarmDates(from now: Date = Date()) -> [Date] {
        let first = nextAlarmDate(from: now)
        guard repeats else { return [first] }
        let cal = Calendar.current
        var dates: [Date] = []
        for offset in 0...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: now),
                  let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  date > now, date.timeIntervalSince(now) <= 7 * 86400,
                  weekdays.contains(cal.component(.weekday, from: date)) else { continue }
            dates.append(date)
        }
        return dates.isEmpty ? [first] : dates
    }

    var daysSummary: String {
        if weekdays.isEmpty { return "Une fois" }
        let prefix = repeatWeekly ? "" : "Une fois : "
        if weekdays.count == 7 { return repeatWeekly ? "Tous les jours" : "Une fois, au prochain jour" }
        if weekdays == [2, 3, 4, 5, 6] { return prefix + (repeatWeekly ? "En semaine" : "en semaine") }
        if weekdays == [1, 7] { return prefix + (repeatWeekly ? "Le week-end" : "le week-end") }
        let names = Self.weekOrder.filter(weekdays.contains).compactMap { Self.dayNames[$0] }
        return (repeatWeekly ? "Chaque " : prefix) + names.joined(separator: ", ")
    }
}

/// Date d'expiration de l'app installée avec Sideloadly (7 jours avec un identifiant Apple gratuit).
enum Provisioning {
    static let expirationDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>") else { return nil }
        let xml = Data(text[start.lowerBound..<end.upperBound].utf8)
        let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }()
}
