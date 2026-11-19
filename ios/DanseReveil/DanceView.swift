import AVFoundation
import SwiftUI

struct DanceView: View {
    @EnvironmentObject var ring: RingController
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if ring.mode == .camera {
                    CameraPreview(session: ring.camera.session)
                } else {
                    Text("📱")
                        .font(.system(size: 120))
                        .rotationEffect(.degrees(sin(Date().timeIntervalSince1970 * 8) * ring.energy * 25))
                        .scaleEffect(1 + ring.energy * 0.3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            VStack(spacing: 8) {
                Text("DANSE !")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(Theme.gradient)
                    .scaleEffect(pulse ? 1.08 : 1)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                Text(ring.message).font(.title3).frame(minHeight: 28)

                bar(value: min(1, ring.energy), height: 12,
                    fill: ring.energy >= RingController.threshold ? AnyShapeStyle(Theme.green) : AnyShapeStyle(Theme.orange))
                bar(value: min(1, ring.progress / Double(ring.target)), height: 22,
                    fill: AnyShapeStyle(LinearGradient(colors: [Theme.pink, Theme.green], startPoint: .leading, endPoint: .trailing)))
                Text("\(Int(ring.progress)) / \(ring.target) s")
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)

                HStack {
                    if ring.mode == .camera {
                        Button("Passer en mode téléphone en main") { ring.switchToMotion() }
                    }
                    if ring.canCancel {
                        Button("Quitter le test") { ring.cancelTest() }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
            .background(Color(red: 0.08, green: 0.06, blue: 0.16))
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { pulse = true }
    }

    private func bar(value: Double, height: CGFloat, fill: AnyShapeStyle) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(fill).frame(width: geo.size.width * value)
                    .animation(.linear(duration: 0.15), value: value)
            }
        }
        .frame(height: height)
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
        VStack(spacing: 14) {
            Spacer()
            Text("🌞").font(.system(size: 96))
            Text("Bien joué, t'es réveillé·e !").font(.title.bold()).multilineTextAlignment(.center)
            Text(ring.doneText).foregroundStyle(Theme.muted)
            Spacer()
            Button {
                ring.phase = .idle
            } label: {
                Text("Retour")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .background(Theme.gradient)
                    .foregroundStyle(Color(red: 0.1, green: 0.06, blue: 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(16)
    }
}
