import AppKit
import UserNotifications

/// Posts Whippet's notifications and passes back what's clicked in them, each for the command or feature it's from,
/// which has to declare notifications and be on. Permission is asked for the first time something needs it, so
/// people who never use a timer are never asked. A new kind of notification is a case of `Kind`, with its buttons.
@MainActor
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifications()

    enum Action: String {
        case snooze
        case stop

        var title: String {
            switch self {
            case .snooze: String(localized: "Snooze")
            case .stop: String(localized: "Stop")
            }
        }
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

        /// The buttons on the notification.
        var actions: [Action] {
            switch self {
            case .timerDone: [.stop, .snooze]
            }
        }

        /// What macOS knows this kind of notification by, which delivered ones keep.
        var category: String {
            switch self {
            case .timerDone: "timer"
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

    typealias Handler = (_ identifier: String, _ action: Action?) -> Void

    private var handlers: [Kind: Handler] = [:]
    private var center: UNUserNotificationCenter { .current() }

    /// Called at launch, before any notification can be clicked.
    func configure() {
        center.delegate = self
        center.setNotificationCategories(
            Set(
                Kind.allCases.map { kind in
                    UNNotificationCategory(
                        identifier: kind.category,
                        actions: kind.actions.map { UNNotificationAction(identifier: $0.rawValue, title: $0.title) },
                        intentIdentifiers: [],
                        options: [.customDismissAction]
                    )
                }))
    }

    /// Sets what's called with a notification's identifier and the action chosen in it, or nil when the notification
    /// itself was clicked or dismissed.
    func onResponse(to kind: Kind, _ handler: @escaping Handler) {
        handlers[kind] = handler
    }

    /// Asks macOS to allow notifications, for `ref`. It asks the user once; later calls return the answer given.
    func requestAuthorization(for ref: ModuleRef) async -> Bool {
        guard PermissionGate.shared.allows(.notifications, for: ref) else { return false }
        return (try? await center.requestAuthorization(options: [.alert])) ?? false
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

    /// Posts a notification for `ref`, if it declares notifications and is on and macOS allows them. False when it
    /// wasn't posted, so what it's about can be shown another way. Whippet plays its own alert sound, so the
    /// notification itself is silent.
    func post(_ kind: Kind, identifier: String, title: String, body: String, for ref: ModuleRef) async -> Bool {
        guard PermissionGate.shared.allows(.notifications, for: ref), await isAuthorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = kind.category
        content.interruptionLevel = .active
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        return true
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
        let category = response.notification.request.content.categoryIdentifier
        await handleResponse(category: category, identifier: identifier, action: action)
    }

    private func handleResponse(category: String, identifier: String, action: Action?) {
        guard let kind = Kind.allCases.first(where: { $0.category == category }) else { return }
        handlers[kind]?(identifier, action)
    }
}
