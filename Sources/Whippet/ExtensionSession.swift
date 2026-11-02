import Foundation
import Observation
import WhippetCore

/// A view command while it's open in the panel: the view its extension last rendered, how deep its navigation is, and
/// the values typed into a form, which Whippet keeps and passes to the action that submits it.
@MainActor
@Observable
final class ExtensionSession {
    let id = UUID().uuidString
    let command: ExtensionCommandInfo
    @ObservationIgnored let runtime: ExtensionRuntime

    private(set) var view = ExtensionView.loading
    private(set) var depth = 1
    /// Bumped with each render, so the launcher's cached results know to update.
    private(set) var revision = 0
    private(set) var formValues: [String: JSONValue] = [:]
    /// What the command was launched with, to launch it again after its extension reloads.
    private(set) var arguments: [String: String] = [:]

    @ObservationIgnored private var pendingSearch: Task<Void, Never>?

    /// How long a throttled list waits for typing to pause before searching.
    private static let throttleDelay = Duration.milliseconds(250)

    init(command: ExtensionCommandInfo, runtime: ExtensionRuntime) {
        self.command = command
        self.runtime = runtime
    }

    func launch(arguments: [String: String]) {
        self.arguments = arguments
        runtime.launch(session: id, command: command.command.name, mode: .view, arguments: arguments)
    }

    /// Takes a new render, returning true when it's a different view in the stack, which starts with an empty search.
    @discardableResult
    func apply(_ view: ExtensionView, depth: Int) -> Bool {
        let isNewView = depth != self.depth
        if isNewView {
            formValues = [:]
        }
        if case .form(let form) = view {
            for field in form.fields {
                if let value = field.value {
                    formValues[field.id] = value
                } else if formValues[field.id] == nil {
                    formValues[field.id] = field.initialValue
                }
            }
        }
        self.view = view
        self.depth = depth
        revision += 1
        return isNewView
    }

    var list: ExtensionList? {
        if case .list(let list) = view { return list }
        return nil
    }

    /// Passes the search text to a list that searches for itself.
    func searchTextChanged(_ text: String) {
        guard let list, let handler = list.searchTextHandler else { return }
        pendingSearch?.cancel()
        guard list.throttle else {
            runtime.dispatch(session: id, handler: handler, arguments: [.string(text)])
            return
        }
        pendingSearch = Task { [runtime, id] in
            try? await Task.sleep(for: Self.throttleDelay)
            guard !Task.isCancelled else { return }
            runtime.dispatch(session: id, handler: handler, arguments: [.string(text)])
        }
    }

    func run(_ action: ExtensionAction) {
        guard let handler = action.handler else { return }
        runtime.dispatch(session: id, handler: handler, arguments: action.submitsForm ? [.object(formValues)] : [])
    }

    func setValue(_ value: JSONValue, of field: ExtensionFormField) {
        formValues[field.id] = value
        if let handler = field.changeHandler {
            runtime.dispatch(session: id, handler: handler, arguments: [value])
        }
    }

    func pop() async -> Bool {
        await runtime.pop(session: id)
    }

    func popToRoot() {
        runtime.popToRoot(session: id)
    }

    func close() {
        pendingSearch?.cancel()
        runtime.close(session: id)
    }
}
