import Foundation
import JavaScriptCore

/// Runs one extension's JavaScript: its own JavaScriptCore virtual machine and context, used only from a private serial
/// queue, since a context can't be shared between threads. Whippet's runtime (React, the renderer and the API) loads
/// first, then the extension's `index.js`.
///
/// The context starts with nothing but JavaScript itself. Everything else, from timers to the network and the
/// clipboard, is a function injected here, which is where the manifest's permissions are enforced. Messages both ways
/// are JSON, so the runtime could move into a separate process without changing what extensions see.
public final class ExtensionRuntime: @unchecked Sendable {
    /// What the extension sends Whippet.
    public enum Event: Sendable {
        /// A view command's view, after each change. `depth` is how long the command's history is, and `route`
        /// identifies the entry shown, so a new page can be told from a change to the same one.
        case render(session: String, depth: Int, route: String, view: ExtensionView)
        /// A command without a view finished.
        case done(session: String)
        /// The extension threw. Without a session, it failed loading or outside any command.
        case failed(session: String?, message: String, stack: String?)
        case log(level: String, message: String)
    }

    /// What the extension asks Whippet to do on its behalf.
    public enum HostRequest: Sendable {
        case toast(title: String, message: String?, isFailure: Bool)
        case closeMainWindow
        case popToRoot
        case open(URL)
        case copy(String)
        case paste(String)
        case readClipboard
    }

    public typealias Host = @Sendable (HostRequest) async throws -> JSONValue

    public let manifest: ExtensionManifest
    public let directory: URL

    private let dataDirectory: URL
    private let queue: DispatchQueue
    private let host: Host
    private let onEvent: @Sendable (Event) -> Void
    private let urlSession: ScopedSession

    // Only touched on `queue`.
    private var context: JSContext?
    private var whippet: JSValue?
    private var loadError: String?
    private var timers: [Int: JSValue] = [:]
    private var nextTimerID = 1
    private var pendingCalls: [Int: (resolve: JSValue, reject: JSValue)] = [:]
    private var nextCallID = 1
    private var storage: [String: String]?
    /// The session whose code is running, so an uncaught exception is reported against it.
    private var currentSession: String?

