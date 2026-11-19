import AVFoundation
import SwiftUI

struct DanceView: View {
    @EnvironmentObject var ring: RingController

    private var dancing: Bool { ring.energy >= RingController.threshold }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if ring.mode == .camera {
                CameraPreview(session: ring.camera.session)
                    .ignoresSafeArea()
            } else {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220)
                    .rotationEffect(.degrees(sin(Date().timeIntervalSince1970 * 8) * ring.energy * 20))
                    .scaleEffect(1 + ring.energy * 0.15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            panel
                .padding(12)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "figure.dance")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(dancing ? Theme.accent : Color.white.opacity(0.35))
                    .symbolEffect(.bounce, value: dancing)
                Text(ring.message)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                Spacer()
            }

            // La musique de l'app suit le volume média : on prévient s'il est trop bas.
            if AVAudioSession.sharedInstance().outputVolume < 0.2 {
                Label("Monte le volume", systemImage: "speaker.wave.3.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(ring.progress))")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
                Text("/ \(ring.target) s")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Progression : grosse barre arrondie orange.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(14, geo.size.width * min(1, ring.progress / Double(ring.target))))
                        .animation(.linear(duration: 0.2), value: ring.progress)
                }
            }
            .frame(height: 14)

            // Énergie du mouvement : verte quand tu bouges assez.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(dancing ? Theme.accent.opacity(0.7) : Color.white.opacity(0.4))
                        .frame(width: geo.size.width * min(1, ring.energy))
                        .animation(.linear(duration: 0.15), value: ring.energy)
                }
            }
            .frame(height: 4)

            HStack {
                if ring.mode == .camera {
                    Button("Téléphone en main") { ring.switchToMotion() }
                }
                Spacer()
                if ring.canCancel {
                    Button("Quitter le test") { ring.cancelTest() }
                }
            }
            .font(.subheadline.weight(.bold))
        }
        .padding(20)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Theme.accent.opacity(0.6), lineWidth: 2))
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

struct DoneView: View {
    @EnvironmentObject var ring: RingController
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 180)
                .rotationEffect(.degrees(bounce ? -10 : 10))
                .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: bounce)
                .onAppear { bounce = true }
            Text("Bonjour !")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(Theme.accent)
            Text(ring.doneText)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                ring.phase = .idle
            } label: {
                Text("C'est parti")
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(20)
        .background(Color.black.ignoresSafeArea())
    }
}
