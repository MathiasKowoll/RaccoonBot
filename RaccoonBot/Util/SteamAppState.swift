import Foundation

/// What Steam itself says about one application.
enum SteamAppLiveness: Equatable {
    case running
    case notRunning
    /// Steam has not said, or the answer could not be read. Never act on this
    /// as though it meant finished: being wrong in that direction kills a game
    /// that is still playing.
    case unknown
}

/// Steam's own account of whether a game is running, read from the bottle.
///
/// The launcher used to decide a game had finished by watching executable names
/// disappear. A name is not a session. A launcher exits the moment it has
/// handed off -- that is its whole job -- and a game may restart itself or run
/// helpers beside it; all of that looks exactly like the game closing. Nioh and
/// MGS4 both start through a launcher, and both were killed by that mistake.
///
/// Steam keeps its own record, per AppID, in the bottle's registry:
///
///     [Software\\Valve\\Steam\\Apps\\485510]
///     "Name"="Nioh: Complete Edition"
///     "Running"=dword:00000000
///
/// It is keyed on the AppID we launched with and says nothing about processes,
/// which is exactly why it survives a handoff. And it needs no per-game
/// knowledge: Steam writes the same key for every installed title, so there is
/// nothing to maintain per game and nothing to get wrong for a title nobody
/// has tested.
struct SteamAppState {
    let registryURL: URL

    init(bottleDirectory: URL) {
        self.registryURL = bottleDirectory.appendingPathComponent("user.reg")
    }

    /// The path exactly as it appears between the brackets in the file, where
    /// wine writes every backslash doubled.
    static func appKeyPath(_ appID: Int) -> String {
        #"Software\\Valve\\Steam\\Apps\\"# + String(appID)
    }

    /// When wine last wrote the registry.
    ///
    /// Wine holds the registry in memory and flushes it periodically, so this
    /// file trails what Steam has done by a little. That lag is why nothing
    /// here is treated as urgent.
    var lastWritten: Date? {
        let attrs = try? FileManager.default.attributesOfItem(
            atPath: registryURL.path(percentEncoded: false))
        return attrs?[.modificationDate] as? Date
    }

    func liveness(ofAppID appID: Int) -> SteamAppLiveness {
        let registry = WineRegistryFile(fileURL: registryURL)
        do {
            try registry.load()
        } catch {
            console.error("could not read \(registryURL.lastPathComponent): \(error.localizedDescription)")
            return .unknown
        }
        guard let section = registry.section(forPath: Self.appKeyPath(appID)) else {
            // Steam has never recorded this app in this bottle.
            return .unknown
        }
        guard let running = section.getValue(forKey: "Running") else { return .unknown }
        return running == "0" ? .notRunning : .running
    }

    /// The name Steam has for an app, when it has one. Only for logging --
    /// nothing decides anything on this.
    func name(ofAppID appID: Int) -> String? {
        let registry = WineRegistryFile(fileURL: registryURL)
        guard (try? registry.load()) != nil else { return nil }
        return registry.section(forPath: Self.appKeyPath(appID))?.getValue(forKey: "Name")
    }
}
