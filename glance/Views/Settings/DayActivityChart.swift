import SwiftUI
import Charts

// MARK: - Activity Segment

struct ActivitySegment: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let type: ActivityType

    enum ActivityType: String {
        case working = "Working"
        case onBreak = "Break"
        case idle = "Idle"
    }

    var color: Color {
        switch type {
        case .working: return .blue
        case .onBreak: return .green
        case .idle: return .gray
        }
    }
}

// MARK: - Day Activity Chart

struct DayActivityChart: View {
    let events: [StatsEvent]

    var body: some View {
        let segments = buildSegments()

        if segments.isEmpty {
            Text("No activity recorded yet today.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 60)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Chart(segments) { segment in
                    RectangleMark(
                        xStart: .value("Start", segment.startTime),
                        xEnd: .value("End", segment.endTime),
                        y: .value("Activity", "Today")
                    )
                    .foregroundStyle(segment.color)
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    }
                }
                .chartYAxis(.hidden)
                .chartXScale(domain: dayRange)
                .frame(height: 40)

                // Legend
                HStack(spacing: 16) {
                    legendItem(color: .blue, label: "Working")
                    legendItem(color: .green, label: "Break")
                    legendItem(color: .gray, label: "Idle")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
        }
    }

    private var dayRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        // Show from start of day to current time (or end of day)
        let endTime = max(now, calendar.date(byAdding: .hour, value: 1, to: now) ?? now)
        return startOfDay...endTime
    }

    // MARK: - Build Segments from Events

    private func buildSegments() -> [ActivitySegment] {
        guard !events.isEmpty else { return [] }

        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var segments: [ActivitySegment] = []
        var currentState: ActivitySegment.ActivityType = .working
        var stateStartTime: Date = sorted.first!.timestamp

        for event in sorted {
            let newState: ActivitySegment.ActivityType?

            switch event.type {
            case .breakStarted:
                newState = .onBreak
            case .breakCompleted, .breakSkipped:
                newState = .working
            case .idleStarted:
                newState = .idle
            case .idleEnded:
                newState = .working
            case .screenTimeMinute:
                // Screen time confirms working state; use to fill gaps
                if currentState != .working && currentState != .onBreak {
                    newState = .working
                } else {
                    newState = nil
                }
            default:
                newState = nil
            }

            if let newState = newState, newState != currentState {
                // Close previous segment if it has duration
                if event.timestamp > stateStartTime {
                    segments.append(ActivitySegment(
                        startTime: stateStartTime,
                        endTime: event.timestamp,
                        type: currentState
                    ))
                }
                currentState = newState
                stateStartTime = event.timestamp
            }
        }

        // Close final segment up to now
        let now = Date()
        if now > stateStartTime {
            segments.append(ActivitySegment(
                startTime: stateStartTime,
                endTime: now,
                type: currentState
            ))
        }

        return segments
    }
}
