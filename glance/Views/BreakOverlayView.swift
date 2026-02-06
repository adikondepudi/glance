import SwiftUI

struct BreakOverlayView: View {
    @EnvironmentObject var breakManager: BreakManager
    @EnvironmentObject var settings: AppSettings
    @State private var showSkipButton = false
    @State private var appear = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            breakBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Breathing eye icon
                Image(systemName: "eye")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.7))
                    .scaleEffect(breathe ? 1.08 : 1.0)
                    .opacity(breathe ? 0.9 : 0.6)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: breathe)

                Spacer().frame(height: 32)

                // Message
                Text(breakManager.currentMessage)
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 80)

                Spacer().frame(height: 48)

                // Timer with progress ring
                ZStack {
                    // Track
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 2.5)
                        .frame(width: 180, height: 180)

                    // Progress
                    Circle()
                        .trim(from: 0, to: breakManager.breakProgress)
                        .stroke(
                            .white.opacity(0.6),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: breakManager.breakProgress)

                    // Time
                    Text(breakManager.formattedBreakTimeRemaining)
                        .font(.system(size: 52, weight: .ultraLight, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                Spacer()

                // Skip / End Early
                if breakManager.canSkip || breakManager.canEndEarly {
                    Group {
                        if breakManager.canEndEarly {
                            overlayButton("End Break") {
                                breakManager.endBreakEarly()
                            }
                        } else if breakManager.canSkip && showSkipButton {
                            overlayButton("Skip") {
                                breakManager.skipCurrentBreak()
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 60)
                }
            }
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                appear = true
            }
            breathe = true

            if settings.skipDifficulty == .balanced {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeIn(duration: 0.3)) { showSkipButton = true }
                }
            } else if settings.skipDifficulty == .casual {
                showSkipButton = true
            }
        }
    }

    private func overlayButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(.white.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var breakBackground: some View {
        switch settings.breakBackgroundStyle {
        case "gradient":
            LinearGradient(
                colors: [
                    Color(hex: settings.breakGradientStart),
                    Color(hex: settings.breakGradientEnd)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "solid":
            Color(hex: settings.breakSolidColor)
        case "image":
            if !settings.breakImagePath.isEmpty,
               let image = NSImage(contentsOfFile: settings.breakImagePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(Color.black.opacity(0.5))
            } else {
                Color.black
            }
        default:
            LinearGradient(
                colors: [Color(hex: "#1a1a2e"), Color(hex: "#16213e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Break Window Controller (one per screen)

class BreakWindowController: NSWindowController {
    convenience init(screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = true
        window.backgroundColor = .black
        window.setFrame(screen.frame, display: true)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false

        let hostingView = NSHostingView(
            rootView: BreakOverlayView()
                .environmentObject(BreakManager.shared)
                .environmentObject(AppSettings.shared)
        )
        window.contentView = hostingView

        self.init(window: window)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }

        self.init(red: r, green: g, blue: b)
    }
}
