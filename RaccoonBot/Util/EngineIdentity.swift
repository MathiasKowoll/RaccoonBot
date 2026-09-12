import Foundation

/// What an engine is, in the three terms a payload asks about.
///
/// The fixes bundle carries media compiled against one particular engine, and
/// applying it to a different one does not degrade: media stops loading, which
/// is the exact shape of the fault it repairs. So all three are read, and a
/// field that cannot be read stays nil rather than being guessed.
///
/// Nonisolated because it is read where the engine is written: the
/// controller-bus switch compares it in Task.detached, and a main-actor
/// initialiser called from there would hop straight back onto the main actor
/// to scan ntdll.so.
nonisolated struct EngineIdentity: Equatable {
    /// The bundle's own name: "Crossover_MGVF.app".
    ///
    /// The only one of the three that tells a patched copy from a stock one.
    /// Both report CFBundleVersion 26.3.0.39832 -- measured on this machine,
    /// not assumed -- so a payload matched on version alone would install into
    /// whichever CrossOver it was pointed at.
    ///
    /// The name is the field to read, and reading the wrong one has a cost
    /// beyond a mismatched payload: an engine that does not own a bottle will
    /// still open it, and wine then updates that bottle from the engine that
    /// opened it. One such update rewrote 1,475 files under `drive_c/windows`
    /// and reverted a fix that stays recorded as installed.
    let app: String

    /// CFBundleVersion: "26.3.0.39832".
    ///
    /// Not CFBundleShortVersionString, which the patcher rewrites -- a patched
    /// copy says "26.3p0.1.0" there and the stock one says "26.3", and neither
    /// is what the bundle records.
    let version: String?

    /// The wine the engine was built from: "wine-11.0-8726-g2e2f5fca349".
    ///
    /// Nothing states it in a file meant to be read. `wine --version` answers
    /// with CrossOver's product version instead, and the only place the tag
    /// appears is inside ntdll.so, so that is where this looks.
    let wine: String?

    /// What the engine records it was copied from, when MacGameVideoFix made
    /// it: `copied_from` in `Contents/SharedSupport/CrossOver/mgvf-origin.json`,
    /// "CrossOver.app" for a copy of the stock one.
    ///
    /// A copy this project made is not a different engine; it is the same
    /// engine under another name, and the name is the only thing a stamp can
    /// see. So a stamp naming the original serves the copy through this, the
    /// way install-engine-media.sh and install-engine-controller.sh resolve
    /// it. Nil for an engine that records nothing -- stock CrossOver, or a
    /// copy something else made -- and nil is not a match.
    let copiedFrom: String?

    /// "Crossover_MGVF.app 26.3.0.39832", for a sentence.
    var described: String {
        [app, version].compactMap { $0 }.joined(separator: " ")
    }

    init(ofEngineAt app: URL) {
        self.app = app.lastPathComponent
        let plist = app.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: plist),
           let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            version = info["CFBundleVersion"] as? String
        } else {
            version = nil
        }
        wine = Self.wineTag(inEngineAt: app)
        copiedFrom = Self.origin(ofEngineAt: app)
    }

    /// `copied_from` out of the marker MacGameVideoFix leaves in a copy it made.
    static func origin(ofEngineAt app: URL) -> String? {
        let marker = app.appendingPathComponent("Contents/SharedSupport/CrossOver/mgvf-origin.json")
        guard let data = try? Data(contentsOf: marker),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let from = json["copied_from"] as? String, !from.isEmpty
        else { return nil }
        return from
    }

    /// Scans ntdll.so for the tag wine stamps into it.
    static func wineTag(inEngineAt app: URL) -> String? {
        let candidates = [
            "Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/ntdll.so",
            "Contents/SharedSupport/CrossOver/lib64/wine/x86_64-unix/ntdll.so",
        ]
        for relative in candidates {
            let url = app.appendingPathComponent(relative)
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            if let tag = tag(in: data) { return tag }
        }
        return nil
    }

    /// "wine-" followed by what wine writes after it: digits, dots, dashes and
    /// the abbreviated commit. Stops at the first byte that is none of those,
    /// which is the NUL the string ends with.
    static func tag(in data: Data) -> String? {
        let needle = Array("wine-".utf8)
        let allowed: Set<UInt8> = Set("0123456789.-abcdefg".utf8)
        let bytes = [UInt8](data)
        guard bytes.count > needle.count else { return nil }

        var index = 0
        while index <= bytes.count - needle.count {
            if Array(bytes[index..<index + needle.count]) == needle {
                var end = index + needle.count
                while end < bytes.count, allowed.contains(bytes[end]) { end += 1 }
                let candidate = String(decoding: bytes[index..<end], as: UTF8.self)
                // "wine-11.0-8726-g2e2f5fca349", not "wine-" on its own or a
                // bare "wine-11.0" from some other string.
                if candidate.contains("-g"), candidate.count > 12 { return candidate }
            }
            index += 1
        }
        return nil
    }
}
