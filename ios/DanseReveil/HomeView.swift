import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ring: RingController
    @State private var showImporter = false
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text("🕺").font(.system(size: 52))
                    Text("Danse Réveil").font(.system(size: 30, weight: .bold))
                    Text("L'alarme ne s'arrête que si tu danses.").foregroundStyle(Theme.muted)
                }
                .padding(.top, 8)

                SleepCountdown()

                card("Heure du réveil") {
                    DatePicker("", selection: $settings.alarmTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .clipped()
                    Toggle("Tous les jours", isOn: $settings.repeatDaily).tint(Theme.pink)
                }

                card("Sonnerie") {
                    SoundPicker(showImporter: $showImporter)
                }

                card("Durée de danse") {
                    Picker("", selection: $settings.duration) {
                        Text("15 s").tag(15)
                        Text("30 s").tag(30)
                        Text("1 min").tag(60)
                    }
                    .pickerStyle(.segmented)
                }

                card("Détection") {
                    Picker("", selection: $settings.mode) {
                        ForEach(DanceMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.mode.hint).font(.footnote).foregroundStyle(Theme.muted)
                }

                Button(action: toggleArm) {
                    Text(settings.isArmed ? "Désactiver l'alarme" : "Activer l'alarme")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(18)
                        .background(settings.isArmed ? AnyShapeStyle(Color.white.opacity(0.12)) : AnyShapeStyle(Theme.gradient))
                        .foregroundStyle(settings.isArmed ? .white : Color(red: 0.1, green: 0.06, blue: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .disabled(busy)

                Button {
                    SoundPlayer.shared.stop()
                    ring.start(test: true)
                } label: {
                    Text("Tester maintenant")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.25)))
                }
                .foregroundStyle(.white)

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.orange).multilineTextAlignment(.center)
                }

                Text("Tu peux verrouiller ton iPhone : l'alarme sonnera même écran éteint et en mode silencieux.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 16)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            importSound(result)
        }
        // Si on change un réglage alors que l'alarme est active, on la reprogramme.
        .onChange(of: settings.alarmTime) { _, _ in rearmIfNeeded() }
        .onChange(of: settings.repeatDaily) { _, _ in rearmIfNeeded() }
        .onChange(of: settings.sound) { _, _ in rearmIfNeeded() }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption).tracking(1).foregroundStyle(Theme.muted)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func toggleArm() {
        errorText = nil
        if settings.isArmed {
            AlarmScheduler.disarm()
            settings.isArmed = false
            return
        }
        busy = true
        Task {
            defer { busy = false }
            guard await AlarmScheduler.requestAuthorization() else {
                errorText = "Autorise les alarmes dans Réglages › Danse Réveil pour que ça marche."
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

/// Compte à rebours jusqu'au réveil : le temps de dodo qu'il reste.
struct SleepCountdown: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let target = settings.nextAlarmDate(from: context.date)
            let remaining = max(0, Int(target.timeIntervalSince(context.date)))
            VStack(spacing: 4) {
                Text(settings.isArmed ? "😴 Temps de dodo restant" : "😴 Si tu actives maintenant")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Text(String(format: "%02d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60))
                    .font(.system(size: 56, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(settings.isArmed ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white))
                Text("Réveil à \(target.formatted(date: .omitted, time: .shortened))"
                     + (settings.isArmed ? " · alarme activée ✅" : ""))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct SoundPicker: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var showImporter: Bool

    private var options: [AlarmSound] {
        var list = Sounds.builtIn
        if Sounds.hasCustom, !settings.customName.isEmpty {
            list.append(.init(id: Sounds.customID, label: "🎵 \(settings.customName)", file: Sounds.customFile))
        }
        return list
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(options) { sound in
                let selected = settings.sound == sound.id
                Button {
                    settings.sound = sound.id
                    SoundPlayer.shared.preview(soundID: sound.id)
                } label: {
                    Text(sound.label)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selected ? Theme.pink : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(selected ? 0 : 0.15)))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(.white)
            }
        }
        Button {
            showImporter = true
        } label: {
            Text("➕ Choisir ma musique")
                .frame(maxWidth: .infinity)
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(.white.opacity(0.3)))
        }
        .foregroundStyle(Theme.muted)
        Button("⏹ Arrêter l'écoute") { SoundPlayer.shared.stop() }
            .font(.footnote)
            .foregroundStyle(Theme.orange)
    }
}
