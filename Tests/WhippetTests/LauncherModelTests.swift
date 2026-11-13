import Foundation
import Testing

@MainActor
struct LauncherModelTests {
    private func makeModel() throws -> (model: LauncherModel, cleanUp: () -> Void) {
        let suite = "LauncherModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let model = LauncherModel(
            modules: ModuleSettings(defaults: defaults), history: LaunchHistory(defaults: defaults))
        return (model, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func keepsTheSearchAfterAClickElsewhere() throws {
        let (model, cleanUp) = try makeModel()
        defer { cleanUp() }
        let closed = Date()
        model.query = "safari"
        model.panelLostFocus(at: closed)

        #expect(model.resumeOrReset(at: closed.addingTimeInterval(LauncherModel.resumeInterval - 1)))
        #expect(model.query == "safari")
    }

    @Test func clearsTheSearchOnceTheIntervalHasPassed() throws {
        let (model, cleanUp) = try makeModel()
        defer { cleanUp() }
        let closed = Date()
        model.query = "safari"
        model.panelLostFocus(at: closed)

        #expect(!model.resumeOrReset(at: closed.addingTimeInterval(LauncherModel.resumeInterval)))
        #expect(model.query.isEmpty)
    }

    /// Escape, the hotkey and actions close the panel without it losing focus first, so the next opening is empty.
    @Test func clearsTheSearchAfterAnyOtherClose() throws {
        let (model, cleanUp) = try makeModel()
        defer { cleanUp() }
        model.query = "safari"

        #expect(!model.resumeOrReset())
        #expect(model.query.isEmpty)
    }

    /// A command's hotkey resets the panel, and nothing from before a reset comes back.
    @Test func resetForgetsAClickElsewhere() throws {
        let (model, cleanUp) = try makeModel()
        defer { cleanUp() }
        let closed = Date()
        model.query = "safari"
        model.panelLostFocus(at: closed)
        model.reset()
        model.query = "notes"

        #expect(!model.resumeOrReset(at: closed.addingTimeInterval(1)))
        #expect(model.query.isEmpty)
    }
}
