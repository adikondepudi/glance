import SwiftUI

struct BreaksTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var newMessage: String = ""

    var body: some View {
        Form {
            Section("Short Break") {
                Picker("Work for", selection: $settings.shortBreakInterval) {
                    ForEach([5, 10, 15, 20, 25, 30, 45, 60], id: \.self) { min in
                        Text("\(min) minutes").tag(min)
                    }
                }

                Picker("Break for", selection: $settings.shortBreakDuration) {
                    ForEach([10, 15, 20, 30, 45, 60], id: \.self) { sec in
                        Text("\(sec) seconds").tag(sec)
                    }
                }
            }

            Section("Long Break") {
                Toggle("Enable long breaks", isOn: $settings.longBreakEnabled)

                if settings.longBreakEnabled {
                    Picker("After every", selection: $settings.longBreakInterval) {
                        ForEach(2...6, id: \.self) { n in
                            Text("\(n) short breaks").tag(n)
                        }
                    }

                    Picker("Duration", selection: $settings.longBreakDuration) {
                        Text("2 minutes").tag(120)
                        Text("3 minutes").tag(180)
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                        Text("15 minutes").tag(900)
                    }
                }
            }

            Section("Skip Behavior") {
                Picker("Difficulty", selection: Binding(
                    get: { settings.skipDifficulty },
                    set: { settings.skipDifficulty = $0 }
                )) {
                    ForEach(SkipDifficulty.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                Text(skipDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Options") {
                Toggle("Don't show breaks while I'm typing or dragging", isOn: $settings.delayWhileTyping)
                Toggle("Let me end break early when nearly done", isOn: $settings.allowEarlyEnd)
                Toggle("Lock my Mac when a break starts", isOn: $settings.lockOnBreak)
            }

            Section("Pre-Break Reminder") {
                Toggle("Show a reminder before break", isOn: $settings.showPreBreakReminder)

                if settings.showPreBreakReminder {
                    Picker("Show before break", selection: $settings.preBreakReminderSeconds) {
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                    }
                }

                Picker("Countdown duration", selection: $settings.countdownDuration) {
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }

                Toggle("Show overtime nudge", isOn: $settings.showOvertimeNudge)
            }

            Section("Postpone Limits") {
                Picker("Max postpones per day", selection: $settings.maxPostponesPerDay) {
                    Text("Unlimited").tag(0)
                    Text("3").tag(3)
                    Text("5").tag(5)
                    Text("10").tag(10)
                }

                if settings.maxPostponesPerDay > 0 {
                    Text("After reaching the limit, postpone and snooze buttons will be disabled for the rest of the day.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Custom Messages") {
                ForEach(Array(settings.customMessages.enumerated()), id: \.offset) { index, message in
                    HStack {
                        Text(message)
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            var msgs = settings.customMessages
                            msgs.remove(at: index)
                            settings.customMessages = msgs
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("Add a message…", text: $newMessage)
                        .onSubmit { addMessage() }
                    Button("Add") { addMessage() }
                        .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var skipDescription: String {
        switch settings.skipDifficulty {
        case .casual: return "Skip any break anytime without restrictions."
        case .balanced: return "Skip button appears after a short delay."
        case .hardcore: return "Breaks cannot be skipped at all."
        }
    }

    private func addMessage() {
        let trimmed = newMessage.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var msgs = settings.customMessages
        msgs.append(trimmed)
        settings.customMessages = msgs
        newMessage = ""
    }
}
