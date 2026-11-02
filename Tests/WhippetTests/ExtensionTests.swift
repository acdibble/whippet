import Foundation
import Testing

@testable import WhippetCore

struct ExtensionManifestTests {
    private func decode(_ json: String) throws -> ExtensionManifest {
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
        try manifest.validate()
        return manifest
    }

    @Test func readsAManifestWithDefaults() throws {
        let manifest = try decode(
            """
            {"id": "com.example.hello", "name": "Hello", "version": "1.0.0", "apiVersion": 1,
             "commands": [{"name": "hello", "title": "Say Hello"}]}
            """)
        #expect(manifest.permissions.isEmpty)
        #expect(manifest.preferences.isEmpty)
        #expect(manifest.commands.first?.mode == .view)
    }

    @Test func readsCommandsPermissionsAndPreferences() throws {
        let manifest = try decode(
            """
            {"id": "com.example.github", "name": "GitHub", "version": "1.0.0", "apiVersion": 1,
             "permissions": {"network": ["api.github.com"], "clipboard": true},
             "preferences": [{"name": "token", "title": "Token", "type": "secret", "required": true}],
             "commands": [
               {"name": "repos", "title": "Search Repositories"},
               {"name": "issue", "title": "Open Issue", "mode": "no-view",
                "argument": {"name": "number", "placeholder": "Number"}}
             ]}
            """)
        #expect(manifest.permissions == ExtensionPermissions(network: ["api.github.com"], clipboard: true))
        #expect(manifest.preferences.first?.type == .secret)
        #expect(manifest.preferences.first?.required == true)
        #expect(manifest.commands[1].mode == .noView)
        #expect(manifest.commands[1].argument == ExtensionArgument(name: "number", placeholder: "Number"))
    }

    @Test(arguments: [
        (
            #"{"id": "hello", "name": "Hello", "version": "1", "apiVersion": 1, "commands": [{"name": "a", "title": "A"}]}"#,
            ExtensionManifestError.invalidID("hello")
        ),
        (
            #"{"id": "com.x.y", "name": "Y", "version": "1", "apiVersion": 2, "commands": [{"name": "a", "title": "A"}]}"#,
            .unsupportedAPIVersion(2)
        ),
        (#"{"id": "com.x.y", "name": "Y", "version": "1", "apiVersion": 1, "commands": []}"#, .noCommands),
        (
            #"{"id": "com.x.y", "name": " ", "version": "1", "apiVersion": 1, "commands": [{"name": "a", "title": "A"}]}"#,
            .missingName
        ),
        (
            #"{"id": "com.x.y", "name": "Y", "version": "1", "apiVersion": 1, "commands": [{"name": "a-b", "title": "A"}]}"#,
            .invalidCommandName("a-b")
        ),
        (
            #"{"id": "com.x.y", "name": "Y", "version": "1", "apiVersion": 1, "commands": [{"name": "a", "title": "A"}, {"name": "a", "title": "B"}]}"#,
            .duplicateCommand("a")
        ),
        (
            #"{"id": "com.x.y", "name": "Y", "version": "1", "apiVersion": 1, "permissions": {"network": ["https://x.com"]}, "commands": [{"name": "a", "title": "A"}]}"#,
            .invalidHost("https://x.com")
        ),
    ])
    func rejectsInvalidManifests(_ json: String, _ error: ExtensionManifestError) {
        #expect(throws: error) { try decode(json) }
    }

    @Test func matchesHosts() {
        let permissions = ExtensionPermissions(network: ["api.github.com", "*.example.com"])
        #expect(permissions.allowsHost("api.github.com"))
        #expect(permissions.allowsHost("API.GitHub.com"))
        #expect(permissions.allowsHost("www.example.com"))
        #expect(!permissions.allowsHost("example.com"))
        #expect(!permissions.allowsHost("github.com"))
        #expect(!permissions.allowsHost("evilexample.com"))
        #expect(ExtensionPermissions(network: ["*"]).allowsHost("anything.org"))
    }

    @Test func coversOnlyWhatWasGranted() {
        let granted = ExtensionPermissions(network: ["api.github.com"])
        #expect(granted.covers(ExtensionPermissions()))
        #expect(granted.covers(ExtensionPermissions(network: ["api.github.com"])))
        #expect(!granted.covers(ExtensionPermissions(network: ["github.com"])))
        #expect(!granted.covers(ExtensionPermissions(clipboard: true)))
        #expect(ExtensionPermissions(network: ["*"]).covers(ExtensionPermissions(network: ["x.org"])))
    }
}

struct ExtensionViewTests {
    private func node(_ json: String) throws -> ExtensionNode {
        try JSONDecoder().decode(ExtensionNode.self, from: Data(json.utf8))
    }

