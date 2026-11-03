import Foundation
import Testing

struct AppContainerTests {
    private let library = URL.homeDirectory.appending(path: "Library")

    @Test func otherAppsContainers() {
        #expect(library.appending(path: "Containers/com.apple.mail/Data/Library/Mail Downloads/a.png").isInAppContainer)
        #expect(
            library.appending(path: "Group Containers/group.net.whatsapp.WhatsApp.shared/Message/b.jpg")
                .isInAppContainer)
        #expect(
            URL(filePath: library.path + "/Containers/com.apple.Notes/../com.apple.mail/Data/c.png").isInAppContainer)
    }

    @Test func otherFiles() {
        #expect(!URL.homeDirectory.appending(path: "Desktop/Screenshot.png").isInAppContainer)
        #expect(!library.appending(path: "Application Support/Whippet/a.png").isInAppContainer)
        #expect(!library.appending(path: "ContainersBackup/a.png").isInAppContainer)
        #expect(!URL(filePath: "/Library/Containers/com.apple.mail/a.png").isInAppContainer)
    }
}
