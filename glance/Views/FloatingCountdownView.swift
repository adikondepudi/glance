import SwiftUI
import AppKit

struct FloatingCountdownView: View {
    @EnvironmentObject var breakManager: BreakManager

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "eye")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text(breakManager.formattedTimeUntilBreak)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.black.opacity(0.55))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        )
    }
}

class FloatingCountdownController: NSWindowController {
    private var mouseTracker: Any?
    private var updateTimer: Timer?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 30),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
        window.isMovable = false
        window.ignoresMouseEvents = true

        let hostingView = NSHostingView(
            rootView: FloatingCountdownView()
                .environmentObject(BreakManager.shared)
        )
        window.contentView = hostingView
        hostingView.frame = window.contentView?.bounds ?? .zero

        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startTracking()
    }

    private func startTracking() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
    }

    private func updatePosition() {
        guard let window = self.window else { return }
        let mouseLocation = NSEvent.mouseLocation
        let offset: CGFloat = 20

        window.setFrameOrigin(NSPoint(
            x: mouseLocation.x + offset,
            y: mouseLocation.y - offset - window.frame.height
        ))
    }

    override func close() {
        updateTimer?.invalidate()
        if let tracker = mouseTracker {
            NSEvent.removeMonitor(tracker)
        }
        super.close()
    }
}
