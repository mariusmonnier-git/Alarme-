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
                    AlarmHeader()
                    Toggle("Alarme activée", isOn: armBinding)
                        .disabled(busy)
                }

                Section {
                    DatePicker("Heure", selection: $settings.alarmTime, displayedComponents: .hourAndMinute)
                    Toggle("Tous les jours", isOn: $settings.repeatDaily)
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
                    Button("Tester l'alarme") {
                        SoundPlayer.shared.stop()
                        ring.start(test: true)
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
            .navigationTitle("Réveil")
        }
        // Si on change un réglage alors que l'alarme est active, on la reprogramme.
        .onChange(of: settings.alarmTime) { _, _ in rearmIfNeeded() }
        .onChange(of: settings.repeatDaily) { _, _ in rearmIfNeeded() }
        .onChange(of: settings.sound) { _, _ in rearmIfNeeded() }
    }

    private func setArmed(_ on: Bool) {
        errorText = nil
        guard on else {
            AlarmScheduler.disarm()
            settings.isArmed = false
            return
        }
        busy = true
        Task {
            defer { busy = false }
            guard await AlarmScheduler.requestAuthorization() else {
                errorText = "Autorise les alarmes dans Réglages › Danse Réveil."
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
        guard settings.isArmed else { return }
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
                    VStack(spacing: 2) {
                        Text(String(format: "%02d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60))
                            .font(.system(size: 64, weight: .thin))
                            .monospacedDigit()
                        Text("avant le réveil à \(target.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                }
            } else {
                Text(settings.alarmTime.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 64, weight: .thin))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("Alarme désactivée")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func importSound(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        do {
            settings.customName = try CustomSoundImporter.importSound(from: url)
            settings.sound = Sounds.customID
            SoundPlayer.shared.preview(soundID: Sounds.customID)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