    @Test func readsAListWithSectionsAndActions() throws {
        let tree = try node(
            """
            {"id": 9, "type": "view", "props": {}, "children": [
              {"id": 8, "type": "list", "props": {"isLoading": true, "filtering": false,
                 "onSearchTextChange": {"$handler": "8.onSearchTextChange"}}, "children": [
                {"id": 1, "type": "list-item", "props": {"title": "Loose"}, "children": []},
                {"id": 7, "type": "list-section", "props": {"title": "Fruit"}, "children": [
                  {"id": 6, "type": "list-item", "props": {"id": "apple", "title": "Apple", "subtitle": "Red",
                     "keywords": ["pomme"], "accessories": [{"text": "3"}]}, "children": [
                    {"id": 5, "type": "action-panel", "props": {}, "children": [
                      {"id": 2, "type": "action", "props": {"title": "Eat", "onAction": {"$handler": "2.onAction"},
                         "shortcut": {"modifiers": ["cmd"], "key": "E"}}, "children": []},
                      {"id": 4, "type": "action-panel-section", "props": {"title": "More"}, "children": [
                        {"id": 3, "type": "action", "props": {"title": "Throw Away", "style": "destructive",
                           "onAction": {"$handler": "3.onAction"}}, "children": []}
                      ]}
                    ]}
                  ]}
                ]}
              ]}
            ]}
            """)
        guard case .list(let list) = ExtensionView(tree) else {
            Issue.record("Expected a list")
            return
        }
        #expect(list.isLoading)
        #expect(!list.filtering)
        #expect(list.searchTextHandler == "8.onSearchTextChange")
        #expect(list.items.map(\.id) == ["position:0", "apple"])
        let apple = list.items[1]
        #expect(apple.section == "Fruit")
        #expect(apple.searchText == "Apple Red pomme")
        #expect(apple.accessories.first?.text == "3")
        #expect(apple.actions.map(\.title) == ["Eat", "Throw Away"])
        #expect(apple.actions[0].shortcut == ExtensionShortcut(key: "e", modifiers: .command))
        #expect(apple.actions[1].isDestructive)
        #expect(apple.actions[1].section == "More")
    }

    @Test func readsAFormWithItsInitialValues() throws {
        let tree = try node(
            """
            {"id": 1, "type": "form", "props": {}, "children": [
              {"id": 2, "type": "form-field", "props": {"id": "name", "kind": "text", "defaultValue": "Ada"}, "children": []},
              {"id": 3, "type": "form-field", "props": {"id": "ok", "kind": "checkbox", "label": "OK"}, "children": []},
              {"id": 4, "type": "form-field", "props": {"id": "size", "kind": "dropdown"}, "children": [
                {"id": 5, "type": "form-option", "props": {"value": "s", "title": "Small"}, "children": []},
                {"id": 6, "type": "form-option", "props": {"value": "l", "title": "Large"}, "children": []}
              ]}
            ]}
            """)
        guard case .form(let form) = ExtensionView(tree) else {
            Issue.record("Expected a form")
            return
        }
        #expect(form.fields.map(\.initialValue) == [.string("Ada"), .bool(false), .string("s")])
        #expect(form.fields[2].options.map(\.title) == ["Small", "Large"])
    }

