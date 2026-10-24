import Foundation
import Observation
import Sparkle

/// Checks for and installs updates with Sparkle, which reads the appcast published with each GitHub release and shows its
/// own update window. Debug builds don't start it: their build number is lower than any release's, so they would always
/// be offered one.
@MainActor
@Observable
final class Updater: NSObject {
    private(set) var canCheckForUpdates = false
    var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observation: NSKeyValueObservation?

    override init() {
        #if DEBUG
        let starts = false
        #else
        let starts = true
        #endif
        automaticallyChecksForUpdates = false
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: starts, updaterDelegate: nil, userDriverDelegate: self)
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    /// Whippet runs in the background without a Dock icon, so updates found by a scheduled check are shown without
    /// taking focus from the app in front.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
