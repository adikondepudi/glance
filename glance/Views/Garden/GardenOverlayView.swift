import SwiftUI

struct GardenOverlayView: View {
    @EnvironmentObject var garden: GardenManager
    @EnvironmentObject var settings: AppSettings

    @State private var displayedGrid: PixelGrid = []
    @State private var appear = false

    var body: some View {
        VStack(spacing: 4) {
            PixelCanvas(grid: displayedGrid, pixelSize: 6)
                .opacity(appear ? 1 : 0)

            Text(garden.stage.displayName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .opacity(appear ? 1 : 0)
        }
        .onAppear {
            updateGrid()
            withAnimation(.easeOut(duration: 0.8)) {
                appear = true
            }
        }
        .onChange(of: garden.state.growth) {
            withAnimation(.easeInOut(duration: 0.5)) {
                updateGrid()
            }
        }
    }

    private func updateGrid() {
        let themeType = GardenThemeType(rawValue: settings.gardenTheme) ?? .gardener
        let theme = gardenTheme(for: themeType)
        displayedGrid = theme.pixelGrid(for: garden.stage, mood: garden.mood)
    }
}
