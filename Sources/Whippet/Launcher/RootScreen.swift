import SwiftUI

/// The main search, made of every module's contributions. With an empty search: what's at the top, such as running
/// timers, then Favorites, Suggestions and everything else by section. While searching: what leads, the ranked matches,
/// then what the text can be used with. A module can take the search over, as the calculator does for `2+3`.
@MainActor
final class RootScreen: LauncherScreen {
    private unowned let host: any ModuleHost
    /// Every module, in the order their rows are listed. Only the main search asks them all; modules don't reach
    /// each other through the host.
    private let modules: () -> [any LauncherModule]
    /// The heading over each item and how many are pinned, set with the items.
    private var sections: [String] = []
    private var pinned = 0

    private static let suggestionLimit = 5

    init(host: any ModuleHost, modules: @escaping () -> [any LauncherModule]) {
        self.host = host
        self.modules = modules
    }

    let id = "root"

    var searchBar: SearchBar {
        .field(placeholder: String(localized: "Search apps and commands"))
    }

    var revision: AnyHashable {
        modules().map(\.revision)
    }

    func items(for query: String) -> [LauncherItem] {
        resolve(query).items
    }

    /// The items for `query`, or the screen a module took the search over with and its items.
    func resolve(_ query: String) -> (items: [LauncherItem], exclusive: (any LauncherScreen)?) {
        let on = modules().filter { host.modules.isEnabled($0.manifest.ref) }
        var contributions: [Contribution] = []
        for module in on {
            let theirs = module.contributions(for: query)
            for contribution in theirs {
                if case .exclusive(let screen) = contribution {
                    sections = []
                    pinned = 0
                    return (screen.items(for: query), screen)
                }
            }
            contributions += commandItems(of: module).map(Contribution.listed) + theirs
        }
        var listed: [LauncherItem] = []
        var tops: [(item: LauncherItem, section: String, rank: Int)] = []
        var leading: [LauncherItem] = []
        var fallbacks: [(item: LauncherItem, tier: Int)] = []
        var pinnedItems: [LauncherItem] = []
        for contribution in contributions {
            switch contribution {
            case .listed(let item) where isListed(item): listed.append(item)
            case .top(let item, let section, let rank) where isListed(item): tops.append((item, section, rank))
            case .leading(let item) where isListed(item): leading.append(item)
            case .fallback(let item, let tier) where isListed(item): fallbacks.append((item, tier))
            case .pinned(let item) where isListed(item): pinnedItems.append(item)
            default: break
            }
        }
        listed = Self.groupedBySection(listed)
        tops = tops.enumerated().sorted { lhs, rhs in
            lhs.element.rank != rhs.element.rank ? lhs.element.rank < rhs.element.rank : lhs.offset < rhs.offset
        }.map(\.element)

        guard query.isEmpty else {
            let ranked = Ranking.rank(
                tops.map(\.item) + listed, query: query, title: \.searchableText, frecency: frecency(of:))
            let fallbackItems = ordered(fallbacks)
            let usedWith = String(localized: "Use “\(query)” with…")
            let results = String(localized: "Results")
            // What the text can be used with comes straight under something pinned for it, such as its translation. Only
            // the pinned items stay put: there can be more fallbacks than fit under a card, so they scroll.
            if !pinnedItems.isEmpty {
                sections =
                    pinnedItems.map(\.section) + fallbackItems.map { _ in usedWith }
                    + (leading + ranked).map { _ in results }
                pinned = pinnedItems.count
                return (pinnedItems + fallbackItems + leading + ranked, nil)
            }
            sections = (leading + ranked).map { _ in results } + fallbackItems.map { _ in usedWith }
            pinned = 0
            return (leading + ranked + fallbackItems, nil)
        }

        let byFavoriteKey = Dictionary(
            listed.compactMap { item in item.favoriteKey.map { ($0, item) } }, uniquingKeysWith: { first, _ in first })
        // A favorite whose app was removed or whose command is gone is kept, in case it comes back, but not listed.
        let favorites = host.history.favorites.compactMap { byFavoriteKey[$0] }
        let favoriteIDs = Set(favorites.map(\.id))
        let others = listed.filter { !favoriteIDs.contains($0.id) }
        let suggestions = Ranking.suggestions(others, limit: Self.suggestionLimit, frecency: frecency(of:))
        let suggestedIDs = Set(suggestions.map(\.id))
        let rest = others.filter { !suggestedIDs.contains($0.id) }
        sections =
            tops.map(\.section) + favorites.map { _ in String(localized: "Favorites") }
            + suggestions.map { _ in String(localized: "Suggestions") } + rest.map(\.section)
        pinned = 0
        return (tops.map(\.item) + favorites + suggestions + rest, nil)
    }

