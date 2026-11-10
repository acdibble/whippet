import AppKit
import Observation
import SwiftUI

/// Whippet itself: Settings, the changelog, What's New after an update, sharing Whippet and quitting.
@MainActor
@Observable
final class WhippetModule: LauncherModule {
    let manifest = ModuleManifest.whippet
    /// The version updated from while What's New is offered at the top of the empty search.
    private(set) var whatsNewSince: String?
    @ObservationIgnored private let whatsNew = WhatsNew()
    @ObservationIgnored private let clipboard: ClipboardHistory
    @ObservationIgnored private weak var host: (any ModuleHost)?

    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let changelogURL = URL(string: "https://github.com/acdibble/whippet/blob/main/CHANGELOG.md")!
    static let releasesURL = URL(string: "https://github.com/acdibble/whippet/releases")!

    init(clipboard: ClipboardHistory) {
        self.clipboard = clipboard
        whatsNew.recordLaunch(of: Self.currentVersion)
        whatsNewSince = whatsNew.pending()
    }

    func attach(to host: any ModuleHost) {
        self.host = host
    }

    /// Also notices What's New's week running out while Whippet stays open.
    func panelWillShow() {
        whatsNewSince = whatsNew.pending()
    }

    var revision: AnyHashable { whatsNewSince }

    func contributions(for query: String) -> [Contribution] {
        var contributions: [Contribution] = [
            .listed(
                .command(
                    .settings, id: "command:settings", title: String(localized: "Settings"),
                    icon: .symbol("gearshape"))),
            .listed(
                .command(
                    .changelog, id: "command:changelog", title: String(localized: "Changelog"),
                    icon: .symbol("list.bullet.rectangle"))),
            .listed(
                .command(
                    .shareWhippet, id: "command:share-whippet",
                    title: String(localized: "Share Whippet with a Friend"), icon: .symbol("square.and.arrow.up"))),
        ]
        // Quitting isn't counted, so it never becomes a suggestion or a favorite.
        var quit = LauncherItem.command(
            .quit, id: "command:quit", title: String(localized: "Quit Whippet"),
            icon: .symbol("power"))
        quit.launchKey = nil
        quit.favoriteKey = nil
        contributions.append(.listed(quit))
        if let release = whatsNewSince.flatMap({
            Changelog.changes(after: $0, upTo: Self.currentVersion, in: Changelog.shipped)
        }) {
            let item = LauncherItem(
                id: "whats-new:\(release.id)", module: manifest.id,
                title: String(localized: "What's New in \(release.version)"),
                subtitle: String(localized: "Changes since \(release.since ?? "")"), icon: .symbol("sparkles"),
                refs: [.whatsNew], isBanner: true, payload: release)
            contributions.append(.top(item, section: String(localized: "Whippet Updated"), rank: 0))
        }
        return contributions
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        if let release = item.payload(as: Release.self) {
            return [
                ItemAction(
                    id: "whats-new.show", title: String(localized: "Show Changes"), icon: "return",
                    owner: .whatsNew
                ) { [weak self] in
                    self?.dismissWhatsNew()
                    return .push(ChangelogScreen(whatsNew: release))
                },
                ItemAction(
                    id: "whats-new.dismiss", title: String(localized: "Dismiss"), icon: "xmark",
                    shortcut: .delete, owner: .whatsNew
                ) { [weak self] in
                    self?.dismissWhatsNew()
                    return .removed
                },
            ]
        }
        switch item.id {
        case "command:settings":
            return [
                .open(owner: .settings) { [weak host] in
                    host?.openSettings(nil)
                    return .stay
                }
            ]
        case "command:changelog":
            return [
                .open(owner: .changelog) { .push(ChangelogScreen()) },
                ItemAction(
                    id: "changelog.browser", title: String(localized: "Open in Browser"), icon: "safari",
                    shortcut: .commandReturn, owner: .changelog
                ) {
                    NSWorkspace.shared.open(Self.changelogURL)
                    return .dismiss
                },
            ]
        case "command:share-whippet":
            return [
                .command(String(localized: "Copy Link"), owner: .shareWhippet) { [clipboard] in
                    ShareLink.copy(using: clipboard)
                    return .dismiss
                }
            ]
        default:
            return [
                ItemAction(id: "whippet.quit", title: String(localized: "Quit"), icon: "power", owner: .quit) {
                    NSApp.terminate(nil)
                    return .stay
                }
            ]
        }
    }

    private func dismissWhatsNew() {
        whatsNew.dismiss()
        whatsNewSince = nil
    }

    func run(command: String) {
        switch command {
        case "settings": host?.openSettings(nil)
        case "changelog": host?.openDirectly { host?.push(ChangelogScreen()) }
        case "share-whippet": ShareLink.copy(using: clipboard)
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }
}

/// Every version, newest first, beside the selected version's changes. Opened from What's New, the versions since the
/// update come first, gathered into one.
@MainActor
final class ChangelogScreen: LauncherScreen {
    private let whatsNew: Release?

    init(whatsNew: Release? = nil) {
        self.whatsNew = whatsNew
    }

    let id = "changelog"

    var searchBar: SearchBar {
        .field(placeholder: String(localized: "Type to filter changes…"))
    }

    var revision: AnyHashable { 0 }

    var content: ScreenContent {
        .custom(AnyView(ChangelogView()))
    }

    var footer: ScreenFooter {
        .actions(
            badge: CommandBadge(
                title: String(localized: "Changelog"), symbol: "list.bullet.rectangle.fill", tint: .indigo))
    }

    func items(for query: String) -> [LauncherItem] {
        let words = query.split(whereSeparator: \.isWhitespace)
        return ((whatsNew.map { [$0] } ?? []) + Changelog.shipped)
            .filter { release in words.allSatisfy { release.searchText.localizedStandardContains($0) } }
            .map { release in
                LauncherItem(
                    id: "release:\(release.id)", module: ModuleManifest.whippet.id, title: Self.title(of: release),
                    subtitle: Self.subtitle(of: release), icon: .symbol(release.since == nil ? "tag" : "sparkles"),
                    payload: release)
            }
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        guard let release = item.payload(as: Release.self) else { return [] }
        return [
            ItemAction(id: "release.browser", title: String(localized: "Open in Browser"), icon: "safari") {
                let url =
                    release.since == nil
                    ? WhippetModule.releasesURL.appending(path: "tag/v\(release.version)") : WhippetModule.releasesURL
                NSWorkspace.shared.open(url)
                return .dismiss
            }
        ]
    }

    static func title(of release: Release) -> String {
        release.since == nil ? release.version : String(localized: "What's New")
    }

    static func subtitle(of release: Release) -> String {
        release.since.map { String(localized: "Changes since \($0)") }
            ?? release.date?.formatted(date: .abbreviated, time: .omitted) ?? ""
    }
}
