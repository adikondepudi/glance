import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView {
            StatsTab()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }

            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            BreaksTab()
                .tabItem {
                    Label("Breaks", systemImage: "timer")
                }

            SmartPauseTab()
                .tabItem {
                    Label("Smart Pause", systemImage: "brain.head.profile")
                }

            ScheduleTab()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }

            WellnessTab()
                .tabItem {
                    Label("Wellness", systemImage: "heart")
                }

            AppearanceTab()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            SoundsTab()
                .tabItem {
                    Label("Sounds", systemImage: "speaker.wave.2")
                }

            AutomationTab()
                .tabItem {
                    Label("Automations", systemImage: "bolt")
                }
        }
        .frame(width: 640, height: 500)
        .environmentObject(settings)
    }
}
