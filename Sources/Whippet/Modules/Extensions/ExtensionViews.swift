import AppKit
import SwiftUI
import WhippetCore

/// Where the open extension's files are, for icons named by file, and the hosts it may load images from.
struct ExtensionContext {
    var directory: URL?
    var permissions = ExtensionPermissions()
}

extension EnvironmentValues {
    @Entry var extensionContext = ExtensionContext()
}

/// An icon an extension names: an SF Symbol, an emoji, an image file in its folder, or an image URL on a host its
/// manifest lists. Other URLs aren't loaded, since a request carries whatever is in it out of the Mac.
struct ExtensionIcon: View {
    let name: String?
    var directory: URL?
    @Environment(\.extensionContext) private var context

    var body: some View {
        switch source {
        case .symbol(let symbol):
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: 17))
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        case .remote(let url):
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
        }
    }

    private enum Source {
        case symbol(String)
        case emoji(String)
        case image(NSImage)
        case remote(URL)
    }

    private static let fallback = Source.symbol("puzzlepiece.extension")

    private var source: Source {
        guard let name, !name.isEmpty else { return Self.fallback }
        if name.hasPrefix("https://"), let url = URL(string: name), let host = url.host(),
            context.permissions.allowsHost(host)
        {
            return .remote(url)
        }
        if let folder = directory ?? context.directory, name.contains(".") {
            let file = folder.appending(path: name).standardizedFileURL
            // Only files inside the extension's own folder.
            if file.path.hasPrefix(folder.standardizedFileURL.path + "/"), let image = NSImage(contentsOf: file) {
                return .image(image)
            }
        }
        if name.unicodeScalars.first?.properties.isEmojiPresentation == true
            || name.unicodeScalars.contains(where: { $0.properties.isEmoji && !$0.isASCII })
        {
            return .emoji(name)
        }
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return .symbol(name)
        }
        return Self.fallback
    }
}

