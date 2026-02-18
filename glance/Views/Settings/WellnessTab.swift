import SwiftUI

struct WellnessTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showingReminderEditor = false
    @State private var editingReminder: CustomReminder?

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

            Section("Custom Reminders") {
                ForEach(settings.customReminders) { reminder in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(reminder.name.isEmpty ? "Untitled" : reminder.name)
                                .font(.callout)
                            Text("Every \(reminder.intervalMinutes)m")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { reminder.enabled },
                            set: { newValue in
                                var reminders = settings.customReminders
                                if let idx = reminders.firstIndex(where: { $0.id == reminder.id }) {
                                    reminders[idx].enabled = newValue
                                    settings.customReminders = reminders
                                    Task { @MainActor in
                                        WellnessManager.shared.resetCustomReminderTimers()
                                    }
                                }
                            }
                        ))
                        .labelsHidden()
                        Button(role: .destructive) {
                            settings.customReminders.removeAll { $0.id == reminder.id }
                            Task { @MainActor in
                                WellnessManager.shared.resetCustomReminderTimers()
                            }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Custom Reminder...") {
                    editingReminder = CustomReminder()
                    showingReminderEditor = true
                }

                Text("Custom reminders send a notification at your chosen interval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .sheet(isPresented: $showingReminderEditor) {
                if let editing = editingReminder {
                    CustomReminderEditorSheet(reminder: editing) { saved in
                        var reminders = settings.customReminders
                        if let idx = reminders.firstIndex(where: { $0.id == saved.id }) {
                            reminders[idx] = saved
                        } else {
                            reminders.append(saved)
                        }
                        settings.customReminders = reminders
                        showingReminderEditor = false
                        Task { @MainActor in
                            WellnessManager.shared.resetCustomReminderTimers()
                        }
                    } onCancel: {
                        showingReminderEditor = false
                    }
                }
            }

            Section("After Breaks") {
                Toggle("Reset wellness reminders after completing a break", isOn: $settings.resetWellnessAfterBreak)
                Text("When enabled, blink and posture reminder timers restart after each break so you won't get a reminder right after resting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

// MARK: - Custom Reminder Editor

struct CustomReminderEditorSheet: View {
    @State var reminder: CustomReminder
    var onSave: (CustomReminder) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Custom Reminder")
                .font(.headline)

            Form {
                TextField("Name", text: $reminder.name)
                TextField("Message", text: $reminder.message)

                Picker("Remind every", selection: $reminder.intervalMinutes) {
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("20 minutes").tag(20)
                    Text("30 minutes").tag(30)
                    Text("45 minutes").tag(45)
                    Text("60 minutes").tag(60)
                    Text("90 minutes").tag(90)
                    Text("120 minutes").tag(120)
                }

                Toggle("Play sound", isOn: $reminder.soundEnabled)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { onSave(reminder) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(reminder.name.isEmpty && reminder.message.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}
