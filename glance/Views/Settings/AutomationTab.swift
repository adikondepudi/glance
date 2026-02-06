import SwiftUI

struct AutomationTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showingEditor = false
    @State private var editingAction: AutomationAction?
    @State private var isCreatingNew = false

    var body: some View {
        Form {
            Section("Automations") {
                Text("Run AppleScripts or shell commands when a break starts or ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.automations.isEmpty {
                    LabeledContent("") {
                        Text("No automations yet")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(settings.automations) { action in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { action.enabled },
                            set: { newValue in
                                var automations = settings.automations
                                if let idx = automations.firstIndex(where: { $0.id == action.id }) {
                                    automations[idx] = AutomationAction(
                                        name: action.name,
                                        script: action.script,
                                        isAppleScript: action.isAppleScript,
                                        trigger: action.trigger,
                                        enabled: newValue
                                    )
                                    settings.automations = automations
                                }
                            }
                        ))
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.name.isEmpty ? "Untitled" : action.name)
                                .font(.headline)
                            Text("\(action.trigger.rawValue) · \(action.isAppleScript ? "AppleScript" : "Shell")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            editingAction = action
                            showingEditor = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)

                        Button(role: .destructive) {
                            settings.automations.removeAll { $0.id == action.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button("Add Automation…") {
                    editingAction = AutomationAction()
                    isCreatingNew = true
                    showingEditor = true
                }
            }

            Section("Examples") {
                VStack(alignment: .leading, spacing: 12) {
                    exampleRow(
                        title: "Pause Spotify on break",
                        trigger: "Break Start",
                        type: "AppleScript",
                        code: """
                        if application "Spotify" is running then
                            tell application "Spotify"
                                if player state is playing then pause
                            end tell
                        end if
                        """
                    )

                    Divider()

                    exampleRow(
                        title: "Enable Do Not Disturb",
                        trigger: "Break Start",
                        type: "Shell",
                        code: "shortcuts run \"Turn On Do Not Disturb\""
                    )

                    Divider()

                    exampleRow(
                        title: "Dim display brightness",
                        trigger: "Break Start",
                        type: "Shell",
                        code: "brightness 0.3"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingEditor) {
            if let action = editingAction {
                AutomationEditorSheet(
                    action: action,
                    isNew: isCreatingNew,
                    onSave: { updated in
                        var automations = settings.automations
                        if isCreatingNew {
                            automations.append(updated)
                        } else if let idx = automations.firstIndex(where: { $0.id == updated.id }) {
                            automations[idx] = updated
                        }
                        settings.automations = automations
                        showingEditor = false
                        isCreatingNew = false
                    },
                    onCancel: {
                        showingEditor = false
                        isCreatingNew = false
                    }
                )
            }
        }
    }

    private func exampleRow(title: String, trigger: String, type: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text("\(trigger) · \(type)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}

// MARK: - Editor Sheet

struct AutomationEditorSheet: View {
    @State var action: AutomationAction
    let isNew: Bool
    let onSave: (AutomationAction) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $action.name)

                Picker("Trigger", selection: $action.trigger) {
                    ForEach(AutomationAction.AutomationTrigger.allCases, id: \.self) { trigger in
                        Text(trigger.rawValue).tag(trigger)
                    }
                }

                Picker("Type", selection: $action.isAppleScript) {
                    Text("AppleScript").tag(true)
                    Text("Shell Script").tag(false)
                }
                .pickerStyle(.segmented)

                Section("Script") {
                    TextEditor(text: $action.script)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    onSave(action)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(action.script.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 420)
    }
}
