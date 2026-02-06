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

                    DatePicker("Start Time", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                    DatePicker("End Time", selection: endTimeBinding, displayedComponents: .hourAndMinute)
                }
            }

            if schedule.enabled {
                Section {
                    Text("Glance will only show break reminders during your set schedule. Outside of these hours, the timer will be paused.")
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

    private func save() {
        settings.officeHours = schedule
    }
}
