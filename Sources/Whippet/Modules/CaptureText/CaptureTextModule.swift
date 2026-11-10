import AppKit

/// Copying the text in an area of the screen.
@MainActor
final class CaptureTextModule: LauncherModule {
    let manifest = ModuleManifest.captureText
    /// Closes the launcher, leaving it out of the screen's picture, and lets an area be picked.
    private let capture: () -> Void

    init(capture: @escaping () -> Void) {
        self.capture = capture
    }

    var activity: [ActivityLock] {
        guard ScreenCapture.isCapturing else { return [] }
        return [
            ActivityLock(
                module: manifest.id, rows: ["capture-text"], reason: String(localized: "Picking an area of the screen"))
        ]
    }

    func contributions(for query: String) -> [Contribution] {
        [
            .listed(
                .command(
                    .captureText, id: "command:capture-text", title: String(localized: "Capture Text"),
                    icon: .symbol("text.viewfinder")))
        ]
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        [
            .command(owner: .captureText) { [capture] in
                capture()
                return .stay
            }
        ]
    }

    func run(command: String) {
        capture()
    }
}
