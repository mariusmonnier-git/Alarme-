import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ring: RingController
    @State private var errorText: String?
    @State private var busy = false

    private var armBinding: Binding<Bool> {
        Binding(get: { settings.isArmed }, set: { setArmed($0) })
    }

    private var soundName: String {
        if settings.sound == Sounds.customID, Sounds.hasCustom { return settings.customName }
        return Sounds.builtIn.first { $0.id == settings.sound }?.label ?? "Classique"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 18) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 110)
                            .rotationEffect(.degrees(settings.isArmed ? -6 : 0))
                            .animation(.spring(duration: 0.5, bounce: 0.6), value: settings.isArmed)
                        AlarmHeader()
                        Button(settings.isArmed ? "Désactiver" : "Activer l'alarme") {
                            setArmed(!settings.isArmed)
                        }
                        .buttonStyle(PillButtonStyle(filled: !settings.isArmed))
                        .disabled(busy)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                if let expiry = Provisioning.expirationDate, expiry.timeIntervalSinceNow < 3 * 86400 {
                    Section {
                        Label(
                            expiry < Date()
                                ? "L'app a expiré : réinstalle-la avec Sideloadly."
                                : "Réinstalle l'app avec Sideloadly avant le \(expiry.formatted(date: .abbreviated, time: .shortened)), sinon l'alarme ne pourra plus être arrêtée en dansant.",
                            systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.accent)
                            .font(.subheadline.weight(.semibold))
                    }
                }

                Section {
                    DatePicker("Heure", selection: $settings.alarmTime, displayedComponents: .hourAndMinute)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Jours")
                        WeekdayPicker(selection: $settings.weekdays)
                        Text(settings.daysSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    if !settings.weekdays.isEmpty {
                        Toggle("Répéter chaque semaine", isOn: $settings.repeatWeekly)
                    }
                    NavigationLink {
                        SoundListView()
                    } label: {
                        LabeledContent("Sonnerie", value: soundName)
                    }
                }

                Section {
                    Picker("Durée de danse", selection: $settings.duration) {
                        Text("15 s").tag(15)
                        Text("30 s").tag(30)
                        Text("1 min").tag(60)
                    }
                    Picker("Détection", selection: $settings.mode) {
                        ForEach(DanceMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.symbol).tag(mode)
                        }
                    }
                } footer: {
                    Text(settings.mode.hint)
                }

                Section {
                    Button {
                        SoundPlayer.shared.stop()
                        ring.start(test: true)
                    } label: {
                        Label("Tester l'alarme", systemImage: "figure.dance")
                            .fontWeight(.bold)
                    }
                } footer: {
                    Text("L'alarme sonne même iPhone verrouillé et en mode silencieux. Si tu l'arrêtes sans danser, elle revient toutes les 30 secondes.")
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .toolbar(.hidden, for: .navigationBar)
        }
        // Si on change un réglage alors que l'alarme est active, on la reprogramme.
        .onChange(of: settings.alarmTime) { _, _ in rearmIfNeeded() }
        .onChange(of: settings.weekdays) { _, _ in rearmIfNeeded() }
        .onChange(of: settings.repeatWeekly) { _, _ in rearmIfNeeded() }
        .onChange(of: settings.sound) { _, _ in rearmIfNeeded() }
    }

    private func setArmed(_ on: Bool) {
        errorText = nil
        guard on else {
            // Impossible de désactiver entre la première sonnerie et la danse validée.
            if AlarmState.needsDance {
                ring.resumeIfNeeded()
                return
            }
            AlarmScheduler.disarm()
            settings.isArmed = false
            return
        }
        busy = true
        Task {
            defer { busy = false }
            guard await AlarmScheduler.requestAuthorization() else {
                errorText = "Autorise les alarmes dans Réglages › Dance Up."
                return
            }
            if settings.mode == .camera { _ = await AVCaptureDevice.requestAccess(for: .video) }
            do {
                try await AlarmScheduler.arm(settings)
                settings.isArmed = true
            } catch {
                errorText = "Impossible de programmer l'alarme : \(error.localizedDescription)"
            }
        }
    }

    private func rearmIfNeeded() {
        guard settings.isArmed, !AlarmState.needsDance else { return }
        Task {
            do { try await AlarmScheduler.arm(settings) } catch {
                errorText = "Impossible de reprogrammer l'alarme : \(error.localizedDescription)"
            }
        }
    }
}

/// En-tête : compte à rebours jusqu'au réveil si l'alarme est active, sinon l'heure réglée.
struct AlarmHeader: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 2) {
            if settings.isArmed {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let target = nextFire(after: context.date)
                    let remaining = max(0, Int(target.timeIntervalSince(context.date)))
                    let days = remaining / 86400
                    let rest = remaining % 86400
                    let clock = String(format: "%02d:%02d:%02d", rest / 3600, (rest % 3600) / 60, rest % 60)
                    VStack(spacing: 2) {
                        Text(days > 0 ? "\(days) j \(clock)" : clock)
                            .font(.system(size: 60, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(Theme.accent)
                        Text("de dodo avant " + [dayLabel(target), target.formatted(date: .omitted, time: .shortened)]
                            .filter { !$0.isEmpty }.joined(separator: " "))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(settings.alarmTime.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.35))
                Text("Alarme désactivée · \(settings.daysSummary)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// « » aujourd'hui, « demain », sinon le jour abrégé (« mer. »).
    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "" }
        if cal.isDateInTomorrow(date) { return "demain" }
        return AppSettings.dayNames[cal.component(.weekday, from: date)] ?? ""
    }

    private func nextFire(after now: Date) -> Date {
        if let fire = AlarmState.nextFire, fire > now { return fire }
        return settings.nextAlarmDate(from: now)
    }
}

/// Choix de la sonnerie, façon Réglages › Sons.
struct SoundListView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showImporter = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(Sounds.builtIn) { sound in
                    row(id: sound.id, label: sound.label, symbol: sound.symbol)
                }
            }
            Section {
                if Sounds.hasCustom, !settings.customName.isEmpty {
                    row(id: Sounds.customID, label: settings.customName, symbol: "music.note")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Choisir une musique…", systemImage: "plus")
                }
            } header: {
                Text("Ma musique")
            } footer: {
                Text("Les 30 premières secondes du morceau sont utilisées, c'est la limite d'iOS pour une alarme.")
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Sonnerie")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            importSound(result)
        }
        .onDisappear { SoundPlayer.shared.stop() }
    }

    private func row(id: String, label: String, symbol: String) -> some View {
        Button {
            settings.sound = id
            SoundPlayer.shared.preview(soundID: id)
        } label: {
            HStack {
                Label(label, systemImage: symbol)
                    .foregroundStyle(.primary)
                Spacer()
                if settings.sound == id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func importSound(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        do {
            let alreadyCustom = settings.sound == Sounds.customID
            settings.customName = try CustomSoundImporter.importSound(from: url)
            settings.sound = Sounds.customID
            // Si la musique perso était déjà choisie, onChange ne se déclenche pas : on reprogramme nous-mêmes
            // pour que l'alarme utilise le nouveau fichier.
            if alreadyCustom, settings.isArmed, !AlarmState.needsDance {
                Task { try? await AlarmScheduler.arm(settings) }
            }
            SoundPlayer.shared.preview(soundID: Sounds.customID)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Rangée de pastilles L M M J V S D, comme dans l'app Horloge.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppSettings.weekOrder, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(AppSettings.dayLetters[day] ?? "")
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .foregroundStyle(on ? Theme.ink : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(on ? Theme.accent : Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
