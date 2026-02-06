import SwiftUI
import UniformTypeIdentifiers

struct AppearanceTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Break Background") {
                Picker("Style", selection: $settings.breakBackgroundStyle) {
                    Text("Gradient").tag("gradient")
                    Text("Solid Color").tag("solid")
                    Text("Image").tag("image")
                }
                .pickerStyle(.segmented)

                switch settings.breakBackgroundStyle {
                case "gradient":
                    HStack(spacing: 16) {
                        VStack {
                            Text("Start Color")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: settings.breakGradientStart) },
                                set: { settings.breakGradientStart = $0.hexString }
                            ))
                            .labelsHidden()
                        }

                        VStack {
                            Text("End Color")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: settings.breakGradientEnd) },
                                set: { settings.breakGradientEnd = $0.hexString }
                            ))
                            .labelsHidden()
                        }

                        Spacer()

                        // Preview
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: settings.breakGradientStart), Color(hex: settings.breakGradientEnd)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.white.opacity(0.1))
                            )
                    }

                    HStack(spacing: 8) {
                        Text("Presets:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        presetButton("Night", start: "#1a1a2e", end: "#16213e")
                        presetButton("Ocean", start: "#0f3460", end: "#16213e")
                        presetButton("Forest", start: "#1b4332", end: "#081c15")
                        presetButton("Sunset", start: "#370617", end: "#03071e")
                        presetButton("Purple", start: "#240046", end: "#10002b")
                    }

                case "solid":
                    HStack {
                        Text("Color")
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: settings.breakSolidColor) },
                            set: { settings.breakSolidColor = $0.hexString }
                        ))
                        .labelsHidden()

                        Spacer()

                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: settings.breakSolidColor))
                            .frame(width: 120, height: 70)
                    }

                case "image":
                    HStack {
                        Text(settings.breakImagePath.isEmpty ? "No image selected" : URL(fileURLWithPath: settings.breakImagePath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Button("Choose Image...") {
                            pickImage()
                        }
                    }

                    if !settings.breakImagePath.isEmpty {
                        Button("Remove Image") {
                            settings.breakImagePath = ""
                        }
                        .foregroundStyle(.red)
                    }

                default:
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func presetButton(_ name: String, start: String, end: String) -> some View {
        Button {
            settings.breakGradientStart = start
            settings.breakGradientEnd = end
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(colors: [Color(hex: start), Color(hex: end)], startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: 40, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            settings.breakImagePath = url.path
        }
    }
}

// MARK: - Color to Hex

extension Color {
    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