    /// A module's commands as rows, made from its manifest and listed as the module says.
    private func commandItems(of module: any LauncherModule) -> [LauncherItem] {
        module.manifest.commands.compactMap { command in
            module.row(for: module.manifest.ref(command.id), .command(command, of: module.manifest))
        }
    }

    /// A command's row, or nil while it's off or its module leaves it out.
    func commandItem(_ ref: ModuleRef) -> LauncherItem? {
        guard host.modules.isEnabled(ref), let module = module(ref.module),
            let command = ref.row.flatMap(module.manifest.command)
        else { return nil }
        return module.row(for: ref, .command(command, of: module.manifest))
    }

    /// What `query` can be used with, from every module but `excluded`, as the Translate screen lists under it.
    func fallbacks(for query: String, excluding excluded: String) -> [LauncherItem] {
        let fallbacks = modules().filter { $0.id != excluded && host.modules.isEnabled($0.manifest.ref) }
            .flatMap { $0.contributions(for: query) }
            .compactMap { contribution -> (item: LauncherItem, tier: Int)? in
                guard case .fallback(let item, let tier) = contribution, isListed(item) else { return nil }
                return (item, tier)
            }
        return ordered(fallbacks)
    }

    /// Items of a section together, sections in the order they first appear, so a module adding rows to two sections,
    /// such as a command and its recent timers, doesn't split either.
    private static func groupedBySection(_ items: [LauncherItem]) -> [LauncherItem] {
        var order: [String: Int] = [:]
        for item in items where order[item.section] == nil {
            order[item.section] = order.count
        }
        return items.enumerated().sorted { lhs, rhs in
            let left = order[lhs.element.section] ?? 0
            let right = order[rhs.element.section] ?? 0
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Fallbacks by tier, the first tier by use. Favorite ones come first, in the order they were added.
    private func ordered(_ fallbacks: [(item: LauncherItem, tier: Int)]) -> [LauncherItem] {
        let sorted = fallbacks.enumerated().sorted { lhs, rhs in
            let (left, right) = (lhs.element, rhs.element)
            if left.tier != right.tier { return left.tier < right.tier }
            if left.tier == 0 {
                let (leftUse, rightUse) = (frecency(of: left.item), frecency(of: right.item))
                if leftUse != rightUse { return leftUse > rightUse }
            }
            return lhs.offset < rhs.offset
        }.map(\.element.item)
        let favoriteOrder = Dictionary(
            host.history.favorites.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let position = { (item: LauncherItem) in item.launchKey.flatMap { favoriteOrder[$0] } }
        let favorites = sorted.filter { position($0) != nil }.sorted { position($0)! < position($1)! }
        return favorites + sorted.filter { position($0) == nil }
    }

    private func isListed(_ item: LauncherItem) -> Bool {
        item.refs.allSatisfy(host.modules.isEnabled)
    }

    private func frecency(of item: LauncherItem) -> Double {
        item.launchKey.map { host.history.frecency(of: $0) } ?? 0
    }

    private func module(_ id: String) -> (any LauncherModule)? {
        modules().first { $0.id == id }
    }

    func actions(for item: LauncherItem) -> [ItemAction] {
        ownActions(for: item)
    }

    /// What an item's own module offers for it.
    func ownActions(for item: LauncherItem) -> [ItemAction] {
        module(item.module)?.actions(for: item) ?? []
    }

    func sectionTitle(at index: Int, in items: [LauncherItem]) -> String? {
        sections.indices.contains(index) ? sections[index] : nil
    }

    func pinnedCount(in items: [LauncherItem]) -> Int {
        pinned
    }

    func rowView(for item: LauncherItem, index: Int, isSelected: Bool) -> AnyView? {
        module(item.module)?.rowView(for: item, isSelected: isSelected)
    }

    func queryChanged(_ query: String) {
        for module in modules() {
            module.searchTextChanged(query)
        }
    }
}
