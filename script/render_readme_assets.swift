import AppKit
import SwiftUI

@main
struct ReadmeAssetRenderer {
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
