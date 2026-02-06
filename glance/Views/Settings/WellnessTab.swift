import SwiftUI

struct WellnessTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Blink Reminder") {
                Toggle("Enable blink reminders", isOn: $settings.blinkReminderEnabled)
                    .onChange(of: settings.blinkReminderEnabled) { _ in
                        Task { @MainActor in
                            WellnessManager.shared.resetTimers()
                        }
                    }

                if settings.blinkReminderEnabled {
                    HStack {
                        Text("Remind every")
                        Picker("", selection: $settings.blinkReminderInterval) {
                            Text("5 minutes").tag(5)
                            Text("10 minutes").tag(10)
                            Text("15 minutes").tag(15)
                            Text("20 minutes").tag(20)
                            Text("30 minutes").tag(30)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .onChange(of: settings.blinkReminderInterval) { _ in
                            Task { @MainActor in
                                WellnessManager.shared.resetTimers()
                            }
                        }
                    }

                    Text("Regular blinking helps prevent dry eyes and keeps your eyes comfortable during long screen sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Posture Reminder") {
                Toggle("Enable posture reminders", isOn: $settings.postureReminderEnabled)
                    .onChange(of: settings.postureReminderEnabled) { _ in
                        Task { @MainActor in
                            WellnessManager.shared.resetTimers()
                        }
                    }

                if settings.postureReminderEnabled {
                    HStack {
                        Text("Remind every")
                        Picker("", selection: $settings.postureReminderInterval) {
                            Text("15 minutes").tag(15)
                            Text("20 minutes").tag(20)
                            Text("30 minutes").tag(30)
                            Text("45 minutes").tag(45)
                            Text("60 minutes").tag(60)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .onChange(of: settings.postureReminderInterval) { _ in
                            Task { @MainActor in
                                WellnessManager.shared.resetTimers()
                            }
                        }
                    }

                    Text("Good posture reduces back pain, neck strain, and tension headaches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tips") {
                VStack(alignment: .leading, spacing: 8) {
                    tipRow(icon: "eye", text: "Follow the 20-20-20 rule: Every 20 minutes, look at something 20 feet away for 20 seconds.")
                    tipRow(icon: "hand.raised", text: "Position your screen at arm's length and slightly below eye level.")
                    tipRow(icon: "light.max", text: "Match your screen brightness to your surroundings to reduce strain.")
                    tipRow(icon: "drop", text: "Blink frequently — we blink 66% less while using screens.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
