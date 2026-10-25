import AppKit
import UserNotifications

/// Posts Whippet's notifications and passes back what's clicked in them. Permission is asked for the first time
/// something needs it, so people who never use a timer are never asked.
@MainActor
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifications()

    enum Action: String {
        case snooze
        case stop
    }

    /// Each kind of notification, which can be turned off on its own in Settings › Notifications.
    enum Kind: String, CaseIterable, Identifiable {
        case timerDone

        var id: Self { self }

        /// The UserDefaults key for whether this kind is on; on unless turned off.
        var key: String { "notifications.\(rawValue)" }

        var title: String {
            switch self {
            case .timerDone: String(localized: "Timer Done")
            }
        }

        var detail: String {
            switch self {
            case .timerDone: String(localized: "When a timer finishes, with Stop and Snooze")
            }
        }
    }

    /// The UserDefaults key for whether Whippet sends notifications at all; on unless turned off.
    static let enabledKey = "notifications.enabled"

    /// Whether Whippet should notify about `kind`: notifications are on and so is that kind. macOS may still not
    /// allow them, which `isAuthorized` tells.
    static func wants(_ kind: Kind, defaults: UserDefaults = .standard) -> Bool {
        isOn(enabledKey, in: defaults) && isOn(kind.key, in: defaults)
    }

    private static func isOn(_ key: String, in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    /// Called with a timer notification's identifier and the action chosen, or nil when the notification itself was
    /// clicked or dismissed.
    var onTimerResponse: (_ identifier: String, _ action: Action?) -> Void = { _, _ in }

    private nonisolated static let timerCategory = "timer"
    private var center: UNUserNotificationCenter { .current() }

    /// Called at launch, before any notification can be clicked.
    func configure() {
        center.delegate = self
        let snooze = UNNotificationAction(identifier: Action.snooze.rawValue, title: String(localized: "Snooze"))
        let stop = UNNotificationAction(identifier: Action.stop.rawValue, title: String(localized: "Stop"))
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.timerCategory,
                actions: [stop, snooze],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
        ])
    }

    /// Asks once; later calls return the answer given.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert])) ?? false
    }

    var isAuthorized: Bool {
        get async {
            let status = await center.notificationSettings().authorizationStatus
            return status == .authorized || status == .provisional
        }
    }

    var authorizationStatus: UNAuthorizationStatus {
        get async { await center.notificationSettings().authorizationStatus }
    }

    /// Whippet plays its own alert sound, so the notification itself is silent.
    func postTimer(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.timerCategory
        content.interruptionLevel = .active
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func remove(identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    static func openSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Whippet counts as the frontmost app while its panel or Settings is open; notifications still show then.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let action = Action(rawValue: response.actionIdentifier)
        guard response.notification.request.content.categoryIdentifier == Self.timerCategory else { return }
        await handleTimerResponse(identifier: identifier, action: action)
    }

    private func handleTimerResponse(identifier: String, action: Action?) {
        onTimerResponse(identifier, action)
    }
}
