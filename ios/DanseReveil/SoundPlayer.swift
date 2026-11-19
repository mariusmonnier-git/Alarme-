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
    /// Convertit le fichier choisi au même format que les sonneries intégrées (WAV 44,1 kHz mono 16 bits,
    /// 29 s max : limite d'iOS pour un son d'alarme) et le range dans Library/Sounds sous un nom NOUVEAU
    /// à chaque fois, pour qu'iOS ne réutilise pas l'ancien son. Renvoie le nom à afficher.
    static func importSound(from url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        try fm.createDirectory(at: Sounds.soundsDir, withIntermediateDirectories: true)

        // 1. Lecture des 29 premières secondes.
        guard let input = try? AVAudioFile(forReading: url) else { throw CustomSoundError.unreadable }
        let inFormat = input.processingFormat
        let frames = AVAudioFrameCount(min(input.length, AVAudioFramePosition(inFormat.sampleRate * 29)))
        guard frames > 0, let source = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else {
            throw CustomSoundError.unreadable
        }
        try input.read(into: source, frameCount: frames)

        // 2. Conversion en 44,1 kHz mono.
        guard let outFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else { throw CustomSoundError.unreadable }
        converter.downmix = true
        let capacity = AVAudioFrameCount(Double(frames) * 44100 / inFormat.sampleRate) + 4096
        guard let converted = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
            throw CustomSoundError.unreadable
        }
        var fed = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            if fed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error, conversionError == nil, converted.frameLength > 0 else { throw CustomSoundError.unreadable }

        // 3. Écriture en WAV 16 bits sous un nouveau nom.
        let fileName = "custom-\(Int(Date().timeIntervalSince1970)).wav"
        let destination = Sounds.soundsDir.appendingPathComponent(fileName)
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            let output = try AVAudioFile(
                forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try output.write(from: converted)
        }  // le fichier est fermé ici

        // 4. On supprime les anciennes musiques et on retient la nouvelle.
        let old = (try? fm.contentsOfDirectory(atPath: Sounds.soundsDir.path)) ?? []
        for name in old where name != fileName && (name.hasPrefix("custom-") || name.hasPrefix("danse-reveil-custom")) {
            try? fm.removeItem(at: Sounds.soundsDir.appendingPathComponent(name))
        }
        Sounds.customFile = fileName
        return String(url.deletingPathExtension().lastPathComponent.prefix(30))
    }
}
