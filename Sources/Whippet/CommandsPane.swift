import AppKit
import SwiftUI
import WhippetCore

/// Settings › Commands: every module in a list, as System Settings lists apps under Notifications. Each opens a page
/// with a switch for it and for each of its commands and features, and what each one uses, so anything the user
/// doesn't want can be turned off. Hotkeys are set in Settings › Shortcuts.
struct CommandsPane: View {
    let modules: ModuleSettings
    let featureFlags: FeatureFlags
    let appIndex: AppIndex
    let quicklinks: Quicklinks
    let extensions: ExtensionManager
    @Bindable var clipboard: ClipboardHistory
    @Bindable var cloudSync: CloudSync
    @Bindable var updater: Updater
    let navigation: SettingsNavigation
    /// Whether this account has the CloudKit Admin role, which lists Read Feedback.
    let showsAdminCommands: Bool
    @State private var path: [String] = []
    @State private var search = ""
    @State private var isShowingPermissions = false
    @State private var pendingApproval: InstalledExtension?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if search.isEmpty {
                    moduleList
                } else {
                    searchResults
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .navigationTitle("Commands")
            .searchable(text: $search, prompt: "Search commands")
            .toolbar {
                ToolbarItem {
                    Button("Permissions…", systemImage: "hand.raised") { isShowingPermissions = true }
                        .help("What each command and feature uses, by permission")
                }
            }
            .navigationDestination(for: String.self) { id in
                if let module = allRows.first(where: { $0.id == id }) {
                    detail(for: module)
                }
            }
        }
        .sheet(isPresented: $isShowingPermissions) {
            PermissionsSheet(
                rows: allRows, isOn: { binding(for: $0) }, canChange: canChange(_:), lock: lock(for:))
        }
        .alert(
            approvalTitle, isPresented: Binding(get: { pendingApproval != nil }, set: { _ in pendingApproval = nil }),
            presenting: pendingApproval
        ) { installed in
            Button("Turn On") { extensions.enable(installed) }
            Button("Cancel", role: .cancel) {}
        } message: { installed in
            Text(installed.manifest.permissions.descriptions.map { "• \($0)" }.joined(separator: "\n"))
        }
        // Leaving the pane, or a module disappearing as its beta feature turns off, goes back to the list.
        .onChange(of: allRows.map(\.id)) { _, ids in
            path.removeAll { !ids.contains($0) }
        }
    }

    // MARK: - The list

    private var moduleList: some View {
        let rows = allRows
        let builtIn = rows.filter { !$0.isExtension }
        let installed = rows.filter(\.isExtension)
        return Form {
            Section {
                ForEach(builtIn) { module in
                    moduleLink(module)
                }
            } footer: {
                Text(
                    "Turn off what you don't want. What's off does no work. Hotkeys are set in Settings › Shortcuts."
                )
                .foregroundStyle(.secondary)
            }
            if !installed.isEmpty {
                Section("Extensions") {
                    ForEach(installed) { module in
                        moduleLink(module)
                    }
                }
            }
        }
    }

    /// A module's row, as a switch row in the other panes, whose label opens the module's page, with a chevron after
    /// the switch that opens it too. The symbols of what it uses are beside the switch. A module that has to stay on
    /// shows that in place of its switch.
    private func moduleLink(_ module: CommandRow) -> some View {
        let label = HStack(spacing: 12) {
            Button {
                path.append(module.id)
            } label: {
                HStack(spacing: 10) {
                    ModuleIcon(row: module, size: 26)
                    RowLabel(row: module, lock: lock(for: module))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            PermissionBadges.space(for: module.permissions)
        }
        .centersSwitch()
        return HStack(spacing: 10) {
            switchRow(module) { label }
                .permissionBadges(module.permissions) { users(of: $0, in: module) }
            Button {
                path.append(module.id)
            } label: {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Show \(module.title)"))
        }
    }

    /// Commands and features whose names match, under their modules, and modules whose names match.
    private var searchResults: some View {
        let words = search.split(whereSeparator: \.isWhitespace)
        let matches = { (row: CommandRow) in
            words.allSatisfy { word in
                row.title.localizedStandardContains(word) || row.summary?.localizedStandardContains(word) == true
            }
        }
        let modules = allRows.filter(matches)
        let sections = allRows.compactMap { module -> (CommandRow, [CommandRow])? in
            let rows = (module.children ?? []).filter(matches)
            return rows.isEmpty ? nil : (module, rows)
        }
        return Form {
            if !modules.isEmpty {
                Section {
                    ForEach(modules) { module in
                        moduleLink(module)
                    }
                }
            }
            ForEach(sections, id: \.0.id) { module, rows in
                Section(module.title) {
                    ForEach(rows) { row in
                        itemRow(row)
                    }
                }
            }
        }
        .overlay {
            if modules.isEmpty, sections.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    // MARK: - A module's page

    private func detail(for module: CommandRow) -> some View {
        let children = module.children ?? []
        let commands = children.filter { $0.kind == .command }
        let features = children.filter { $0.kind == .feature }
        let dynamic = children.filter { $0.kind == .dynamic }
        return Form {
            Section {
                switchRow(module) {
                    HStack(alignment: .top, spacing: 12) {
                        ModuleIcon(row: module, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(module.title)
                                .font(.headline)
                            if let summary = module.summary {
                                Text(summary)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let lock = lock(for: module) {
                                Label(lock.reason, systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .centersSwitch()
                }
            }
            if !module.permissions.isEmpty {
                Section("Uses") {
                    ForEach(module.permissions, id: \.self) { permission in
                        PermissionRow(permission: permission, users: users(of: permission, in: module))
                    }
                }
            }
            if !commands.isEmpty {
                Section("Commands") {
                    ForEach(commands) { row in
                        itemRow(row)
                    }
                }
            }
            if !features.isEmpty {
                Section("Features") {
                    ForEach(features) { row in
                        itemRow(row)
                    }
                }
            }
            if !dynamic.isEmpty {
                Section(module.ref == .applications ? "Applications" : "Quicklinks") {
                    ForEach(dynamic) { row in
                        itemRow(row)
                    }
                }
            }
            if module.isExtension {
                Section {
                    Button("Open Settings › Extensions") { navigation.pane = .extensions }
                } footer: {
                    Text("Preferences, its log and uninstalling are in Settings › Extensions.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .navigationTitle(module.title)
    }

    /// A command or feature: its name and what it does, then the symbols of what it uses and its switch.
    private func itemRow(_ row: CommandRow) -> some View {
        switchRow(row) {
            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ModuleIcon(row: row, size: 18)
                    RowLabel(row: row, lock: lock(for: row))
                }
                Spacer(minLength: 0)
                PermissionBadges.space(for: row.permissions)
            }
            .centersSwitch()
        }
        .permissionBadges(row.permissions)
        .opacity(isModuleOn(row) ? 1 : 0.5)
    }

    /// A row's switch, or, for something that has to stay on, such as Settings or a running timer, “On” with a lock in
    /// its place: a disabled switch would grey out the whole row as if it were off. A row whose module is off keeps its
    /// disabled switch.
    @ViewBuilder
    private func switchRow(_ row: CommandRow, @ViewBuilder label: () -> some View) -> some View {
        if isModuleOn(row), !canChange(row) {
            HStack(spacing: 12) {
                label()
                Spacer(minLength: 0)
                Label("On", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            .help(help(for: row))
        } else {
            Toggle(isOn: binding(for: row)) { label() }
                .disabled(!canChange(row))
                .help(help(for: row))
        }
    }

    /// The commands and features in a module that use a permission.
    private func users(of permission: Permission, in module: CommandRow) -> [String] {
        guard !module.isExtension else { return [] }
        return (module.children ?? []).filter { row in
            row.permissions.contains { $0.kind == permission.kind }
        }.map(\.title)
    }

    // MARK: - Rows

    private var allRows: [CommandRow] {
        let builtIn = ModuleRegistry.builtIn.filter { manifest in
            manifest.flag.map(featureFlags.isEnabled) ?? true
        }.map(moduleRow)
        let installed = featureFlags.isEnabled(.extensions) ? extensions.installed.map(extensionRow) : []
        return builtIn + installed
    }

    private func moduleRow(_ manifest: ModuleManifest) -> CommandRow {
        let commands = manifest.commands.filter { !$0.isAdminOnly || showsAdminCommands }.map { command in
            let ref = manifest.ref(command.id)
            return CommandRow(
                id: "\(manifest.id)/\(command.id)", kind: .command, title: command.title, icon: .symbol(command.icon),
                permissions: command.permissions, ref: ref)
        }
        let features = manifest.features.map { feature in
            CommandRow(
                id: "\(manifest.id)/\(feature.id)", kind: .feature, title: feature.title, summary: feature.summary,
                icon: .none, permissions: feature.permissions, ref: manifest.ref(feature.id),
                storage: feature.isStoredElsewhere ? externalStorage(for: manifest.ref(feature.id)) : .settings)
        }
        let dynamic: [CommandRow] =
            switch manifest.dynamicRows {
            case .apps?:
                appIndex.apps.map { app in
                    CommandRow(
                        id: "app/\(app.stableID)", kind: .dynamic, title: app.name, icon: .file(app.url),
                        permissions: [], ref: .app(app.stableID))
                }
            case .quicklinks?:
                quicklinks.items.map { quicklink in
                    CommandRow(
                        id: "quicklink/\(quicklink.uuid)", kind: .dynamic, title: quicklink.name, icon: .symbol("link"),
                        permissions: [], ref: .quicklink(quicklink.uuid))
                }
            case nil: []
            }
        return CommandRow(
            id: manifest.id, kind: .module, title: manifest.title, summary: manifest.summary,
            icon: .tile(manifest.icon, manifest.tint.color), permissions: manifest.permissions, ref: manifest.ref,
            children: commands + features + dynamic)
    }

    /// An extension is turned on by approving what its manifest asks for, as in Settings › Extensions.
    private func extensionRow(_ installed: InstalledExtension) -> CommandRow {
        let manifest = installed.manifest
        let module = "extension.\(installed.id)"
        let commands = manifest.commands.map { command in
            CommandRow(
                id: "\(module)/\(command.name)", kind: .command, title: command.title, summary: command.subtitle,
                icon: .extension(command.icon ?? manifest.icon, installed.directory), permissions: [],
                ref: ModuleRef(module: module, row: command.name))
        }
        let status = extensions.status(of: installed)
        return CommandRow(
            id: module, kind: .module, title: manifest.name,
            summary: status == .needsApproval
                ? String(localized: "This version asks for more access. Turn it on again to allow it.")
                : manifest.description,
            icon: .extension(manifest.icon, installed.directory), permissions: manifest.permissions.permissions,
            ref: ModuleRef(module: module), storage: .extensionApproval(installed), children: commands)
    }

    /// Features whose switch belongs to a service, so this switch and the one in its pane stay the same.
    private func externalStorage(for ref: ModuleRef) -> CommandRow.Storage {
        switch ref {
        case .linkPreviews: .external($clipboard.fetchesLinkPreviews)
        case .iCloudSync: .external($cloudSync.isEnabled)
        case .automaticUpdateChecks: .external($updater.automaticallyChecksForUpdates)
        default: .settings
        }
    }

    // MARK: - Switches

    private func binding(for row: CommandRow) -> Binding<Bool> {
        switch row.storage {
        case .settings:
            Binding(get: { modules.isOn(row.ref) }, set: { modules.setOn(row.ref, $0) })
        case .external(let binding):
            binding
        case .extensionApproval(let installed):
            Binding(
                get: { extensions.status(of: installed) == .enabled },
                set: { isOn in
                    if !isOn {
                        extensions.disable(installed)
                    } else if installed.manifest.permissions.isEmpty {
                        extensions.enable(installed)
                    } else {
                        pendingApproval = installed
                    }
                })
        }
    }

    /// The extension a row belongs to, if it's in one.
    private func installedExtension(for row: CommandRow) -> InstalledExtension? {
        guard row.ref.module.hasPrefix("extension.") else { return nil }
        return extensions.installed(id: String(row.ref.module.dropFirst("extension.".count)))
    }

    /// Whether the row's module is on, so the row can work. An extension is on once what it asks for is approved.
    private func isModuleOn(_ row: CommandRow) -> Bool {
        guard row.ref.row != nil else { return true }
        if let installed = installedExtension(for: row) {
            return extensions.status(of: installed) == .enabled
        }
        return modules.isOn(row.ref.moduleRef)
    }

    /// A row is greyed out while its module is off, and can't be turned off while it's required or in use.
    private func canChange(_ row: CommandRow) -> Bool {
        guard isModuleOn(row) else { return false }
        guard binding(for: row).wrappedValue else { return true }
        if case .external = row.storage {
            return lock(for: row) == nil
        }
        return !modules.isRequired(row.ref) && lock(for: row) == nil
    }

    private func lock(for row: CommandRow) -> ActivityLock? {
        modules.lock(for: row.ref)
    }

    private func help(for row: CommandRow) -> String {
        if modules.isRequired(row.ref) {
            return String(localized: "Always on, so Settings can be reached from the search")
        }
        return lock(for: row)?.reason ?? ""
    }

    private var approvalTitle: String {
        guard let pendingApproval else { return "" }
        return String(localized: "Allow “\(pendingApproval.manifest.name)” to:")
    }
}

/// A module, or one of its commands or features, in Settings › Commands.
struct CommandRow: Identifiable {
    enum Kind {
        case module
        case command
        case feature
        /// An app or a quicklink.
        case dynamic
    }

    enum Icon {
        case none
        case symbol(String)
        /// A white symbol on a coloured tile, as Settings' sidebar draws panes.
        case tile(String, Color)
        /// An app's icon from its bundle.
        case file(URL)
        /// An extension's icon: a symbol, an emoji or an image in its folder.
        case `extension`(String?, URL)
    }

    /// Where the row's switch is kept.
    enum Storage {
        case settings
        /// By the service it belongs to, such as Cloud Sync's own switch.
        case external(Binding<Bool>)
        /// By approving what an extension's manifest asks for.
        case extensionApproval(InstalledExtension)
    }

    let id: String
    let kind: Kind
    let title: String
    var summary: String?
    let icon: Icon
    let permissions: [Permission]
    let ref: ModuleRef
    var storage = Storage.settings
    var children: [CommandRow]?

    var isExtension: Bool {
        if case .extensionApproval = storage { return true }
        return false
    }
}

extension ModuleTint {
    var color: Color {
        switch self {
        case .blue: .blue
        case .brown: .brown
        case .cyan: .cyan
        case .gray: .gray
        case .green: .green
        case .indigo: .indigo
        case .mint: .mint
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .red: .red
        case .teal: .teal
        }
    }
}

private struct ModuleIcon: View {
    let row: CommandRow
    let size: CGFloat

    var body: some View {
        switch row.icon {
        case .none:
            EmptyView()
        case .symbol(let name):
            Image(systemName: name)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        case .tile(let name, let tint):
            PaneIcon(symbol: name, tint: tint, size: size)
        case .file(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: size, height: size)
        case .extension(let name, let directory):
            ExtensionIcon(name: name, directory: directory)
                .frame(width: size, height: size)
        }
    }
}

/// A row's name, with what it does under it, or what's keeping it on while something is in use.
private struct RowLabel: View {
    let row: CommandRow
    let lock: ActivityLock?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
            if let lock {
                Label(lock.reason, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let summary = row.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The symbols of what a module, command or feature uses, beside its switch, as System Settings › Sharing puts an
/// info button beside each service. A permission macOS hasn't given yet is orange. Clicking them shows what each one
/// allows, and whether macOS has given it.
private struct PermissionBadges: View {
    let permissions: [Permission]
    /// The commands and features that use a permission, for a whole module's symbols.
    var users: (Permission) -> [String] = { _ in [] }
    @State private var isShowingDetails = false

    var body: some View {
        if !permissions.isEmpty {
            Button {
                isShowingDetails = true
            } label: {
                HStack(spacing: 6) {
                    ForEach(permissions, id: \.self) { permission in
                        Image(systemName: permission.kind.symbol)
                            .foregroundStyle(
                                PermissionStatus(permission: permission).isGranted == false ? .orange : .secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Uses \(names)"))
            .accessibilityLabel(Text("Uses \(names)"))
            .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(permissions, id: \.self) { permission in
                        PermissionDetail(permission: permission, users: users(permission))
                    }
                }
                .padding(16)
                .frame(width: 320, alignment: .leading)
            }
        }
    }

    private var names: String {
        permissions.map(\.kind.title).formatted(.list(type: .and))
    }

    /// The room the symbols take in a switch's label, where `permissionBadges(_:users:)` draws them.
    static func space(for permissions: [Permission]) -> some View {
        PermissionBadges(permissions: permissions)
            .hidden()
            .anchorPreference(key: BadgeSpace.self, value: .bounds) { $0 }
    }
}

/// Where a switch's label left room for its permission symbols.
private struct BadgeSpace: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Centres a form's switch beside its label, which would otherwise line up with the label's first line and look
    /// off beside an icon and two lines of text. The switch lines up its baseline, which is 4.5 points below its
    /// middle, with the label's, so the label's baseline is moved to that far below its own middle. A custom toggle
    /// style could centre it too, but its switch then hides the buttons in its label from VoiceOver.
    fileprivate func centersSwitch() -> some View {
        alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
    }

    /// Draws permission symbols over the room `PermissionBadges.space(for:)` left in a switch's label. They're drawn
    /// over the switch rather than in its label, where a button gets no clicks, and they can be clicked while the
    /// switch is disabled. A switch beside its label instead doesn't respond to VoiceOver.
    fileprivate func permissionBadges(
        _ permissions: [Permission], users: @escaping (Permission) -> [String] = { _ in [] }
    ) -> some View {
        overlayPreferenceValue(BadgeSpace.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let rect = proxy[anchor]
                    PermissionBadges(permissions: permissions, users: users)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
    }
}

/// One permission in the popover beside a switch: what it allows, which commands and features use it, and, for those
/// macOS gives, whether it has, with a way to System Settings.
private struct PermissionDetail: View {
    let permission: Permission
    let users: [String]

    var body: some View {
        let status = PermissionStatus(permission: permission)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: permission.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(permission.kind.title)
                    .font(.headline)
                Text(permission.detail)
                    .foregroundStyle(.secondary)
                if !users.isEmpty {
                    Text("Used by \(users.formatted(.list(type: .and)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if status.isGranted == true {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if status.isGranted == false, let settingsURL = status.settingsURL {
                    Button("Allow…") { NSWorkspace.shared.open(settingsURL) }
                        .padding(.top, 2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A permission a module uses, in its Uses section: what it allows, which of its commands and features use it, and,
/// for those macOS gives, whether it has, with a way to System Settings.
private struct PermissionRow: View {
    let permission: Permission
    let users: [String]

    var body: some View {
        let status = PermissionStatus(permission: permission)
        LabeledContent {
            if status.isGranted == true {
                Text("Allowed")
                    .foregroundStyle(.secondary)
            } else if status.isGranted == false, let settingsURL = status.settingsURL {
                Button("Allow…") { NSWorkspace.shared.open(settingsURL) }
            }
        } label: {
            Label {
                Text(permission.kind.title)
                Text(permission.detail)
                if !users.isEmpty {
                    Text("Used by \(users.formatted(.list(type: .and)))")
                }
            } icon: {
                Image(systemName: permission.kind.symbol)
                    .foregroundStyle(status.isGranted == false ? .orange : .secondary)
            }
        }
    }
}

/// Whether macOS has given Whippet a permission, for those it asks the user for, and where in System Settings to
/// give it.
@MainActor
private struct PermissionStatus {
    let permission: Permission

    /// Nil for permissions whose state can't be read straight away, such as Automation, which macOS asks about the
    /// first time it's used.
    var isGranted: Bool? {
        switch permission {
        case .accessibility: Paster.isTrusted
        case .screenRecording: ScreenCapture.isAllowed
        default: nil
        }
    }

    var settingsURL: URL? {
        let privacy = "x-apple.systempreferences:com.apple.preference.security?"
        return switch permission {
        case .accessibility: URL(string: privacy + "Privacy_Accessibility")
        case .screenRecording: URL(string: privacy + "Privacy_ScreenCapture")
        case .automation: URL(string: privacy + "Privacy_Automation")
        case .notifications: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        default: nil
        }
    }
}

/// Every command and feature, grouped by what they use, such as everything that connects to the network.
private struct PermissionsSheet: View {
    let rows: [CommandRow]
    let isOn: (CommandRow) -> Binding<Bool>
    let canChange: (CommandRow) -> Bool
    let lock: (CommandRow) -> ActivityLock?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(Permission.Kind.allCases, id: \.self) { kind in
                    let users = users(of: kind)
                    if !users.isEmpty {
                        Section {
                            ForEach(users, id: \.row.id) { module, row, permission in
                                Toggle(isOn: isOn(row)) {
                                    Text(module == row.title ? row.title : "\(module) › \(row.title)")
                                    Text(lock(row)?.reason ?? permission.detail)
                                }
                                .disabled(!canChange(row))
                            }
                        } header: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 560)
    }

    /// The commands and features that use a kind of permission, each with its module's name. An extension asks as a
    /// whole, so it's listed itself.
    private func users(of kind: Permission.Kind) -> [(module: String, row: CommandRow, permission: Permission)] {
        rows.flatMap { module -> [(module: String, row: CommandRow, permission: Permission)] in
            if module.isExtension {
                return module.permissions.filter { $0.kind == kind }.map { (module.title, module, $0) }
            }
            return (module.children ?? []).flatMap { row in
                row.permissions.filter { $0.kind == kind }.map { (module.title, row, $0) }
            }
        }
    }
}