/// An extension list item's accessories, at the end of its row.
struct ExtensionAccessories: View {
    let accessories: [ExtensionAccessory]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(accessories.enumerated()), id: \.offset) { _, accessory in
                HStack(spacing: 4) {
                    if let icon = accessory.icon {
                        ExtensionIcon(name: icon)
                            .frame(width: 13, height: 13)
                    }
                    if let text = accessory.text {
                        Text(text)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

/// The open view command: its list, detail or form.
struct ExtensionContent: View {
    @Environment(LauncherModel.self) private var host
    let screen: ExtensionScreen
    let permissions: ExtensionPermissions

    var body: some View {
        let session = screen.session
        Group {
            switch session.view {
            case .loading:
                VStack {
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .list:
                ResultsList()
                    .overlay {
                        if host.results.isEmpty, !session.view.isLoading {
                            Text("No Results")
                                .foregroundStyle(Color.launcherSecondary)
                        }
                    }
            case .detail(let detail):
                ScrollView {
                    MarkdownView(markdown: detail.markdown)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .form(let form):
                ExtensionFormView(session: session, form: form) { host.activate() }
            }
        }
        .environment(
            \.extensionContext, ExtensionContext(directory: session.command.directory, permissions: permissions))
    }
}

/// An extension's form, with Whippet keeping the values. Return in a one-line field submits, as ⌘Return does anywhere.
private struct ExtensionFormView: View {
    let session: ExtensionSession
    let form: ExtensionForm
    let submit: () -> Void
    @FocusState private var focused: String?

    var body: some View {
        ScrollView {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(form.fields) { field in
                    GridRow {
                        Text(field.title ?? "")
                            .foregroundStyle(Color.launcherSecondary)
                            .gridColumnAlignment(.trailing)
                        control(for: field)
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            // Waits a turn, so the fields are in the window before one takes focus.
            DispatchQueue.main.async { focused = form.fields.first { $0.kind != .checkbox }?.id }
        }
    }

    @ViewBuilder
    private func control(for field: ExtensionFormField) -> some View {
        switch field.kind {
        case .text:
            TextField(field.placeholder ?? "", text: text(field))
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: field.id)
                .onSubmit(submit)
        case .password:
            SecureField(field.placeholder ?? "", text: text(field))
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: field.id)
                .onSubmit(submit)
        case .textarea:
            TextEditor(text: text(field))
                .font(.body)
                .frame(minHeight: 80, maxHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .focused($focused, equals: field.id)
        case .checkbox:
            Toggle(field.label ?? "", isOn: bool(field))
                .toggleStyle(.checkbox)
        case .dropdown:
            Picker("", selection: text(field)) {
                ForEach(field.options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func text(_ field: ExtensionFormField) -> Binding<String> {
        Binding(
            get: { session.formValues[field.id]?.string ?? "" },
            set: { session.setValue(.string($0), of: field) })
    }

    private func bool(_ field: ExtensionFormField) -> Binding<Bool> {
        Binding(
            get: { session.formValues[field.id]?.bool ?? false },
            set: { session.setValue(.bool($0), of: field) })
    }
}

/// Markdown drawn block by block, since `Text` shows only inline styles: headings, paragraphs, lists, quotes, code
/// blocks and rules.
struct MarkdownView: View {
    let markdown: String
    @Environment(\.extensionContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.blocks(of: markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    private enum Kind: Equatable {
        case paragraph
        case heading(Int)
        case code
        case quote
        case listItem(marker: String, depth: Int)
        case rule
        /// An image on its own line, with its alt text.
        case image(URL)
    }

    private struct Block {
        let kind: Kind
        var text: AttributedString
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block.kind {
        case .paragraph:
            Text(block.text)
        case .heading(let level):
            Text(block.text)
                .font(.system(size: [24, 20, 17, 15, 14, 13][min(level, 6) - 1], weight: .semibold))
                .padding(.top, level <= 2 ? 4 : 0)
        case .code:
            ScrollView(.horizontal) {
                Text(block.text)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(10)
            }
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        case .quote:
            Text(block.text)
                .foregroundStyle(Color.launcherSecondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.launcherSecondary.opacity(0.5)).frame(width: 3)
                }
        case .listItem(let marker, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .foregroundStyle(Color.launcherSecondary)
                Text(block.text)
            }
            .padding(.leading, CGFloat(depth - 1) * 16)
        case .rule:
            Divider()
        case .image(let url):
            // Only from hosts the manifest lists, since loading an image sends a request; otherwise the alt text.
            if let host = url.host(), context.permissions.allowsHost(host) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: 240, maxHeight: 200, alignment: .leading)
                .accessibilityLabel(Text(block.text))
            } else {
                Text(block.text)
                    .foregroundStyle(Color.launcherSecondary)
            }
        }
    }

    /// Groups the parsed runs by the block they belong to, which `PresentationIntent` identifies.
    private static func blocks(of markdown: String) -> [Block] {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return [Block(kind: .paragraph, text: AttributedString(markdown))]
        }
        var blocks: [Block] = []
        var currentIntent: PresentationIntent?
        for run in parsed.runs {
            var text = AttributedString(parsed[run.range])
            if let url = run.imageURL {
                blocks.append(Block(kind: .image(url), text: text))
                // Text after the image in the same paragraph starts a block of its own.
                currentIntent = nil
                continue
            }
            if run.inlinePresentationIntent?.contains(.code) == true {
                text.font = .system(.body, design: .monospaced)
            }
            if let intent = run.presentationIntent, intent == currentIntent, !blocks.isEmpty {
                blocks[blocks.count - 1].text += text
                continue
            }
            currentIntent = run.presentationIntent
            blocks.append(Block(kind: kind(of: run.presentationIntent), text: text))
        }
        return blocks
    }

    private static func kind(of intent: PresentationIntent?) -> Kind {
        guard let intent else { return .paragraph }
        var listDepth = 0
        var marker: String?
        var ordered = false
        var kind = Kind.paragraph
        // Innermost first.
        for component in intent.components {
            switch component.kind {
            case .header(let level):
                kind = .heading(level)
            case .codeBlock:
                return .code
            case .blockQuote:
                if kind == .paragraph { kind = .quote }
            case .thematicBreak:
                return .rule
            case .listItem(let ordinal):
                if marker == nil { marker = "\(ordinal)" }
            case .orderedList:
                if listDepth == 0 { ordered = true }
                listDepth += 1
            case .unorderedList:
                listDepth += 1
            default:
                break
            }
        }
        if let marker, listDepth > 0 {
            return .listItem(marker: ordered ? "\(marker)." : "•", depth: listDepth)
        }
        return kind
    }
}
