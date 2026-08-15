import SwiftUI
import AppKit

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

                // Skip warning (#16)
                if breakManager.breaksSkippedCount >= 3 {
                    Text("You've skipped \(breakManager.breaksSkippedCount) breaks in a row. Consider resting your eyes.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.8))
                        .padding(.bottom, 8)
                }

                // Snooze / Skip / End Early (#9, #17)
                if breakManager.canSkip || breakManager.canEndEarly {
                    Group {
                        if breakManager.canEndEarly {
                            overlayButton("End Break") {
                                breakManager.endBreakEarly()
                            }
                        } else if showSkipButton {
                            HStack(spacing: 12) {
                                if breakManager.canPostpone {
                                    overlayButton("+1m") {
                                        breakManager.snoozeBreak(extraSeconds: 60)
                                    }
                                    overlayButton("+5m") {
                                        breakManager.snoozeBreak(extraSeconds: 300)
                                    }
                                }
                                overlayButton("Skip") {
                                    breakManager.skipCurrentBreak()
                                }
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
        case .gradient:
            LinearGradient(
                colors: [
                    Color(hex: settings.breakGradientStart),
                    Color(hex: settings.breakGradientEnd)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .solid:
            Color(hex: settings.breakSolidColor)
        case .image:
            if !settings.breakImagePath.isEmpty,
               let image = NSImage(contentsOfFile: settings.breakImagePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(Color.black.opacity(0.5))
            } else {
                Color.black
            }
        case .blur:
            ZStack {
                // Blurs whatever is beneath the overlay window ("frosted glass
                // over your work"). Requires the window itself to be non-opaque
                // with a clear background color — see BreakWindowController.
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                // .hudWindow always renders a dark blur regardless of system
                // light/dark appearance or what's underneath, which is what
                // keeps this overlay's white text legible either way. The
                // scrim below is extra insurance for very bright content
                // (e.g. a white document) showing through the blur.
                Color.black.opacity(0.35)
            }
        case .animatedGradient:
            AnimatedGradientBackground(
                colors: [
                    Color(hex: settings.breakGradientStart),
                    Color(hex: settings.breakGradientEnd)
                ]
            )
        }
    }
}

// MARK: - Blurred Screen Background

/// Wraps an `NSVisualEffectView` for use as a full-screen "frosted glass"
/// backdrop. With `.behindWindow` blending, the view blurs the content of
/// whatever is beneath its window in the window server's compositing order —
/// here, the user's desktop and other app windows, since the break overlay
/// floats above everything at `.screenSaver` level.
private struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Animated Gradient Background

/// A slow, continuously-drifting gradient meant to read as calm rather than
/// eye-catching — this is a rest screen, not a loading spinner. The gradient's
/// start/end points and hue are a pure function of elapsed time, computed
/// fresh on each `TimelineView` tick rather than driven by `@State` mutation.
///
/// `minimumInterval` caps how often `TimelineView` invalidates — 0.3s (about
/// 3 updates/sec) is far coarser than the screen's refresh rate but still
/// imperceptibly smooth for a drift this slow (a full ~24s cycle), so it
/// keeps CPU/GPU usage negligible for a view that may sit on screen for
/// minutes at a time.
private struct AnimatedGradientBackground: View {
    let colors: [Color]

    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                staticGradient
            } else {
                TimelineView(.animation(minimumInterval: 0.3, paused: false)) { timeline in
                    gradient(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .onReceive(
            // Posted on NSWorkspace's own notification center, not .default.
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        ) { _ in
            reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }

    private var staticGradient: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func gradient(at time: TimeInterval) -> some View {
        let period = 24.0 // seconds for one full, gentle drift cycle
        let phase = (time.truncatingRemainder(dividingBy: period)) / period * 2 * .pi

        // The gradient's axis slowly rotates around the screen's center...
        let start = UnitPoint(x: 0.5 + 0.5 * cos(phase), y: 0.5 + 0.5 * sin(phase))
        let end = UnitPoint(x: 0.5 - 0.5 * cos(phase), y: 0.5 - 0.5 * sin(phase))

        return LinearGradient(colors: colors, startPoint: start, endPoint: end)
            // ...while a small hue drift (+/-10deg) keeps the color itself
            // from ever looking perfectly static, without ever being jarring.
            .hueRotation(.degrees(sin(phase) * 10))
    }
}

// MARK: - Break Window Controller (one per screen)

// Borderless windows refuse key status by default, which would leave keyboard
// events (double-Escape skip) going to the previously frontmost app.
private final class BreakOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

class BreakWindowController: NSWindowController {
    convenience init(screen: NSScreen) {
        let window = BreakOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        // The blurred-screen style needs NSVisualEffectView's .behindWindow
        // blending to actually see what's beneath, which only happens if the
        // window itself is non-opaque with a clear background. Every other
        // style paints the full screen itself, so they keep the cheaper
        // opaque/black default.
        let usesBlurBackground = AppSettings.shared.breakBackgroundStyle == .blur
        window.isOpaque = !usesBlurBackground
        window.backgroundColor = usesBlurBackground ? .clear : .black
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
