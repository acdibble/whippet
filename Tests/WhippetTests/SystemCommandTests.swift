import Testing

struct SystemCommandTests {
    @Test func onlyCommandsThatCantBeUndoneAskFirst() {
        let asking = SystemCommand.allCases.filter { $0.confirmation != nil }
        #expect(Set(asking) == [.restart, .shutDown, .emptyTrash])
    }
}
