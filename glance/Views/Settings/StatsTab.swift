import SwiftUI

struct StatsTab: View {
    @ObservedObject private var statsManager = StatsManager.shared
    @State private var selectedRange: StatsTimeRange = .today

    var body: some View {
        Form {
            Section {
                Picker("Time Range", selection: $selectedRange) {
                    ForEach(StatsTimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }

            let period = statsManager.stats(for: selectedRange)

            Section("Screen Score") {
                HStack {
                    Spacer()
                    screenScoreGauge(score: selectedRange == .today ? statsManager.todayStats.screenScore : period.averageScreenScore)
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            Section("Metrics") {
                metricsGrid(period: period)
            }

            Section("Break Breakdown") {
                breakdownView(period: period)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Screen Score Gauge

    private func screenScoreGauge(score: Int) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: Double(score) / 100.0)
                    .stroke(scoreColor(score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                Text("\(score)")
                    .font(.system(size: 32, weight: .medium, design: .rounded))
            }

            Text("Screen Score")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .yellow }
        if score >= 40 { return .orange }
        return .red
    }

    // MARK: - Metrics Grid

    private func metricsGrid(period: PeriodStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCell(value: "\(period.totalBreaksCompleted)", label: "Breaks Taken", icon: "checkmark.circle")
            metricCell(value: formatScreenTime(period.totalScreenTimeMinutes), label: "Screen Time", icon: "desktopcomputer")
            metricCell(value: "\(period.totalFocusCycles)", label: "Focus Cycles", icon: "target")
            metricCell(value: "\(period.totalBreaksSkipped)", label: "Breaks Skipped", icon: "forward.fill")
        }
        .padding(.vertical, 4)
    }

    private func metricCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Breakdown

    private func breakdownView(period: PeriodStats) -> some View {
        VStack(spacing: 8) {
            breakdownRow(label: "Short breaks", count: period.totalShortBreaks, color: .blue)
            breakdownRow(label: "Long breaks", count: period.totalLongBreaks, color: .purple)
            breakdownRow(label: "Postponed", count: period.totalBreaksPostponed, color: .orange)
            breakdownRow(label: "Skipped", count: period.totalBreaksSkipped, color: .red)
        }
    }

    private func breakdownRow(label: String, count: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.callout)
            Spacer()
            Text("\(count)")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func formatScreenTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}
