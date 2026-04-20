import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Automation") {
                Toggle(
                    "Enable sleep/wake sync",
                    isOn: Binding(
                        get: { model.automationState.isEnabled },
                        set: { model.requestAutomationChange($0) }
                    )
                )
                .disabled(model.selectedSpeaker == nil || model.isWorking)

                if let originalMode = model.automationState.originalStandbyMode,
                   model.automationState.isEnabled {
                    LabeledContent("Original standby mode", value: originalMode.displayName)
                }

                Text("When enabled, the app saves the current KEF standby mode, switches the speaker to Never, puts it into network standby when macOS sleeps, and powers it back on to Optical after macOS wakes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Speaker") {
                Picker(
                    "Selected speaker",
                    selection: Binding(
                        get: { model.selectedSpeaker?.id },
                        set: { model.selectSpeaker(id: $0) }
                    )
                ) {
                    Text("Automatic").tag(Optional<String>.none)
                    ForEach(model.speakers) { speaker in
                        Text("\(speaker.name) (\(speaker.modelName))").tag(Optional(speaker.id))
                    }
                }

                if model.speakers.isEmpty {
                    Text("No KEF speakers are visible on the local network yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.speakers) { speaker in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(speaker.name)
                            Text("\(speaker.modelName) • \(speaker.hostDisplayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Launch") {
                Toggle(
                    "Start at login",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLoginEnabled($0) }
                    )
                )

                Text(model.loginItemStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Status") {
                LabeledContent("Current speaker", value: model.selectedSpeakerName)
                LabeledContent("Last sync", value: model.automationState.lastSyncSummary)

                SyncActionButtons(model: model, layoutStyle: .horizontal)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560, height: 460)
    }
}