    @Test func ignoresShortcutsWithoutCommandOrControl() {
        #expect(ExtensionShortcut(.object(["key": .string("a"), "modifiers": .array([.string("shift")])])) == nil)
        #expect(ExtensionShortcut(.object(["key": .string("ab"), "modifiers": .array([.string("cmd")])])) == nil)
    }
}

/// Runs real extensions in JavaScriptCore, written without JSX since the tests can't bundle.
final class ExtensionRuntimeTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "WhippetExtension-\(UUID().uuidString)")

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private static let manifest = ExtensionManifest(
        id: "com.example.test", name: "Test", version: "1.0.0",
        permissions: ExtensionPermissions(network: ["allowed.example"]),
        commands: [
            ExtensionCommand(name: "fruit", title: "Fruit"),
            ExtensionCommand(name: "quick", title: "Quick", mode: .noView),
        ])

    private static let script = """
        const React = require("react");
        const { List, ActionPanel, Action, Detail, LocalStorage, getPreferenceValues } = require("@whippet/api");
        const h = React.createElement;

        exports.fruit = function Fruit({ arguments: args }) {
          const [query, setQuery] = React.useState(args.start ?? "");
          const names = ["Apple", "Banana", "Cherry"].filter((name) => name.toLowerCase().includes(query.toLowerCase()));
          return h(List, { onSearchTextChange: setQuery },
            names.map((name) => h(List.Item, { key: name, id: name, title: name,
              actions: h(ActionPanel, null,
                h(Action.Push, { title: "Show", target: h(Detail, { markdown: "# " + name }) })) })));
        };

        exports.quick = async function () {
          await LocalStorage.setItem("greeting", "hello " + getPreferenceValues().name);
          console.log("stored", await LocalStorage.getItem("greeting"));
          try {
            await fetch("https://blocked.example/");
          } catch (error) {
            console.log("blocked:", error.message);
          }
        };

        exports.broken = function () {
          throw new Error("boom");
        };
        """

    private func start(script: String = ExtensionRuntimeTests.script) throws -> (
        ExtensionRuntime, AsyncStream<ExtensionRuntime.Event>
    ) {
        let folder = directory.appending(path: "extension")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try script.write(to: folder.appending(path: "index.js"), atomically: true, encoding: .utf8)
        let (stream, continuation) = AsyncStream<ExtensionRuntime.Event>.makeStream()
        let runtime = ExtensionRuntime(
            manifest: Self.manifest, directory: folder, dataDirectory: directory.appending(path: "data"),
            environment: [:], preferences: ["name": .string("Ada")],
            host: { _ in .null },
            onEvent: { continuation.yield($0) })
        return (runtime, stream)
    }

    /// The next event the filter accepts, failing after a few seconds rather than hanging.
    private func next<T: Sendable>(
        _ stream: AsyncStream<ExtensionRuntime.Event>, _ filter: @escaping @Sendable (ExtensionRuntime.Event) -> T?
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                for await event in stream {
                    if let value = filter(event) { return value }
                }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                return nil
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() ?? nil else { throw CancellationError() }
            return value
        }
    }

    private static func list(_ event: ExtensionRuntime.Event) -> (depth: Int, list: ExtensionList)? {
        guard case .render(_, let depth, .list(let list)) = event else { return nil }
        return (depth, list)
    }

    @Test func rendersAListAndFiltersIt() async throws {
        let (runtime, stream) = try start()
        runtime.launch(session: "s", command: "fruit", mode: .view, arguments: ["start": "an"])
        let first = try await next(stream, Self.list)
        #expect(first.depth == 1)
        #expect(first.list.items.map(\.title) == ["Banana"])
        #expect(!first.list.filtering)

        let handler = try #require(first.list.searchTextHandler)
        runtime.dispatch(session: "s", handler: handler, arguments: [.string("e")])
        let filtered = try await next(stream) { event in
            Self.list(event).flatMap { $0.list.items.count == 2 ? $0.list : nil }
        }
        #expect(filtered.items.map(\.title) == ["Apple", "Cherry"])
    }

    @Test func pushesAndPopsViews() async throws {
        let (runtime, stream) = try start()
        runtime.launch(session: "s", command: "fruit", mode: .view)
        let first = try await next(stream, Self.list)
        let show = try #require(first.list.items.first?.actions.first?.handler)

        runtime.dispatch(session: "s", handler: show)
        let markdown = try await next(stream) { event -> String? in
            guard case .render(_, 2, .detail(let detail)) = event else { return nil }
            return detail.markdown
        }
        #expect(markdown == "# Apple")

        #expect(await runtime.pop(session: "s"))
        _ = try await next(stream) { event in Self.list(event).flatMap { $0.depth == 1 ? true : nil } }
        #expect(await !runtime.pop(session: "s"))
    }

    @Test func runsACommandWithoutAViewUsingStorageAndFetch() async throws {
        let (runtime, stream) = try start()
        runtime.launch(session: "q", command: "quick", mode: .noView)
        var logs: [String] = []
        while true {
            let event = try await next(stream) { event -> ExtensionRuntime.Event? in
                switch event {
                case .log, .done, .failed: event
                default: nil
                }
            }
            if case .log(_, let message) = event {
                logs.append(message)
            } else if case .failed(_, let message, _) = event {
                Issue.record("Failed: \(message)")
                break
            } else {
                break
            }
        }
        #expect(logs.first == "stored hello Ada")
        #expect(logs.last?.hasPrefix("blocked: Whippet blocked a request to blocked.example") == true)
        let stored = try Data(contentsOf: directory.appending(path: "data/storage.json"))
        #expect(try JSONDecoder().decode([String: String].self, from: stored) == ["greeting": "hello Ada"])
    }

    @Test func reportsErrorsAgainstTheSession() async throws {
        let (runtime, stream) = try start()
        runtime.launch(session: "b", command: "broken", mode: .view)
        let markdown = try await next(stream) { event -> String? in
            guard case .render("b", _, .detail(let detail)) = event else { return nil }
            return detail.markdown
        }
        #expect(markdown.contains("boom"))
    }

    @Test func reportsAMissingCommand() async throws {
        let (runtime, stream) = try start()
        runtime.launch(session: "m", command: "missing", mode: .view)
        let message = try await next(stream) { event -> String? in
            guard case .failed("m", let message, _) = event else { return nil }
            return message
        }
        #expect(message.contains("missing"))
    }

    @Test func reportsAScriptThatDoesntLoad() async throws {
        let (runtime, stream) = try start(script: "this is not javascript")
        _ = try await next(stream) { event -> Bool? in
            guard case .failed(nil, _, _) = event else { return nil }
            return true
        }
        runtime.launch(session: "x", command: "fruit", mode: .view)
        _ = try await next(stream) { event -> Bool? in
            guard case .failed("x", _, _) = event else { return nil }
            return true
        }
    }
}