    static let runtimeSource: String? = Bundle.module.url(forResource: "ExtensionRuntime", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    /// Starts loading straight away, on the runtime's queue. Events arrive on that queue too.
    public init(
        manifest: ExtensionManifest,
        directory: URL,
        dataDirectory: URL,
        environment: [String: JSONValue],
        preferences: [String: JSONValue],
        host: @escaping Host,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.manifest = manifest
        self.directory = directory
        self.dataDirectory = dataDirectory
        self.host = host
        self.onEvent = onEvent
        queue = DispatchQueue(label: "codes.dibble.whippet.extension.\(manifest.id)", qos: .userInitiated)
        urlSession = ScopedSession(hosts: manifest.permissions.network, timeout: 30)
        queue.async {
            self.load(environment: environment, preferences: preferences)
        }
    }

    // MARK: - Commands

    public func launch(
        session: String, command: String, mode: ExtensionCommand.Mode, arguments: [String: String] = [:],
        fallbackText: String? = nil
    ) {
        queue.async {
            guard let whippet = self.whippet else {
                self.onEvent(.failed(session: session, message: self.loadError ?? "", stack: nil))
                return
            }
            let arguments = JSONValue.object(arguments.mapValues(JSONValue.string)).jsonString
            self.run(in: session) {
                whippet.invokeMethod(
                    "launch", withArguments: [session, command, mode.rawValue, arguments, fallbackText ?? NSNull()])
            }
        }
    }

    /// Runs a function the extension sent as a `$handler`, such as an action's `onAction`.
    public func dispatch(session: String, handler: String, arguments: [JSONValue] = []) {
        queue.async {
            self.run(in: session) {
                self.whippet?.invokeMethod(
                    "dispatch", withArguments: [session, handler, JSONValue.array(arguments).jsonString])
            }
        }
    }

    /// Goes back in the command's history, returning false on its first entry.
    public func pop(session: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                let popped = self.run(in: session) { self.whippet?.invokeMethod("pop", withArguments: [session]) }
                continuation.resume(returning: popped?.toBool() ?? false)
            }
        }
    }

    public func popToRoot(session: String) {
        queue.async {
            self.run(in: session) { self.whippet?.invokeMethod("popToRoot", withArguments: [session]) }
        }
    }

    /// Unmounts a view command, which runs its effects' cleanups.
    public func close(session: String) {
        queue.async {
            self.run(in: session) { self.whippet?.invokeMethod("close", withArguments: [session]) }
        }
    }

    public func updatePreferences(_ preferences: [String: JSONValue]) {
        queue.async {
            let configuration = JSONValue.object(["preferences": .object(preferences)]).jsonString
            self.run(in: nil) { self.whippet?.invokeMethod("configure", withArguments: [configuration]) }
        }
    }

    /// Stops timers and requests and lets the context go. A script stuck in a loop keeps its thread until Whippet
    /// quits, since JavaScriptCore has no public way to interrupt it.
    public func shutdown() {
        urlSession.invalidate()
        queue.async {
            self.timers.removeAll()
            self.pendingCalls.removeAll()
            self.whippet = nil
            self.context = nil
        }
    }

    @discardableResult
    private func run(in session: String?, _ body: () -> JSValue?) -> JSValue? {
        dispatchPrecondition(condition: .onQueue(queue))
        let previous = currentSession
        currentSession = session
        defer { currentSession = previous }
        return body()
    }

    // MARK: - Loading

    private func load(environment: [String: JSONValue], preferences: [String: JSONValue]) {
        guard let runtimeSource = Self.runtimeSource else {
            fail(String(localized: "Whippet's extension runtime is missing.", bundle: .module))
            return
        }
        let scriptURL = directory.appending(path: "index.js")
        guard let script = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            fail(
                String(
                    localized: "There's no index.js in the extension's folder. Build the extension first.",
                    bundle: .module))
            return
        }
        guard let virtualMachine = JSVirtualMachine(), let context = JSContext(virtualMachine: virtualMachine) else {
            fail(String(localized: "Whippet couldn't start JavaScript.", bundle: .module))
            return
        }
        context.name = manifest.name
        context.exceptionHandler = { [weak self] _, exception in
            self?.report(exception)
        }
        installNative(in: context)
        self.context = context

        context.evaluateScript(runtimeSource, withSourceURL: URL(string: "whippet://runtime.js"))
        guard let whippet = context.objectForKeyedSubscript("__whippet"), whippet.isObject else {
            fail(String(localized: "Whippet's extension runtime didn't start.", bundle: .module))
            return
        }
        let configuration: JSONValue = .object([
            "environment": .object(environment), "preferences": .object(preferences),
        ])
        whippet.invokeMethod("configure", withArguments: [configuration.jsonString])

        // The bundle is CommonJS, so it's wrapped in a function that receives `module`, `exports` and `require`.
        let factory = context.evaluateScript(
            "(function (module, exports, require) {\n\(script)\n})", withSourceURL: scriptURL)
        guard let factory, factory.isObject, context.exception == nil else {
            fail(loadError ?? String(localized: "index.js couldn't be read as JavaScript.", bundle: .module))
            return
        }
        whippet.invokeMethod("load", withArguments: [factory])
        guard loadError == nil else { return }
        self.whippet = whippet
    }

    private func fail(_ message: String) {
        loadError = message
        whippet = nil
        onEvent(.failed(session: nil, message: message, stack: nil))
    }

    private func report(_ exception: JSValue?) {
        guard let exception else { return }
        let message = exception.objectForKeyedSubscript("message")?.toString() ?? exception.toString() ?? ""
        let stack = exception.objectForKeyedSubscript("stack").flatMap { $0.isUndefined ? nil : $0.toString() }
        if whippet == nil, loadError == nil {
            loadError = message
        }
        onEvent(.failed(session: currentSession, message: message, stack: stack))
    }

    // MARK: - Native functions

    private func installNative(in context: JSContext) {
        let native = JSValue(newObjectIn: context)!

        let post: @convention(block) (String) -> Void = { [weak self] message in
            self?.receive(message)
        }
        let call: @convention(block) (String, String) -> JSValue? = { [weak self] name, arguments in
            guard let self, let context = JSContext.current() else { return nil }
            return JSValue(newPromiseIn: context) { resolve, reject in
                guard let resolve, let reject else { return }
                self.handleCall(name, arguments: arguments, resolve: resolve, reject: reject)
            }
        }
        let setTimeout: @convention(block) (JSValue, Double) -> Int = { [weak self] callback, milliseconds in
            self?.schedule(callback, after: milliseconds) ?? 0
        }
        let clearTimeout: @convention(block) (Int) -> Void = { [weak self] id in
            self?.timers[id] = nil
        }
        let uuid: @convention(block) () -> String = {
            UUID().uuidString.lowercased()
        }

        native.setObject(unsafeBitCast(post, to: AnyObject.self), forKeyedSubscript: "post" as NSString)
        native.setObject(unsafeBitCast(call, to: AnyObject.self), forKeyedSubscript: "call" as NSString)
        native.setObject(unsafeBitCast(setTimeout, to: AnyObject.self), forKeyedSubscript: "setTimeout" as NSString)
        native.setObject(unsafeBitCast(clearTimeout, to: AnyObject.self), forKeyedSubscript: "clearTimeout" as NSString)
        native.setObject(unsafeBitCast(uuid, to: AnyObject.self), forKeyedSubscript: "uuid" as NSString)
        context.setObject(native, forKeyedSubscript: "__native" as NSString)
    }

    private func schedule(_ callback: JSValue, after milliseconds: Double) -> Int {
        let id = nextTimerID
        nextTimerID += 1
        timers[id] = callback
        let delay = max(0, milliseconds.isFinite ? milliseconds : 0) / 1000
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let callback = timers.removeValue(forKey: id) else { return }
            run(in: nil) { callback.call(withArguments: []) }
        }
        return id
    }

    /// Parses with `JSONSerialization` rather than `Codable`, since a long list makes a render of a megabyte or more,
    /// which `JSONDecoder` reads several times slower.
    private func receive(_ text: String) {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
            let message = object as? [String: Any], let type = message["type"] as? String
        else { return }
        let session = message["session"] as? String
        switch type {
        case "render":
            guard let session else { return }
            let tree = (message["tree"] as? [String: Any]).flatMap(ExtensionNode.init(object:))
            onEvent(
                .render(
                    session: session, depth: message["depth"] as? Int ?? 1, route: message["route"] as? String ?? "",
                    view: ExtensionView(tree)))
        case "done":
            guard let session else { return }
            onEvent(.done(session: session))
        case "error":
            onEvent(
                .failed(
                    session: session, message: message["message"] as? String ?? "", stack: message["stack"] as? String))
        case "log":
            onEvent(.log(level: message["level"] as? String ?? "log", message: message["message"] as? String ?? ""))
        default:
            break
        }
    }

    // MARK: - Calls

    private enum CallError: LocalizedError {
        case unknown(String)
        case invalidArguments(String)
        case notPermitted(String)

        var errorDescription: String? {
            switch self {
            case .unknown(let name): String(localized: "Whippet has no function named \(name).", bundle: .module)
            case .invalidArguments(let name):
                String(localized: "The arguments for \(name) aren't valid.", bundle: .module)
            case .notPermitted(let reason): reason
            }
        }
    }

    private func handleCall(_ name: String, arguments text: String, resolve: JSValue, reject: JSValue) {
        let arguments = (try? JSONValue.parse(text)) ?? .null
        let id = nextCallID
        nextCallID += 1
        pendingCalls[id] = (resolve, reject)

        func request(_ request: HostRequest) {
            Task {
                do {
                    settle(id, with: .success(try await host(request)))
                } catch {
                    settle(id, with: .failure(error))
                }
            }
        }

        switch name {
        case "fetch":
            Task {
                do {
                    settle(id, with: .success(try await fetch(arguments)))
                } catch {
                    settle(id, with: .failure(error))
                }
            }
        case "storage.get", "storage.set", "storage.remove", "storage.all", "storage.clear":
            settle(id, with: Result { try useStorage(name, arguments: arguments) })
        case "toast":
            guard let title = arguments["title"]?.string else {
                return settle(id, with: .failure(CallError.invalidArguments(name)))
            }
            request(
                .toast(
                    title: title, message: arguments["message"]?.string,
                    isFailure: arguments["style"]?.string == "failure"))
        case "closeMainWindow":
            request(.closeMainWindow)
        case "popToRoot":
            request(.popToRoot)
        case "open":
            // File URLs could open any app or document on the Mac, so extensions open web and app links only.
            guard let url = arguments["url"]?.string.flatMap(URL.init(string:)), let scheme = url.scheme,
                scheme.lowercased() != "file"
            else { return settle(id, with: .failure(CallError.invalidArguments(name))) }
            request(.open(url))
        case "clipboard.copy", "clipboard.paste":
            guard let text = arguments["text"]?.string else {
                return settle(id, with: .failure(CallError.invalidArguments(name)))
            }
            request(name == "clipboard.copy" ? .copy(text) : .paste(text))
        case "clipboard.read":
            guard manifest.permissions.clipboard else {
                let reason = String(
                    localized: "Reading the clipboard needs the clipboard permission in the manifest.", bundle: .module)
                return settle(id, with: .failure(CallError.notPermitted(reason)))
            }
            request(.readClipboard)
        default:
            settle(id, with: .failure(CallError.unknown(name)))
        }
    }

    /// Resolves or rejects a call's promise on the runtime's queue, from wherever the answer came.
    private func settle(_ id: Int, with result: Result<JSONValue, Error>) {
        queue.async {
            guard let call = self.pendingCalls.removeValue(forKey: id), let context = self.context else { return }
            self.run(in: nil) {
                switch result {
                case .success(let value):
                    call.resolve.call(withArguments: [value == .null ? "" : value.jsonString])
                case .failure(let error):
                    call.reject.call(withArguments: [
                        JSValue(newErrorFromMessage: error.localizedDescription, in: context) as Any
                    ])
                }
            }
        }
    }

    // MARK: - Network

    private func fetch(_ arguments: JSONValue) async throws -> JSONValue {
        guard let text = arguments["url"]?.string, let url = URL(string: text),
            let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", let host = url.host()
        else {
            throw CallError.notPermitted(String(localized: "fetch needs an http or https URL.", bundle: .module))
        }
        let permissions = manifest.permissions
        guard permissions.allowsHost(host) else { throw Self.blocked(host) }
        var request = URLRequest(url: url)
        request.httpMethod = arguments["method"]?.string ?? "GET"
        for (name, value) in arguments["headers"]?.object ?? [:] {
            request.setValue(value.string, forHTTPHeaderField: name)
        }
        request.httpBody = arguments["body"]?.string.map { Data($0.utf8) }
        let (data, response) = try await urlSession.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 200
        var headers: [String: JSONValue] = [:]
        for (name, value) in http?.allHeaderFields ?? [:] {
            if let name = name as? String {
                headers[name.lowercased()] = .string("\(value)")
            }
        }
        return .object([
            "status": .number(Double(status)),
            "statusText": .string(HTTPURLResponse.localizedString(forStatusCode: status)),
            "headers": .object(headers),
            "url": .string(response.url?.absoluteString ?? text),
            "body": .string(String(decoding: data, as: UTF8.self)),
        ])
    }

    static func blocked(_ host: String) -> Error {
        CallError.notPermitted(
            String(
                localized: "Whippet blocked a request to \(host), which the extension's manifest doesn't list.",
                bundle: .module))
    }

    // MARK: - Storage

    private var storageURL: URL {
        dataDirectory.appending(path: "storage.json")
    }

    private func useStorage(_ name: String, arguments: JSONValue) throws -> JSONValue {
        var items =
            storage ?? (try? Data(contentsOf: storageURL)).flatMap {
                try? JSONDecoder().decode([String: String].self, from: $0)
            }
            ?? [:]
        defer { storage = items }
        let key = arguments["key"]?.string
        switch name {
        case "storage.get":
            return key.flatMap { items[$0] }.map(JSONValue.string) ?? .null
        case "storage.all":
            return .object(items.mapValues(JSONValue.string))
        case "storage.set":
            guard let key, let value = arguments["value"]?.string else { throw CallError.invalidArguments(name) }
            items[key] = value
        case "storage.remove":
            guard let key else { throw CallError.invalidArguments(name) }
            items[key] = nil
        default:
            items = [:]
        }
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: storageURL, options: .atomic)
        return .null
    }
}
