import AppKit
import KeyboardShortcuts
import SwiftUI
import WhippetCore

/// Links and searches you save, opened with text you type, each with its own hotkey.
@MainActor
final class QuicklinksModule: LauncherModule {
    let manifest = ModuleManifest.quicklinks
    let quicklinks: Quicklinks
    private let navigation: SettingsNavigation
    private let createQuicklink: () -> Void
    private weak var host: (any ModuleHost)?
    private var registeredHotkeys: Set<String> = []

    init(quicklinks: Quicklinks, navigation: SettingsNavigation, createQuicklink: @escaping () -> Void) {
        self.quicklinks = quicklinks
        self.navigation = navigation
        self.createQuicklink = createQuicklink
    }

    var settingsPane: ModuleSettingsPane? {
        ModuleSettingsPane(title: String(localized: "Quicklinks"), symbol: "link", tint: .indigo) {
            [quicklinks, navigation] in AnyView(QuicklinksPane(quicklinks: quicklinks, navigation: navigation))
        }
    }

    func attach(to host: any ModuleHost) {
        self.host = host
        quicklinks.onListChange = { [weak self] in self?.registerHotkeys() }
        registerHotkeys()
    }

    var revision: AnyHashable { quicklinks.items }

    func contributions(for query: String) -> [Contribution] {
        var contributions = quicklinks.items.map { Contribution.listed(item(for: $0)) }
        guard !query.isEmpty else { return contributions }
        for quicklink in quicklinks.items where quicklink.takesArgument {
            var item = item(for: quicklink)
            item = LauncherItem(
                id: "with:quicklink:\(quicklink.uuid)", module: manifest.id, title: quicklink.name,
                subtitle: String(localized: "Quicklink"), icon: item.icon, launchKey: item.id,
                refs: [.quicklink(quicklink.uuid), .quicklinkFallbacks], payload: Fallback(quicklink: quicklink))
            contributions.append(.fallback(item))
        }
        return contributions
    }

    /// A quicklink offered for the whole search text, opened with it straight away.
    private struct Fallback: Hashable {
        let quicklink: Quicklink
    }

    private func item(for quicklink: Quicklink) -> LauncherItem {
        let icon = Quicklinks.icon(for: quicklink).map { ItemIcon.image(.init(image: $0)) } ?? .symbol("link")
        let id = "quicklink:\(quicklink.uuid)"
        return LauncherItem(
            id: id, module: manifest.id, title: quicklink.name, subtitle: String(localized: "Quicklink"), icon: icon,
            section: String(localized: "Quicklinks"), searchText: quicklink.searchText, launchKey: id, favoriteKey: id,
            refs: [.quicklink(quicklink.uuid)], hotkey: quicklink.shortcutName, payload: quicklink)
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        if let fallback = item.payload(as: Fallback.self) {
            return [
                ItemAction(
                    id: "quicklink.open", title: String(localized: "Open Quicklink"), icon: "return",
                    recordsLaunch: true
                ) { [weak host] in
                    let text = host?.query.trimmingCharacters(in: .whitespaces) ?? ""
                    return Quicklinks.open(fallback.quicklink, argument: text) ? .dismiss : .fail()
                }
            ]
        }
        if let quicklink = item.payload(as: Quicklink.self) {
            guard quicklink.takesArgument else {
                return [
                    ItemAction(
                        id: "quicklink.open", title: String(localized: "Open Quicklink"), icon: "return",
                        recordsLaunch: true
                    ) {
                        Quicklinks.open(quicklink) ? .dismiss : .fail()
                    }
                ]
            }
            return [
                ItemAction(
                    id: "quicklink.enter-text", title: String(localized: "Enter Text"), icon: "return",
                    runsOnTab: true
                ) { .input(Self.request(for: quicklink)) }
            ]
        }
        guard item.command == .createQuicklink else { return [] }
        return [
            .open(owner: .createQuicklink) { [createQuicklink] in
                createQuicklink()
                return .stay
            }
        ]
    }

    /// The text a quicklink opens with, typed in the search bar. It's counted as used once it opens.
    private static func request(for quicklink: Quicklink) -> InputRequest {
        InputRequest(
            label: quicklink.name, placeholder: String(localized: "Type and press Return"),
            submitTitle: String(localized: "Open Quicklink"), launchKey: "quicklink:\(quicklink.uuid)"
        ) { text in
            Quicklinks.open(quicklink, argument: text) ? .dismiss : .fail()
        }
    }

    func hotkeys(_ modules: ModuleSettings) -> [(name: KeyboardShortcuts.Name, isOn: Bool)] {
        quicklinks.items.map { ($0.shortcutName, modules.isEnabled(.quicklink($0.uuid))) }
    }

    /// Registers a handler once per quicklink, which looks it up when pressed. One that takes text opens the panel
    /// ready for it.
    private func registerHotkeys() {
        defer { host?.hotkeysChanged() }
        for quicklink in quicklinks.items where !registeredHotkeys.contains(quicklink.uuid) {
            registeredHotkeys.insert(quicklink.uuid)
            let uuid = quicklink.uuid
            KeyboardShortcuts.onKeyDown(for: quicklink.shortcutName) { [weak self] in
                guard let self, let host, let quicklink = quicklinks.items.first(where: { $0.uuid == uuid }),
                    host.modules.isEnabled(.quicklink(uuid))
                else { return }
                guard quicklink.takesArgument else {
                    host.recordLaunch("quicklink:\(uuid)")
                    Quicklinks.open(quicklink)
                    return
                }
                host.openDirectly { host.beginInput(Self.request(for: quicklink)) }
            }
        }
    }
}
