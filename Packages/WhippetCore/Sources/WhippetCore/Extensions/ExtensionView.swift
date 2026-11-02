import Foundation

/// A host element as the extension's renderer serializes it: `list`, `list-item`, `action` and so on, with its props.
/// Functions in props arrive as `{ "$handler": id }`, which Whippet sends back to run them.
public struct ExtensionNode: Decodable, Hashable, Sendable {
    public let id: Int
    public let type: String
    public let props: [String: JSONValue]
    public let children: [ExtensionNode]

    public init(id: Int, type: String, props: [String: JSONValue] = [:], children: [ExtensionNode] = []) {
        self.id = id
        self.type = type
        self.props = props
        self.children = children
    }

    /// Reads a node from what `JSONSerialization` returns.
    init?(object: [String: Any]) {
        guard let id = object["id"] as? Int, let type = object["type"] as? String else { return nil }
        self.id = id
        self.type = type
        props = (object["props"] as? [String: Any] ?? [:]).mapValues(JSONValue.init(object:))
        children = (object["children"] as? [[String: Any]] ?? []).compactMap(ExtensionNode.init(object:))
    }

    func string(_ key: String) -> String? {
        props[key]?.string
    }

    func bool(_ key: String) -> Bool? {
        props[key]?.bool
    }

    /// The id of the function in a prop, such as `onAction`.
    func handler(_ key: String) -> String? {
        props[key]?["$handler"]?.string
    }

    /// The actions in this element's `action-panel`, in order, with section titles kept.
    var actions: [ExtensionAction] {
        guard let panel = children.first(where: { $0.type == "action-panel" }) else { return [] }
        return panel.children.flatMap { child -> [ExtensionAction] in
            switch child.type {
            case "action": return ExtensionAction(child).map { [$0] } ?? []
            case "action-panel-section":
                let title = child.string("title")
                return child.children.compactMap { ExtensionAction($0, section: title) }
            default: return []
            }
        }
    }
}

/// What a command shows: the top view of its navigation stack.
public enum ExtensionView: Hashable, Sendable {
    /// Nothing rendered yet.
    case loading
    case list(ExtensionList)
    case detail(ExtensionDetail)
    case form(ExtensionForm)

    /// Reads the `view` element the renderer sends, which wraps one list, detail or form.
    public init(_ node: ExtensionNode?) {
        guard let node else {
            self = .loading
            return
        }
        let content = node.type == "view" ? node.children.first : node
        switch content?.type {
        case "list": self = .list(ExtensionList(content!))
        case "detail": self = .detail(ExtensionDetail(content!))
        case "form": self = .form(ExtensionForm(content!))
        default: self = .loading
        }
    }

    public var navigationTitle: String? {
        switch self {
        case .loading: nil
        case .list(let list): list.navigationTitle
        case .detail(let detail): detail.navigationTitle
        case .form(let form): form.navigationTitle
        }
    }

    public var isLoading: Bool {
        switch self {
        case .loading: true
        case .list(let list): list.isLoading
        case .detail(let detail): detail.isLoading
        case .form(let form): form.isLoading
        }
    }

    /// The view's own actions: a detail's or a form's, or an empty list's.
    public var actions: [ExtensionAction] {
        switch self {
        case .loading: []
        case .list(let list): list.actions
        case .detail(let detail): detail.actions
        case .form(let form): form.actions
        }
    }
}

public struct ExtensionList: Hashable, Sendable {
    public let isLoading: Bool
    public let navigationTitle: String?
    public let searchBarPlaceholder: String?
    /// Whippet filters the items by the search text itself, rather than leaving it to the extension.
    public let filtering: Bool
    public let throttle: Bool
    public let searchTextHandler: String?
    public let items: [ExtensionListItem]
    public let actions: [ExtensionAction]

    init(_ node: ExtensionNode) {
        isLoading = node.bool("isLoading") ?? false
        navigationTitle = node.string("navigationTitle")
        searchBarPlaceholder = node.string("searchBarPlaceholder")
        filtering = node.bool("filtering") ?? true
        throttle = node.bool("throttle") ?? false
        searchTextHandler = node.handler("onSearchTextChange")
        actions = node.actions
        var items: [ExtensionListItem] = []
        for child in node.children {
            switch child.type {
            case "list-item":
                items.append(ExtensionListItem(child, section: nil, position: items.count))
            case "list-section":
                let title = child.string("title")
                for item in child.children where item.type == "list-item" {
                    items.append(ExtensionListItem(item, section: title, position: items.count))
                }
            default: break
            }
        }
        self.items = items
    }
}

public struct ExtensionListItem: Hashable, Sendable {
    /// The extension's own id for the item, or one from its position, which keeps it selected as the list changes.
    public let id: String
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let accessories: [ExtensionAccessory]
    public let keywords: [String]
    public let section: String?
    public let actions: [ExtensionAction]

