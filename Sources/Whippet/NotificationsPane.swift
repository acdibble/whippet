import AppKit
import SwiftUI
import UserNotifications

/// Everything about Whippet's notifications in one place: a switch for all of them, one for each kind, and how
/// timers alert.
struct NotificationsPane: View {
    @Bindable var timers: Timers
    @AppStorage(Notifications.enabledKey) private var isEnabled = true
    @State private var authorization = UNAuthorizationStatus.notDetermined

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isEnabled) {
                    Text("Allow Notifications")
                    Text("Every kind of notification from Whippet")
                }
                if isEnabled, authorization == .denied {
                    LabeledContent {
                        Button("Open Notification Settings…", action: Notifications.openSettings)
                    } label: {
                        Text("Turned off in System Settings")
                        Text("Until they're allowed there, Whippet shows alerts instead")
                    }
                }
            }

            Section("Notifications") {
                ForEach(Notifications.Kind.allCases) { kind in
                    KindToggle(kind: kind)
                }
            }
            .disabled(!isEnabled)

            Section("Timers") {
                Picker("Alert Sound", selection: $timers.sound) {
                    Text("None").tag("")
                    ForEach(Timers.sounds, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .onChange(of: timers.sound) { _, sound in
                    guard !sound.isEmpty else { return }
                    NSSound(named: NSSound.Name(sound))?.play()
                }
                Picker("Snooze For", selection: $timers.snoozeMinutes) {
                    ForEach(Timers.snoozeChoices, id: \.self) { minutes in
                        Text(TimerNaming.duration(TimeInterval(minutes * 60))).tag(minutes)
                    }
                }
            }
        }
        .toggleStyle(.switch)
        .task { await refreshAuthorization() }
        .onChange(of: isEnabled) { _, isEnabled in
            guard isEnabled, authorization == .notDetermined else { return }
            Task {
                _ = await Notifications.shared.requestAuthorization()
                await refreshAuthorization()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshAuthorization() }
        }
    }

    private func refreshAuthorization() async {
        authorization = await Notifications.shared.authorizationStatus
    }
}

/// A switch for one kind of notification, stored under the kind's own key.
private struct KindToggle: View {
    let kind: Notifications.Kind
    @AppStorage private var isOn: Bool

    init(kind: Notifications.Kind) {
        self.kind = kind
        _isOn = AppStorage(wrappedValue: true, kind.key)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(kind.title)
            Text(kind.detail)
        }
    }
}
