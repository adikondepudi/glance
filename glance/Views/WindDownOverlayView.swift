import SwiftUI

struct WindDownOverlayView: View {
    @ObservedObject private var windDownManager = WindDownManager.shared
    @State private var appear = false

    var body: some View {
        ZStack {
            // Warm-toned background
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.12, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "moon.stars")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.7))

                Text(windDownManager.currentMessage)
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)

                if windDownManager.dismissCount >= 3 && AppSettings.shared.windDownEscalation {
                    Text("Dismissed \(windDownManager.dismissCount) times tonight")
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.7))
                }

                Spacer()

                Button {
                    windDownManager.dismiss()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 60)
            }
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appear = true
            }
        }
    }
}

// MARK: - Wind Down Window Controller

class WindDownWindowController: NSWindowController {
    convenience init(screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = true
        window.backgroundColor = .black
        window.setFrame(screen.frame, display: true)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(
            rootView: WindDownOverlayView()
        )
        window.contentView = hostingView

        self.init(window: window)
    }
}
