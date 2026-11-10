import AppKit
import KeyboardShortcuts
import WhippetCore

/// A row in the launcher: an app, a command, a clipboard item, a timer. Modules make them from what they show, and the
/// host lists, ranks and selects them without knowing what they are. `payload` holds the module's own value, which
/// it gets back with `payload(as:)` when the row is chosen.
struct LauncherItem: Identifiable, Hashable {
    /// Stable across launches for anything that can be a favorite, such as `command:calculator` or `app:<path>`.
    let id: String
    /// The module that made it, which is asked for its actions in screens it doesn't own, such as the main search.
    let module: String
    var title: String
    var subtitle = ""
    var icon: ItemIcon = .none
    /// The heading it's listed under in the empty search, after Favorites and Suggestions.
    var section = String(localized: "Commands")
    /// What search matches, when that's more than the title, such as a quicklink's keyword.
    var searchText: String?
    /// The key launches are recorded under, which ranks it by how often and how recently it's used.
    var launchKey: String?
    /// The key a favorite is kept under. Rows offered for the search text count as the command they stand for, but
    /// aren't favorites themselves.
    var favoriteKey: String?
    /// What has to be turned on in Settings › Commands for it to be listed.
    var refs: [ModuleRef] = []
    /// The hotkey shown beside it, and offered by Set Hotkey….
    var hotkey: KeyboardShortcuts.Name?
    /// Commands only an account with the CloudKit Admin role sees, shown with an Admin badge.
    var isAdminOnly = false
    /// The subtitle sits beside the title, leaving the end of the row for the module's own accessories.
    var subtitleBesideTitle = false
    /// The same thing as it changes, such as a timer that finishes, so it stays selected when its row changes.
    var selectionKey: String?
    /// Shown under the empty search bar while the list is hidden, when it leads the results, as What's New is.
    var isBanner = false
    /// The command in its module's manifest that it's the row of, such as `.startTimer`, which the module tells its
    /// commands apart by.
    var command: ModuleRef?
    var payload: AnyHashable?

    var searchableText: String {
        searchText ?? title
    }

    func payload<T>(as type: T.Type) -> T? {
        payload?.base as? T
    }
}

/// An item's icon.
enum ItemIcon: Hashable {
    case none
    /// An SF Symbol.
    case symbol(String)
    /// A symbol in the asset catalog, for one SF Symbols lacks.
    case assetSymbol(String)
    /// The Finder icon of a file or app.
    case file(URL)
    /// An extension's icon: a symbol, an emoji or an image in its folder.
    case `extension`(String?, URL?)
    /// An image a module has already loaded, such as a site's icon, compared by identity.
    case image(ImageBox)

    /// An `NSImage`, hashed by identity so items stay cheap to compare.
    struct ImageBox: Hashable {
        let image: NSImage

        static func == (lhs: ImageBox, rhs: ImageBox) -> Bool {
            lhs.image === rhs.image
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(image))
        }
    }
}

/// What an item holds, so other modules can offer actions on it without knowing what it is: Timers offers Start Timer
/// on anything with a duration, such as a calculation of `25 min`.
struct ItemTraits {
    var text: (() -> String?)?
    var url: URL?
    var fileURL: URL?
    /// Worked out when it's used, so a timer counting down to a moment starts from when it's chosen.
    var duration: (() -> Int?)?
}
