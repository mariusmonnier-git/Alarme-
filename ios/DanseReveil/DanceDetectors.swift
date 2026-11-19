import AVFoundation
import CoreMotion
import Foundation
import Vision

/// Détecte la danse avec la caméra frontale (posture du corps via Vision).
final class CameraDanceDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    let session = AVCaptureSession()
    /// (énergie, corps visible) — appelé sur le thread principal.
    var onUpdate: ((Double, Bool) -> Void)?

    private let queue = DispatchQueue(label: "dansereveil.camera")
    private var prev: [Joint: CGPoint] = [:]
    private var energy = 0.0
    private var lastFrame = Date.distantPast

    /// Parties du corps suivies : il faut en bouger plusieurs (pas juste agiter une main).
    private static let groups: [[Joint]] = [
        [.leftElbow, .leftWrist], [.rightElbow, .rightWrist],
        [.leftKnee, .leftAnkle], [.rightKnee, .rightAnkle],
        [.leftHip, .rightHip], [.nose],
    ]

    func start(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.queue.async {
                let ok = self.configure()
                if ok { self.session.startRunning() }
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    func stop() {
        queue.async {
            self.session.stopRunning()
            self.prev = [:]
            self.energy = 0
        }
    }

    private func configure() -> Bool {
        if !session.inputs.isEmpty { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        if let c = output.connection(with: .video), c.isVideoRotationAngleSupported(90) {
            c.videoRotationAngle = 90  // images en portrait
        }
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastFrame) >= 1.0 / 15 else { return }  // ~15 analyses/s
        lastFrame = now

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        try? handler.perform([request])

        guard let observation = request.results?.first,
              let points = try? observation.recognizedPoints(.all) else {
            lost()
            return
        }
        var cur: [Joint: CGPoint] = [:]
        for (joint, p) in points where p.confidence > 0.3 { cur[joint] = p.location }

        // Taille du torse pour normaliser selon la distance à la caméra.
        func dist(_ a: Joint, _ b: Joint) -> Double? {
            guard let p = cur[a], let q = cur[b] else { return nil }
            return hypot(p.x - q.x, p.y - q.y)
        }
        guard let torsoRaw = dist(.neck, .root) ?? dist(.leftShoulder, .leftHip) ?? dist(.rightShoulder, .rightHip)
        else {
            lost()
            return
        }
        let torso = max(0.05, torsoRaw)

        if !prev.isEmpty {
            var total = 0.0
            var moving = 0
            for group in Self.groups {
                var s = 0.0
                for j in group {
                    if let a = cur[j], let b = prev[j] { s += hypot(a.x - b.x, a.y - b.y) / torso }
                }
                s /= Double(group.count)
                if s > 0.05 { moving += 1 }
                total += s
            }
            let raw = moving >= 3 ? total * 3 : total * 0.75
            energy = energy * 0.72 + min(1.5, raw) * 0.28
        }
        prev = cur
        report(true)
    }

    private func lost() {
        energy *= 0.8
        prev = [:]
        report(false)
    }

    private func report(_ visible: Bool) {
        let e = energy
        DispatchQueue.main.async { self.onUpdate?(e, visible) }
    }
}

/// Détecte la danse avec l'accéléromètre (téléphone en main).
final class MotionDanceDetector {
    private let manager = CMMotionManager()
    private var smooth = 0.0
    /// Énergie de 0 à 1,5 — appelé sur le thread principal.
    var onUpdate: ((Double) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        smooth = 0
        manager.deviceMotionUpdateInterval = 1.0 / 50
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let a = motion?.userAcceleration else { return }
            let mag = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() * 9.81  // m/s², sans la gravité
            self.smooth = self.smooth * 0.9 + mag * 0.1
            self.onUpdate?(min(1.5, self.smooth / 6))  // ~6 m/s² de secousses = danse franche
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
