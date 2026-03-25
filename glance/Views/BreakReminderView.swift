import SwiftUI
import AppKit

struct BreakReminderView: View {
    @EnvironmentObject var breakManager: BreakManager
    @State private var appear = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Break in \(breakManager.formattedTimeUntilBreak)")
                    .font(.headline)
                Text(breakManager.currentMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Time since last break (#1)
                Text(breakManager.formattedTimeSinceLastBreak)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                // Breaks skipped warning (#2, #16)
                if breakManager.breaksSkippedCount > 0 {
                    if breakManager.breaksSkippedCount >= 3 {
                        Text("You've skipped \(breakManager.breaksSkippedCount) breaks in a row. Consider taking one.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("\(breakManager.breaksSkippedCount) break\(breakManager.breaksSkippedCount == 1 ? "" : "s") skipped in a row")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button("+1m") {
                    breakManager.postponeBreak(seconds: 60)
                }
                .disabled(!breakManager.canPostpone)
                Button("+5m") {
                    breakManager.postponeBreak(seconds: 300)
                }
                .disabled(!breakManager.canPostpone)
                Button("Skip") {
                    breakManager.skipBreak()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Start Now") {
                breakManager.startBreakNow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : -8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appear = true
            }
        }
    }
}

// MARK: - Reminder Window Controller

class ReminderWindowController: NSWindowController {
    convenience init() {
        guard let screen = NSScreen.main else {
            self.init(window: nil)
            return
        }

        let windowWidth: CGFloat = 460
        let windowHeight: CGFloat = 80
        let padding: CGFloat = 20

        let x = screen.visibleFrame.midX - windowWidth / 2
        let y = screen.visibleFrame.maxY - windowHeight - padding

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
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

        let hostingView = NSHostingView(
            rootView: BreakReminderView()
                .environmentObject(BreakManager.shared)
        )
        window.contentView = hostingView
        
        // Let SwiftUI determine the size
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }

        self.init(window: window)
    }
}
