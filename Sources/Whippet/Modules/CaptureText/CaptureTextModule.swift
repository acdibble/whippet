import AppKit

/// Copying the text in an area of the screen.
@MainActor
final class CaptureTextModule: LauncherModule {
    let manifest = ModuleManifest.captureText
    private weak var host: (any ModuleHost)?

    func attach(to host: any ModuleHost) {
        self.host = host
    }

    var activity: [ActivityLock] {
        guard ScreenCapture.isCapturing else { return [] }
        return [
            ActivityLock(
                module: manifest.id, rows: ["capture-text"], reason: String(localized: "Picking an area of the screen"))
        ]
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        [
            .command(owner: .captureText) { [weak self] in
                self?.capture()
                return .stay
            }
        ]
    }

    /// Closes the launcher first, and leaves it out of the screen's picture in case it hasn't gone yet, then lets an
    /// area be picked.
    private func capture() {
        guard let host else { return }
        let launcher = host.panelWindowNumber
        if host.isPanelVisible {
            host.dismiss()
        }
        Task { await ScreenCapture.captureText(excludingWindows: launcher.map { [$0] } ?? []) }
    }
}
