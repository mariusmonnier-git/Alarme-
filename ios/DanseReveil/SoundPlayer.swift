import AVFoundation
import Foundation

/// Joue la sonnerie dans l'app (pendant la danse et pour les aperçus).
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var player: AVAudioPlayer?
    private var previewToken = UUID()
    private var volume: Float = 1

    func start(soundID: String, preview: Bool = false) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        guard let url = Sounds.url(for: soundID) ?? Sounds.url(for: "classique"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.numberOfLoops = -1
        p.volume = preview ? 0.8 : 0.25
        p.play()
        // Le volume monte jusqu'au maximum en 20 s.
        if !preview { p.setVolume(1, fadeDuration: 20) }
        volume = 1
        player = p
    }

    /// Écoute 5 secondes d'une sonnerie.
    func preview(soundID: String) {
        start(soundID: soundID, preview: true)
        let token = UUID()
        previewToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.previewToken == token { self?.stop() }
        }
    }

    func setVolume(_ v: Float) {
        guard v != volume else { return }
        volume = v
        player?.setVolume(v, fadeDuration: 0.4)
    }

    func stop() {
        previewToken = UUID()
        player?.stop()
        player = nil
    }

    var isPlaying: Bool { player?.isPlaying ?? false }
}

enum CustomSoundError: LocalizedError {
    case unreadable
    var errorDescription: String? { "Ce fichier audio n'est pas lisible. Essaie un MP3 ou un M4A." }
}

enum CustomSoundImporter {
    /// Convertit le fichier choisi en .caf (30 s max, limite d'iOS pour les sons d'alarme)
    /// et le range dans Library/Sounds. Renvoie le nom à afficher.
    static func importSound(from url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        try fm.createDirectory(at: Sounds.soundsDir, withIntermediateDirectories: true)

        guard let input = try? AVAudioFile(forReading: url) else { throw CustomSoundError.unreadable }
        let format = input.processingFormat
        let maxFrames = AVAudioFramePosition(format.sampleRate * 29)
        let frames = AVAudioFrameCount(min(input.length, maxFrames))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw CustomSoundError.unreadable
        }
        try input.read(into: buffer, frameCount: frames)

        let tmp = Sounds.soundsDir.appendingPathComponent("import-tmp.caf")
        try? fm.removeItem(at: tmp)
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            let output = try AVAudioFile(
                forWriting: tmp, settings: settings, commonFormat: format.commonFormat,
                interleaved: format.isInterleaved)
            try output.write(from: buffer)
        }  // le fichier est fermé ici
        try? fm.removeItem(at: Sounds.customURL)
        try fm.moveItem(at: tmp, to: Sounds.customURL)
        return String(url.deletingPathExtension().lastPathComponent.prefix(30))
    }
}
