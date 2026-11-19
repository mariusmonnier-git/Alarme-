import AudioToolbox
import Foundation
import SwiftUI
import UIKit

/// Gère une sonnerie en cours : son, détection de danse, progression.
@MainActor
final class RingController: ObservableObject {
    static let shared = RingController()

    enum Phase { case idle, ringing, done }

    @Published var phase: Phase = .idle
    @Published var progress = 0.0
    @Published var energy = 0.0
    @Published var message = ""
    @Published var mode: DanceMode = .camera
    @Published var target = 30
    @Published var doneText = ""

    static let threshold = 0.35

    let camera = CameraDanceDetector()
    private let motion = MotionDanceDetector()
    private var timer: Timer?
    private var lastTick = Date()
    private var startedAt = Date()
    private var lastVibe = Date.distantPast
    private var lostSince: Date?
    private var ready = false
    private var isTest = false

    private static let encouragements = [
        "Bouge plus", "Plus fort", "Lève les bras", "Continue",
        "Garde le rythme", "Presque fini",
    ]

    /// À appeler quand l'app s'ouvre : reprend la danse si l'alarme a sonné.
    func resumeIfNeeded() {
        if AlarmState.needsDance && phase != .ringing { start() }
    }

    func start(test: Bool = false) {
        guard phase != .ringing else { return }
        let settings = AppSettings.shared
        isTest = test
        target = settings.duration
        mode = settings.mode
        progress = 0
        energy = 0
        ready = false
        lostSince = nil
        startedAt = Date()
        lastTick = Date()
        phase = .ringing
        UIApplication.shared.isIdleTimerDisabled = true

        if !test {
            AlarmScheduler.stopAlerting()
            // Pendant la danse, les relances sont repoussées à 3 min (si tu quittes l'app, ça resonne).
            Task { await AlarmScheduler.postponeChain(by: 180) }
        }
        SoundPlayer.shared.start(soundID: settings.sound)
        startDetector()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func switchToMotion(_ msg: String? = nil) {
        camera.stop()
        mode = .motion
        ready = false
        lostSince = nil
        startMotion()
        if let msg { message = msg }
    }

    private func startDetector() {
        if mode == .camera {
            message = "Démarrage de la caméra…"
            camera.onUpdate = { [weak self] e, visible in
                Task { @MainActor in self?.cameraUpdate(e, visible) }
            }
            camera.start { [weak self] ok in
                Task { @MainActor in
                    guard let self, self.phase == .ringing, self.mode == .camera else { return }
                    if ok { self.ready = true } else {
                        self.switchToMotion("Caméra indisponible : danse téléphone en main")
                    }
                }
            }
        } else {
            startMotion()
        }
    }

    private func startMotion() {
        message = "Danse avec le téléphone en main"
        guard motion.isAvailable else {
            message = "Capteurs de mouvement indisponibles"
            return
        }
        motion.onUpdate = { [weak self] e in
            Task { @MainActor in
                guard let self, self.mode == .motion else { return }
                self.ready = true
                self.energy = e
            }
        }
        motion.start()
    }

    private func cameraUpdate(_ e: Double, _ visible: Bool) {
        guard mode == .camera else { return }
        energy = e
        if visible { lostSince = nil } else if lostSince == nil { lostSince = Date() }
    }

    private func tick() {
        guard phase == .ringing else { return }
        let now = Date()
        let dt = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now

        let dancing = energy >= Self.threshold
        if ready {
            if dancing { progress += dt } else { progress = max(0, progress - dt * 0.5) }  // on perd si on s'arrête
        }

        if let lost = lostSince, now.timeIntervalSince(lost) > 0.8 {
            message = "Recule-toi : on ne te voit pas"
        } else if ready {
            let pct = min(1, progress / Double(target))
            let idx = dancing ? 1 + Int(pct * Double(Self.encouragements.count - 2)) : 0
            message = Self.encouragements[min(idx, Self.encouragements.count - 1)]
        }

        // Le son baisse quand tu danses bien (récompense), sans jamais se couper.
        SoundPlayer.shared.setVolume(dancing ? 0.35 : 1)
        if now.timeIntervalSince(lastVibe) > 1.5 {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            lastVibe = now
        }
        if progress >= Double(target) { finish() }
    }

    private func finish() {
        stopEverything()
        let secs = Int(Date().timeIntervalSince(startedAt))
        doneText = "Alarme arrêtée en \(secs / 60) min \(String(format: "%02d", secs % 60)) s"
        if !isTest {
            AlarmState.danceDoneAt = Date()
            AlarmScheduler.cancelChain()
            AlarmScheduler.stopAlerting()
            let settings = AppSettings.shared
            if settings.repeatDaily {
                Task { try? await AlarmScheduler.arm(settings) }  // alarme de demain
            } else {
                AlarmScheduler.disarm()
                settings.isArmed = false
            }
        }
        phase = .done
    }

    /// Uniquement pour le mode test.
    func cancelTest() {
        guard isTest else { return }
        stopEverything()
        phase = .idle
    }

    var canCancel: Bool { isTest }

    private func stopEverything() {
        timer?.invalidate()
        timer = nil
        camera.stop()
        motion.stop()
        SoundPlayer.shared.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
