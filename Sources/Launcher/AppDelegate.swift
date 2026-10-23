import AppKit
import Carbon.HIToolbox

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let appIndex = AppIndex()
    private let clipboard = ClipboardHistory()
    private var model: LauncherModel!
    private var panel: LauncherPanel!
    private var hotKey: HotKey?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appIndex.refresh()
        clipboard.start()

        model = LauncherModel(appIndex: appIndex, clipboard: clipboard)
        model.onDismiss = { [weak self] in self?.hidePanel() }

        panel = LauncherPanel(rootView: SearchView(model: model))
        panel.delegate = self

        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            self?.togglePanel()
        }

        // Navigation keys are handled before they reach the focused view, because text fields treat Escape as "complete"
        // and focus can sit outside the search field.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === panel else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isPlainArrow = modifiers.isDisjoint(with: [.shift, .command, .option, .control])
            switch Int(event.keyCode) {
            case kVK_Escape: model.back()
            case kVK_UpArrow: model.moveSelection(by: -1)
            case kVK_DownArrow: model.moveSelection(by: 1)
            case kVK_LeftArrow where isPlainArrow, kVK_RightArrow where isPlainArrow:
                guard model.moveColumn(by: Int(event.keyCode) == kVK_LeftArrow ? -1 : 1) else { return event }
            case kVK_ANSI_P where modifiers == [.command, .shift]: model.togglePinnedSelection()
            case kVK_ANSI_Q where modifiers == [.command]: NSApp.terminate(nil)
            default: return event
            }
            return nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hidePanel()
    }

    private func togglePanel() {
        if panel.isVisible {
            hidePanel()
            return
        }
        showPanel()
    }

    private func showPanel() {
        model.reset()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel() {
        panel.orderOut(nil)
    }
}
