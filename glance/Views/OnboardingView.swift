import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var currentStep = 0
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: timingStep
                case 2: wellnessStep
                case 3: readyStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                // Step indicators
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                if currentStep < 3 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        settings.hasCompletedOnboarding = true
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 380)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundColor(.accentColor)

            Text("Welcome to Glance")
                .font(.title.bold())

            Text("Glance helps you rest your eyes by reminding you to take regular breaks. Follow the 20-20-20 rule: every 20 minutes, look at something 20 feet away for 20 seconds.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .padding()
    }

    private var timingStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.accentColor)

            Text("Break Timing")
                .font(.title2.bold())

            Text("How often should Glance remind you to take a break?")
                .foregroundStyle(.secondary)

            Form {
                Picker("Work for", selection: $settings.shortBreakInterval) {
                    ForEach([10, 15, 20, 25, 30, 45, 60], id: \.self) { min in
                        Text("\(min) minutes").tag(min)
                    }
                }

                Picker("Break for", selection: $settings.shortBreakDuration) {
                    ForEach([10, 15, 20, 30, 45, 60], id: \.self) { sec in
                        Text("\(sec) seconds").tag(sec)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 340)
            .scrollDisabled(true)
        }
        .padding()
    }

    private var wellnessStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.accentColor)

            Text("Wellness Reminders")
                .font(.title2.bold())

            Text("Optional notifications to help you blink and maintain good posture.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Form {
                Toggle("Blink reminders", isOn: $settings.blinkReminderEnabled)
                Toggle("Posture reminders", isOn: $settings.postureReminderEnabled)
            }
            .formStyle(.grouped)
            .frame(maxWidth: 340)
            .scrollDisabled(true)
        }
        .padding()
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title.bold())

            Text("Glance will run in your menu bar and remind you to take breaks. You can customize everything in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            VStack(alignment: .leading, spacing: 8) {
                Label("Work for \(settings.shortBreakInterval) minutes", systemImage: "desktopcomputer")
                Label("Break for \(settings.shortBreakDuration) seconds", systemImage: "eye.slash")
                if settings.blinkReminderEnabled {
                    Label("Blink reminders on", systemImage: "eye")
                }
                if settings.postureReminderEnabled {
                    Label("Posture reminders on", systemImage: "figure.stand")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding()
    }
}
