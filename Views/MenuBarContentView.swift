import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("KefSleepSync")
                    .font(.headline)

                Text(model.selectedSpeakerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Toggle(
                "Enable sleep/wake sync",
                isOn: Binding(
                    get: { model.automationState.isEnabled },
                    set: { model.requestAutomationChange($0) }
                )
            )
            .disabled(model.selectedSpeaker == nil || model.isWorking)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    "Use keyboard volume on Optical",
                    isOn: Binding(
                        get: { model.keyboardVolumeControlState.isEnabled },
                        set: { model.setKeyboardVolumeControlEnabled($0) }
                    )
                )
                .disabled(model.selectedSpeaker == nil)

                Text(model.keyboardVolumeStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Current Mac output: \(model.currentMacOutputRouteDescription)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.shouldShowKeyboardPermissionButton {
                    Button("Request Input Monitoring") {
                        model.requestKeyboardVolumePermission()
                    }
                }
            }

            if model.isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working...")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Last Sync")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(model.automationState.lastSyncSummary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.speakers.isEmpty {
                Picker(
                    "Speaker",
                    selection: Binding(
                        get: { model.selectedSpeaker?.id },
                        set: { model.selectSpeaker(id: $0) }
                    )
                ) {
                    Text("Automatic").tag(Optional<String>.none)
                    ForEach(model.speakers) { speaker in
                        Text(speaker.name).tag(Optional(speaker.id))
                    }
                }
            }
            Divider()

            SyncActionButtons(model: model)

            Divider()

            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }

            Button("Quit") {
                model.requestQuit()
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

struct SyncActionButtons: View {
    enum LayoutStyle {
        case vertical
        case horizontal
    }

    @ObservedObject var model: AppModel
    var layoutStyle: LayoutStyle = .vertical

    var body: some View {
        Group {
            switch layoutStyle {
            case .vertical:
                VStack(alignment: .leading, spacing: 8) {
                    buttons
                }
            case .horizontal:
                HStack(spacing: 8) {
                    buttons
                }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Test Sleep") {
            model.testSleep()
        }
        .disabled(actionButtonsDisabled)

        Button("Test Wake to Optical") {
            model.testWakeToOptical()
        }
        .disabled(actionButtonsDisabled)
    }

    private var actionButtonsDisabled: Bool {
        model.selectedSpeaker == nil || model.isWorking
    }
}
