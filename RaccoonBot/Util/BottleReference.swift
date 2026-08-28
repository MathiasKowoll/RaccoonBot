import Foundation

/// A bottle, however the caller happened to write it.
///
/// This application stores the selected bottle as a `file://` URL, but
/// CrossOver's `--bottle` wants a bare name. Where the two met without
/// translating, `wine` was handed
/// `file:///Users/.../CXPBottles/Steam/` as a name and answered
/// "invalid bottle name" behind a Fatal Error dialog -- so the polite
/// shutdown never ran, and the launcher fell through to killing processes
/// instead.
///
/// The name alone is not enough either. It is resolved under whatever bottle
/// root the engine happens to use, and this machine has bottles of the same
/// name under two roots, which macOS does not tell apart by case. So a
/// reference carries the root it came from as well.
struct BottleReference: Equatable {
    /// What `--bottle` accepts: the directory name, percent-decoded.
    let name: String

    /// The directory the bottle sits in, for `CX_BOTTLE_PATH`. Empty when the
    /// caller gave a bare name and there was nothing to derive it from.
    let root: String

    /// The bottle's own directory, for reading what is inside it. Nil when the
    /// caller gave a bare name, because a name alone does not say where.
    let directory: URL?

    init?(_ bottle: String) {
        let trimmed = bottle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard trimmed.contains("/") else {
            // Already a name.
            self.name = trimmed
            self.root = ""
            self.directory = nil
            return
        }

        let url: URL? = trimmed.hasPrefix("file://")
            ? URL(string: trimmed)
            : URL(fileURLWithPath: trimmed)
        guard let url else { return nil }

        let name = url.lastPathComponent
        guard !name.isEmpty, name != "/" else { return nil }

        self.name = name
        self.directory = url
        // Joined as text rather than through the URL: `path` reports a
        // trailing slash or not depending on whether the directory exists on
        // disk, and a root that changes shape when the bottle is missing is a
        // root that compares unequal in tests.
        var root = url.deletingLastPathComponent().path(percentEncoded: false)
        while root.count > 1 && root.hasSuffix("/") { root.removeLast() }
        self.root = root
    }

    /// `CX_BOTTLE_PATH=...` ready to prefix a command, or nothing when the
    /// root is unknown -- an empty value would point the engine at nowhere.
    var environmentPrefix: String {
        root.isEmpty ? "" : "CX_BOTTLE_PATH=\"\(root)\" "
    }
}
