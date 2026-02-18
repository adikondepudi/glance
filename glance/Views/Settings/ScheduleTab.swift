import SwiftUI

struct ScheduleTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var schedule: OfficeHoursSchedule = AppSettings.shared.officeHours

    var body: some View {
        Form {
            Section("Office Hours") {
                Toggle("Only show breaks during office hours", isOn: $schedule.enabled)
                    .onChange(of: schedule.enabled) { _ in save() }

                if schedule.enabled {
                    Section("Active Days") {
                        Toggle("Monday", isOn: dayBinding(2))
                        Toggle("Tuesday", isOn: dayBinding(3))
                        Toggle("Wednesday", isOn: dayBinding(4))
                        Toggle("Thursday", isOn: dayBinding(5))
                        Toggle("Friday", isOn: dayBinding(6))
                        Toggle("Saturday", isOn: dayBinding(7))
                        Toggle("Sunday", isOn: dayBinding(1))
                    }

                    Toggle("Use different hours per day", isOn: $schedule.usePerDaySchedule)
                        .onChange(of: schedule.usePerDaySchedule) { _ in save() }

                    if schedule.usePerDaySchedule {
                        ForEach(sortedActiveDays, id: \.self) { weekday in
                            Section(dayName(weekday)) {
                                DatePicker("Start", selection: dayStartBinding(weekday), displayedComponents: .hourAndMinute)
                                DatePicker("End", selection: dayEndBinding(weekday), displayedComponents: .hourAndMinute)
                            }
                        }
                    } else {
                        DatePicker("Start Time", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                        DatePicker("End Time", selection: endTimeBinding, displayedComponents: .hourAndMinute)
                    }
                }
            }

            if schedule.enabled {
                Section("Wind Down") {
                    Toggle("Show wind-down reminders outside office hours", isOn: $settings.windDownEnabled)

                    if settings.windDownEnabled {
                        Picker("Remind every", selection: $settings.windDownIntervalMinutes) {
                            Text("5 minutes").tag(5)
                            Text("10 minutes").tag(10)
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("60 minutes").tag(60)
                        }

                        TextField("Custom message (optional)", text: $settings.windDownMessageRaw)

                        Toggle("Escalate messages after repeated dismissals", isOn: $settings.windDownEscalation)

                        Text("When working outside your office hours, a gentle full-screen reminder will encourage you to stop working.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Glance will only show break reminders during your set schedule. Outside of these hours, the timer will be paused.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tip: Setting the end time before the start time means the schedule extends past midnight.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            schedule = settings.officeHours
        }
    }

    private func dayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { schedule.activeDays.contains(weekday) },
            set: { isActive in
                if isActive {
                    schedule.activeDays.insert(weekday)
                } else {
                    schedule.activeDays.remove(weekday)
                }
                save()
            }
        )
    }

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: schedule.startHour, minute: schedule.startMinute)) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                schedule.startHour = components.hour ?? 9
                schedule.startMinute = components.minute ?? 0
                save()
            }
        )
    }

    private var endTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: schedule.endHour, minute: schedule.endMinute)) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                schedule.endHour = components.hour ?? 18
                schedule.endMinute = components.minute ?? 0
                save()
            }
        )
    }

    private var sortedActiveDays: [Int] {
        // Sort: Mon(2), Tue(3), Wed(4), Thu(5), Fri(6), Sat(7), Sun(1)
        let order = [2, 3, 4, 5, 6, 7, 1]
        return order.filter { schedule.activeDays.contains($0) }
    }

    private func dayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return ""
        }
    }

    private func dayStartBinding(_ weekday: Int) -> Binding<Date> {
        Binding(
            get: {
                let ds = schedule.perDaySchedules[weekday] ?? DaySchedule()
                return Calendar.current.date(from: DateComponents(hour: ds.startHour, minute: ds.startMinute)) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                var ds = schedule.perDaySchedules[weekday] ?? DaySchedule()
                ds.startHour = components.hour ?? 9
                ds.startMinute = components.minute ?? 0
                schedule.perDaySchedules[weekday] = ds
                save()
            }
        )
    }

    private func dayEndBinding(_ weekday: Int) -> Binding<Date> {
        Binding(
            get: {
                let ds = schedule.perDaySchedules[weekday] ?? DaySchedule()
                return Calendar.current.date(from: DateComponents(hour: ds.endHour, minute: ds.endMinute)) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                var ds = schedule.perDaySchedules[weekday] ?? DaySchedule()
                ds.endHour = components.hour ?? 18
                ds.endMinute = components.minute ?? 0
                schedule.perDaySchedules[weekday] = ds
                save()
            }
        )
    }

    private func save() {
        settings.officeHours = schedule
    }
}
