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
                Image(systemName: "figure.dance")
                    .font(.system(size: 150, weight: .ultraLight))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(sin(Date().timeIntervalSince1970 * 8) * ring.energy * 20))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            panel
                .padding(12)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dancing ? Theme.ok : Color.white.opacity(0.35))
                    .frame(width: 10, height: 10)
                Text(ring.message)
                    .font(.headline)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(ring.progress))")
                    .font(.system(size: 64, weight: .thin))
                    .monospacedDigit()
                Text("/ \(ring.target) s")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: min(1, ring.progress / Double(ring.target)))
                .tint(Theme.accent)

            // Énergie du mouvement : verte quand tu bouges assez.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(dancing ? Theme.ok : Color.white.opacity(0.5))
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
            .font(.subheadline)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 88, weight: .thin))
                .foregroundStyle(Theme.accent)
            Text("Bonjour")
                .font(.largeTitle.bold())
            Text(ring.doneText)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                ring.phase = .idle
            } label: {
                Text("OK").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
        .background(Color.black.ignoresSafeArea())
    }
}
