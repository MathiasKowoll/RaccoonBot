//
//  GameDefaults.swift
//  RaccoonBot
//
//  What a title starts life with, written down rather than assumed.
//
//  A launch reads the persisted GameOptionsData for its appid and builds the
//  environment from that. Where nothing was persisted it used to fall back to
//  a freshly constructed GameOptions -- and only logged "failed to retrieve
//  game options" on the way past. That fallback is how the interface could
//  show D3DMetal 4 for a title while the launch installed 3: the default
//  backend is "d3dmetal", `installd3dMetal` reads it as generation 3, and the
//  engine keeps whatever the last launch put there.
//
//  The cost was not one bad launch. Three titles were written off today as
//  broken or as documented limitations -- Life is Strange: Double Exposure,
//  Tormented Souls 2, NieR Replicant -- and all three ran after somebody
//  re-selected the toolkit and saved, with no code change. Ten of the twenty
//  three fixed titles are marked as needing 4.0b2 and two of them crash on
//  3.0, so any of them could produce a false negative this way.
//
//  So a title is given a configuration when it is discovered, and the launch
//  reads that. There is no unconfigured state to fall back from.
//

import Foundation

nonisolated enum GameDefaults {

    /// The one place the options key is spelled.
    ///
    /// Steam's appid where there is one, the library's own id where there is
    /// not -- a custom entry has no appid. Every caller has to agree on this
    /// or a title is configured under one name and launched under another.
    static func key(forAppID appID: Int, id: String) -> String {
        namespacedKey("GameOptions", appID != 0 ? String(describing: appID) : id)
    }

    /// What a newly discovered title is configured with.
    ///
    /// Built from a GameOptions rather than by listing fields here, so that a
    /// field added later carries its own default instead of silently arriving
    /// as nil. Only what the owner asked for is overridden:
    ///
    ///     the Metal HUD on, showing frames per second and nothing else
    ///     D3DMetal 4
    ///
    /// The rest is whatever this application already considers sensible.
    static func freshOptions() -> GameOptionsData {
        let options = GameOptions()
        options.mtlHudEnabled = true
        options.mtlHudDetail = MetalHudDetail.fpsOnly.rawValue
        options.cxGraphicsBackend = newestD3DMetalBackend
        // The same rule the panel applies when somebody picks this backend
        // (GameOptionsView, onChange of the picker). Written explicitly rather
        // than left to the computed fallback in set(data:), because building
        // this from a GameOptions means the field arrives non-nil and the
        // fallback never fires -- so a seeded title would have run D3DMetal 4
        // with D3DM_MTL4=0, which is not what the panel produces for the same
        // choice. Off below macOS 27, where the toggle is disabled and nobody
        // could turn it back off.
        options.d3dMtl4Enabled = newestD3DMetalBackend == "d3dmetal4" && OSVersion >= 27
        return GameOptionsData(data: options)
    }

    /// Give a title a configuration if it has none.
    ///
    /// Never over one that exists: a title somebody has configured keeps every
    /// choice they made, including the ones that match a default. Returns true
    /// when something was written, which is what a test can assert on.
    @discardableResult
    static func seedIfAbsent(key: String) -> Bool {
        if (readUsrDefData(key: key) as GameOptionsData?) != nil { return false }
        persistUsrDefData(key: key, data: freshOptions())
        console.log("configured \(key) for the first time")
        return true
    }

    @discardableResult
    static func seedIfAbsent(forAppID appID: Int, id: String) -> Bool {
        seedIfAbsent(key: key(forAppID: appID, id: id))
    }
}