    init(_ node: ExtensionNode, section: String?, position: Int) {
        id = node.string("id") ?? "position:\(position)"
        title = node.string("title") ?? ""
        subtitle = node.string("subtitle")
        icon = node.string("icon")
        accessories = (node.props["accessories"]?.array ?? []).map {
            ExtensionAccessory(text: $0["text"]?.string, icon: $0["icon"]?.string)
        }
        keywords = (node.props["keywords"]?.array ?? []).compactMap(\.string)
        self.section = section
        actions = node.actions
    }

    /// What Whippet's own filtering matches: the title, subtitle and keywords.
    public var searchText: String {
        ([title, subtitle] + keywords).compactMap { $0 }.joined(separator: " ")
    }
}

public struct ExtensionAccessory: Hashable, Sendable {
    public let text: String?
    public let icon: String?
}

public struct ExtensionDetail: Hashable, Sendable {
    public let markdown: String
    public let navigationTitle: String?
    public let isLoading: Bool
    public let actions: [ExtensionAction]

    init(_ node: ExtensionNode) {
        markdown = node.string("markdown") ?? ""
        navigationTitle = node.string("navigationTitle")
        isLoading = node.bool("isLoading") ?? false
        actions = node.actions
    }
}

public struct ExtensionForm: Hashable, Sendable {
    public let navigationTitle: String?
    public let isLoading: Bool
    public let fields: [ExtensionFormField]
    public let actions: [ExtensionAction]

    init(_ node: ExtensionNode) {
        navigationTitle = node.string("navigationTitle")
        isLoading = node.bool("isLoading") ?? false
        fields = node.children.filter { $0.type == "form-field" }.compactMap(ExtensionFormField.init)
        actions = node.actions
    }
}

public struct ExtensionFormField: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case text, textarea, password, checkbox, dropdown
    }

    public struct Option: Hashable, Sendable {
        public let value: String
        public let title: String
    }

    public let id: String
    public let kind: Kind
    public let title: String?
    public let placeholder: String?
    /// A checkbox's text beside it.
    public let label: String?
    public let defaultValue: JSONValue?
    /// Set when the extension controls the value, replacing what's in the field.
    public let value: JSONValue?
    public let changeHandler: String?
    public let options: [Option]

    init?(_ node: ExtensionNode) {
        guard let id = node.string("id"), let kind = node.string("kind").flatMap(Kind.init) else { return nil }
        self.id = id
        self.kind = kind
        title = node.string("title")
        placeholder = node.string("placeholder")
        label = node.string("label")
        defaultValue = node.props["defaultValue"]
        value = node.props["value"]
        changeHandler = node.handler("onChange")
        options = node.children.filter { $0.type == "form-option" }.compactMap { option in
            guard let value = option.string("value") else { return nil }
            return Option(value: value, title: option.string("title") ?? value)
        }
    }

    /// The value a new field starts with: its default, or empty, unchecked or the first option.
    public var initialValue: JSONValue {
        if let value { return value }
        if let defaultValue { return defaultValue }
        switch kind {
        case .checkbox: return .bool(false)
        case .dropdown: return options.first.map { .string($0.value) } ?? .string("")
        default: return .string("")
        }
    }
}

public struct ExtensionAction: Hashable, Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let icon: String?
    public let shortcut: ExtensionShortcut?
    public let isDestructive: Bool
    /// Passes the form's values to the handler.
    public let submitsForm: Bool
    public let handler: String?
    /// The title of the `ActionPanel.Section` it's in.
    public let section: String?

    init?(_ node: ExtensionNode, section: String? = nil) {
        guard node.type == "action", let title = node.string("title") else { return nil }
        id = node.id
        self.title = title
        icon = node.string("icon")
        shortcut = node.props["shortcut"].flatMap(ExtensionShortcut.init)
        isDestructive = node.string("style") == "destructive"
        submitsForm = node.bool("submitsForm") ?? false
        handler = node.handler("onAction")
        self.section = section
    }
}

/// A key with modifiers, as an extension writes it: `{ "modifiers": ["cmd", "shift"], "key": "o" }`.
public struct ExtensionShortcut: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let shift = Modifiers(rawValue: 2)
        public static let option = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8)
    }

    public let key: String
    public let modifiers: Modifiers

    public init(key: String, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    init?(_ value: JSONValue) {
        guard let key = value["key"]?.string?.lowercased(), key.count == 1 else { return nil }
        var modifiers: Modifiers = []
        for name in value["modifiers"]?.array?.compactMap(\.string) ?? [] {
            switch name {
            case "cmd", "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            default: break
            }
        }
        // Plain keys type into the search bar, so a shortcut needs ⌘ or ⌃.
        guard modifiers.contains(.command) || modifiers.contains(.control) else { return nil }
        self.key = key
        self.modifiers = modifiers
    }
}
