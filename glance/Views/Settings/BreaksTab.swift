import SwiftUI

struct BreaksTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var newMessage: String = ""
    @State private var showingScheduledBreakEditor = false
    @State private var editingScheduledBreak: ScheduledBreak?

    var body: some View {
        Form {
            Section("Timer Mode") {
                Picker("Mode", selection: Binding(
                    get: { settings.timerMode },
                    set: { settings.timerMode = $0 }
                )) {
                    ForEach(TimerMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if settings.timerMode == .pomodoro {
                Section("Pomodoro Settings") {
                    Picker("Work duration", selection: $settings.pomodoroWorkMinutes) {
                        ForEach([15, 20, 25, 30, 35, 40, 45, 50], id: \.self) { min in
                            Text("\(min) minutes").tag(min)
                        }
                    }

                    Picker("Short break", selection: $settings.pomodoroShortBreakSeconds) {
                        Text("3 minutes").tag(180)
                        Text("5 minutes").tag(300)
                        Text("7 minutes").tag(420)
                        Text("10 minutes").tag(600)
                    }

                    Picker("Long break", selection: $settings.pomodoroLongBreakSeconds) {
                        Text("10 minutes").tag(600)
                        Text("15 minutes").tag(900)
                        Text("20 minutes").tag(1200)
                        Text("30 minutes").tag(1800)
                    }

                    Picker("Long break after", selection: $settings.pomodoroLongBreakAfter) {
                        ForEach(2...8, id: \.self) { n in
                            Text("\(n) cycles").tag(n)
                        }
                    }

                    Text("The Pomodoro technique: work for focused intervals, take short breaks between, and a long break after several cycles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
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

                if settings.lockOnBreak {
                    Picker("Lock on", selection: Binding(
                        get: { settings.lockOnBreakMode },
                        set: { settings.lockOnBreakMode = $0 }
                    )) {
                        ForEach(LockOnBreakMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }
            }

            Section("Scheduled Breaks") {
                ForEach(settings.scheduledBreaks) { sb in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(sb.name.isEmpty ? "Untitled" : sb.name)
                                .font(.callout)
                            Text(sb.formattedTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { sb.enabled },
                            set: { newValue in
                                var breaks = settings.scheduledBreaks
                                if let idx = breaks.firstIndex(where: { $0.id == sb.id }) {
                                    breaks[idx].enabled = newValue
                                    settings.scheduledBreaks = breaks
                                }
                            }
                        ))
                        .labelsHidden()
                        Button(role: .destructive) {
                            settings.scheduledBreaks.removeAll { $0.id == sb.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Scheduled Break...") {
                    editingScheduledBreak = ScheduledBreak()
                    showingScheduledBreakEditor = true
                }

                Text("Scheduled breaks trigger at specific times regardless of the work timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .sheet(isPresented: $showingScheduledBreakEditor) {
                if let editing = editingScheduledBreak {
                    ScheduledBreakEditorSheet(scheduledBreak: editing) { saved in
                        var breaks = settings.scheduledBreaks
                        if let idx = breaks.firstIndex(where: { $0.id == saved.id }) {
                            breaks[idx] = saved
                        } else {
                            breaks.append(saved)
                        }
                        settings.scheduledBreaks = breaks
                        showingScheduledBreakEditor = false
                    } onCancel: {
                        showingScheduledBreakEditor = false
                    }
                }
            }

            Section("Pre-Break Reminder") {
                Toggle("Show a reminder before break", isOn: $settings.showPreBreakReminder)

                if settings.showPreBreakReminder {
                    Picker("Show before break", selection: $settings.preBreakReminderSeconds) {
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                    }
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

// MARK: - Scheduled Break Editor

struct ScheduledBreakEditorSheet: View {
    @State var scheduledBreak: ScheduledBreak
    var onSave: (ScheduledBreak) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Scheduled Break")
                .font(.headline)

            Form {
                TextField("Name", text: $scheduledBreak.name)

                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)

                Picker("Duration", selection: $scheduledBreak.durationSeconds) {
                    Text("20 seconds").tag(20)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("15 minutes").tag(900)
                }

                Section("Active Days") {
                    Toggle("Mon", isOn: dayBinding(2))
                    Toggle("Tue", isOn: dayBinding(3))
                    Toggle("Wed", isOn: dayBinding(4))
                    Toggle("Thu", isOn: dayBinding(5))
                    Toggle("Fri", isOn: dayBinding(6))
                    Toggle("Sat", isOn: dayBinding(7))
                    Toggle("Sun", isOn: dayBinding(1))
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { onSave(scheduledBreak) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 400, height: 500)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: scheduledBreak.hour, minute: scheduledBreak.minute)) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                scheduledBreak.hour = components.hour ?? 12
                scheduledBreak.minute = components.minute ?? 0
            }
        )
    }

    private func dayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { scheduledBreak.activeDays.contains(weekday) },
            set: { active in
                if active {
                    scheduledBreak.activeDays.insert(weekday)
                } else {
                    scheduledBreak.activeDays.remove(weekday)
                }
            }
        )
    }
}
