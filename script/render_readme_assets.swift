import AppKit
import SwiftUI

@main
struct ReadmeAssetRenderer {
    private struct KeyboardVolumePreviewCard: View {
        @ObservedObject var model: AppModel

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("Keyboard Volume")
                    .font(.headline)

                Toggle(
                    "Use Mac volume keys for KEF",
                    isOn: .constant(model.keyboardVolumeControlState.isEnabled)
                )
                .disabled(true)

                LabeledContent("Step size", value: model.keyboardVolumeStepDescription)
                LabeledContent("Current Mac output", value: model.currentMacOutputRouteDescription)

                Text(model.keyboardVolumeStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("The keys only override macOS while the selected KEF speaker is on Optical and the Mac is actively using the learned optical output route.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .padding(18)
        }
    }

    private struct SnapshotSpec<Content: View> {
        let filename: String
        let size: CGSize
        let view: Content
    }

    static func main() throws {
        let arguments = CommandLine.arguments
        let outputDirectory: URL
        if arguments.count > 1 {
            outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        } else {
            outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let model = AppModel.makeReadmeDemoModel()
        let keyboardModel = AppModel.makeReadmeDemoModel()

        let snapshots = [
            SnapshotSpec(
                filename: "settings-preview.png",
                size: CGSize(width: 560, height: 620),
                view: AnyView(
                    ZStack {
                        Color(nsColor: .windowBackgroundColor)
                        SettingsView(model: model)
                            .frame(width: 560, height: 620)
                    }
                )
            ),
            SnapshotSpec(
                filename: "menu-preview.png",
                size: CGSize(width: 320, height: 420),
                view: AnyView(
                    ZStack {
                        Color(nsColor: .windowBackgroundColor)
                        VStack(spacing: 0) {
                            MenuBarContentView(model: model)
                                .frame(width: 320)
                                .padding(10)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 320, height: 420)
                    }
                )
            ),
            SnapshotSpec(
                filename: "keyboard-volume-preview.png",
                size: CGSize(width: 560, height: 280),
                view: AnyView(
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(nsColor: .windowBackgroundColor),
                                Color(nsColor: .underPageBackgroundColor)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        KeyboardVolumePreviewCard(model: keyboardModel)
                            .frame(width: 560, height: 280)
                    }
                )
            )
        ]

        for snapshot in snapshots {
            try writePNG(
                for: snapshot.view,
                size: snapshot.size,
                to: outputDirectory.appendingPathComponent(snapshot.filename)
            )
        }
    }

    @MainActor
    private static func writePNG<Content: View>(for view: Content, size: CGSize, to destination: URL) throws {
        let hostingView = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw NSError(
                domain: "KefSleepSync.ReadmeAssetRenderer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to render \(destination.lastPathComponent)."]
            )
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "KefSleepSync.ReadmeAssetRenderer",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode \(destination.lastPathComponent) as PNG."]
            )
        }

        try pngData.write(to: destination)
    }
}
