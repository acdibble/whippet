import Foundation

extension URL {
    /// Whether the file is inside a sandboxed app's container, such as a Mail attachment in
    /// `~/Library/Containers/com.apple.mail/Data/…` or a file in `~/Library/Group Containers/…`. macOS blocks Whippet
    /// from reading these, even to check that they exist, and tells the user each time with “Data Access Blocked”.
    /// There's no permission to ask for, short of Full Disk Access, so they're only ever handled by path.
    var isInAppContainer: Bool {
        let library = URL.homeDirectory.appending(path: "Library").standardizedFileURL.path
        let path = standardizedFileURL.path
        return ["Containers", "Group Containers"].contains { path.hasPrefix("\(library)/\($0)/") }
    }
}
