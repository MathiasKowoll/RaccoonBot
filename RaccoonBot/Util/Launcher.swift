//
//  Launcher.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 24/02/2026.
//

import AppKit

/// Close a bottle down: ask, wait for it to happen, then end what is left of
/// this bottle -- and only this bottle.
///
/// This replaces `closeWineActivities`, which sent terminate to every running
/// application whose name ended in `.exe` or contained "wine" -- machine-wide,
/// every bottle, stock CrossOver included. Nothing about it was scoped to what
/// was being closed, so every mistake about whether a game had ended became a
/// mistake about every Windows program on the machine.
///
/// And it began the moment `Steam.exe -shutdown` had been *sent*, which is not
/// when Steam has finished. Steam writes its own state on the way down; it was
/// being killed in the middle of doing so.
///
/// Save data is already safe by the time this runs: the caller waits for
/// Steam's exit sync to finish before asking Steam to quit at all.
func closeBottle(cxAppPath: String, bottle: String,
                 waitingUpTo settleTimeout: TimeInterval = 30,
                 decidedAt generation: Int = LaunchGeneration.shared.current) async throws {
    // Asked before every destructive step, not once at the top. The waits below
    // run for half a minute, and a launch inside that window was destroyed by a
    // decision taken before it existed.
    func superseded() -> Bool {
        if LaunchGeneration.shared.supersedes(generation) {
            console.log("a game has been launched since this was decided; leaving the bottle up")
            return true
        }
        return false
    }
    guard let directory = BottleReference(bottle)?.directory else {
        console.error("cannot close \(bottle): it does not name a bottle")
        return
    }

    // Wait for Steam, and only for Steam.
    //
    // The first version of this waited for the whole bottle to fall silent,
    // which cannot happen: services.exe, plugplay.exe, rpcss.exe, explorer.exe
    // and winedevice.exe live as long as the wineserver does, by design. So the
    // wait always ran its full length and then killed -- twenty seconds thrown
    // away on every close, and Steam getting wineserver -k on top of it while
    // it was still shutting down, which is what put steamerrorreporter64.exe on
    // screen.
    let deadline = Date().addingTimeInterval(settleTimeout)
    while Date() < deadline {
        if superseded() { return }
        let here = BottleProcesses.running(inBottleAt: directory)
        if here.isEmpty {
            console.log("the bottle closed on its own")
            return
        }
        if !here.contains(where: { $0.name.lowercased().hasPrefix("steam") }) {
            console.log("steam has gone; ending what wine keeps running")
            break
        }
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    let left = BottleProcesses.running(inBottleAt: directory)
    if left.contains(where: { $0.name.lowercased().hasPrefix("steam") }) {
        console.warn("steam did not go in \(Int(settleTimeout))s: "
                     + left.map(\.name).sorted().joined(separator: ", "))
    }

    if superseded() { return }
    // wineserver -k ends the prefix through wine's own mechanism.
    try await quitWine(cxAppPath: cxAppPath, bottle: bottle)
    try await Task.sleep(nanoseconds: 2_000_000_000)

    // Whatever outlived its own server is an orphan, and orphans are the
    // reason the next launch fails: they keep the bottle's devices and its
    // registry claimed. Ending them is the whole point of knowing which bottle
    // they belong to.
    if superseded() { return }
    let survivors = await BottleProcesses.end(inBottleAt: directory)
    if survivors.isEmpty {
        console.log("the bottle is closed")
    } else {
        console.error("would not end: " + survivors.map(\.name).joined(separator: ", "))
    }
}

func quitSteam(cxAppPath: String, bottle: String, isNative: Bool) async throws -> Void {
    console.log("quitting steam...")
    if(isNative) {
        let steamBundleID = "com.valvesoftware.steam"
        if let steamApp = NSRunningApplication.runningApplications(withBundleIdentifier: steamBundleID).first {
            steamApp.terminate() // polite request to quit
        }
    } else {
        // Callers hold the bottle as a file:// URL; `--bottle` wants the name.
        // Passing the URL straight through made every shutdown fail with
        // "invalid bottle name", which is how Steam ended up being killed
        // rather than asked to leave.
        guard let ref = BottleReference(bottle) else {
            console.error("cannot quit steam: \(bottle) does not name a bottle")
            return
        }
        try safeShell("\(ref.environmentPrefix)\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \"\(ref.name)\" \"C:\\Program Files (x86)\\Steam\\Steam.exe\" -shutdown")
    }
}

func quitWine(cxAppPath: String, bottle: String) async throws -> Void {
    console.log("quitting wine...")
    guard let ref = BottleReference(bottle) else {
        console.error("cannot quit wine: \(bottle) does not name a bottle")
        return
    }
    try safeShell("\(ref.environmentPrefix)\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \"\(ref.name)\" wineserver -k")
}

func openSteam(cxAppPath: String?, selectedBottle: String?, SteamX86AppPath: String) {
    if cxAppPath == nil || selectedBottle == nil {
        return
    }
    if let bottleName = URL(string: selectedBottle!)?.lastPathComponent {
        // Same reason as launchWindowsGame: the name alone can resolve into
        // another product's bottle root.
        let bottleRoot = URL(string: selectedBottle!)?.deletingLastPathComponent().path(percentEncoded: false) ?? ""
        let steamLaunchCommand = "CX_BOTTLE_PATH=\"\(bottleRoot)\" MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0 CX_GRAPHICS_BACKEND=\"auto\" \(cxAppPath!)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \"\(SteamX86AppPath)\""
        do {
            try safeShell(steamLaunchCommand)
            console.log(steamLaunchCommand)
        } catch {
            console.error(String(reflecting: error))
        }
    }
}

/// What the Steam client inside the bottle can be asked to do.
///
/// Steam registers the `steam://` protocol on Windows and steam.exe accepts one
/// of these as an argument, so the client can be driven from outside without
/// steamcmd, without credentials, and without this application ever touching
/// the user's account. Every one of them ends in Steam's own dialog: the
/// confirmation belongs to Steam, which is where it should be.
enum SteamAction {
    case install(String)
    case run(String)
    /// Verifies the files and repairs what is wrong, which is also how a title
    /// that failed to update gets fixed.
    case validate(String)

    var url: String {
        switch self {
        case .install(let id):  return "steam://install/\(id)"
        case .run(let id):      return "steam://run/\(id)"
        case .validate(let id): return "steam://validate/\(id)"
        }
    }
}

/// Hand a steam:// url to the Steam client in the bottle.
///
/// NOT `open steam://…` on the mac side: that would reach a native Steam if one
/// is installed, which is a different client with a different library, and for
/// a Windows title it is the wrong one.
func runSteamAction(_ action: SteamAction,
                    cxAppPath: String?,
                    selectedBottle: String?,
                    SteamX86AppPath: String) {
    guard let cxAppPath, let selectedBottle,
          let bottleName = URL(string: selectedBottle)?.lastPathComponent else { return }
    // Same reason as launchWindowsGame: the name alone can resolve into
    // another product's bottle root.
    let bottleRoot = URL(string: selectedBottle)?.deletingLastPathComponent().path(percentEncoded: false) ?? ""
    let command = "CX_BOTTLE_PATH=\"\(bottleRoot)\" \(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \"\(SteamX86AppPath)\" \"\(action.url)\""
    do {
        try safeShell(command)
        console.log(command)
    } catch {
        console.error(String(reflecting: error))
    }
}

func copyMoltenVK(cxAppPath: String, vulkanLibID: String) throws -> Void {
    let cxURL = URL(fileURLWithPath: cxAppPath)
    guard let layout = EngineLayout.of(cxURL) else {
        throw UnsupportedEngine(path: cxAppPath)
    }
    let moltenVKDest = cxURL.appendingPathComponent(SHARED_SUPPORT_COMPONENT + "/\(layout.moltenVKRoot())/libMoltenVK.dylib")
    console.log(moltenVKDest.path())
    switch (vulkanLibID) {
    case "latest":
        console.log(Bundle.main.url(forResource: "libMoltenVK-latest", withExtension: "dylib")?.path() ?? "")
        try copyResource(name: "libMoltenVK-latest.dylib", destUrl: moltenVKDest)
    case "experimental":
        console.log(Bundle.main.url(forResource: "libMoltenVK-experimental", withExtension: "dylib")?.path() ?? "")
        try copyResource(name: "libMoltenVK-experimental.dylib", destUrl: moltenVKDest)
    case "dbh":
        console.log(Bundle.main.url(forResource: "libMoltenVK-dbh", withExtension: "dylib")?.path() ?? "")
        try copyResource(name: "libMoltenVK-dbh.dylib", destUrl: moltenVKDest)
//    case "kosmickrisp":
//        if let url = Bundle.main.url(forResource: "libvulkan_kosmickrisp", withExtension: "dylib") {
//             try copyResource(name: "libMoltenVK-experimental2.dylib", destUrl: cxURL)
//        }
    default:
        try restoreOrig(destUrl: moltenVKDest)
    }
}

func launchWindowsGame(id: String, cxAppPath: String, selectedBottle: String, steamExePath: String, options: GameOptions? = nil, appExeURL: URL? = nil) async throws -> Void {
    console.log("options: \(options.debugDescription)")
    if let vulkanLibID = options?.vulkanLib {
        try copyMoltenVK(cxAppPath: cxAppPath, vulkanLibID: vulkanLibID)
    }
    guard !selectedBottle.isEmpty else {
        console.error("No bottle to launch into. If this title is set to run on ARM, choose an ARM bottle in Options -- or create one in CrossOver with the ARM architecture.")
        return
    }
    guard let bottleURL = URL(string: selectedBottle) else {
        console.error("Invalid bottle URL: \(selectedBottle)")
        return
    }

    // Wine services that outlived the server that owned them keep this bottle's
    // devices and registry claimed, and the next launch fails because of them.
    // They are cleared here rather than hoped away -- but only when no server
    // is alive in this bottle, because a live server means somebody is playing.
    await BottleProcesses.clearOrphans(inBottleAt: bottleURL)
    if(options == nil) {
        console.error("Missing game options for game with id \(id) - cannot launch (options = nil)")
        return
    }
    let f = FileManager.default

    var command = ""
    
    // registry
    let regOptionsDictionary: [String: UInt32] = [
        "DisableHidraw":options!.disableHidraw ? 1 : 0,
        "Enable SDL": options!.enableSDL ? 1 : 0
    ]
    
    let registryURL = bottleURL.appendingPathComponent("system.reg")
    let registry = WineRegistryFile(fileURL: registryURL)
    try registry.load()
    if let controllersSection = registry.section(forPath: "System\\\\CurrentControlSet\\\\Services\\\\winebus") {
        // Written only when it would change something. This rewrites the
        // bottle's entire system.reg -- 160,000 lines on this machine -- and
        // after a bottle's first launch these two values already hold what we
        // are about to set, so every launch after the first was a rewrite for
        // nothing. A file not written is a file not at risk.
        var changed = false
        regOptionsDictionary.keys.forEach { key in
            let value = regOptionsDictionary[key]!
            if controllersSection.addOrSetDword(forKey: key, value: value) {
                console.log("setting \(key) to \(value)")
                changed = true
            }
        }
        if changed { try registry.save() }
    } else {
        console.error("\\\\winebus section not found in system.reg file for the bottle \(selectedBottle)")
    }
    
    console.warn("applying config changes to the bottle \(selectedBottle)...")
    
    let bottleName = URL(string: selectedBottle)?.lastPathComponent ?? ""
    // From here on, any teardown decided before this moment is about a session
    // that no longer exists.
    LaunchGeneration.shared.launched()
    console.warn("attempting to run steam.exe on game id \(id)")
    let arguments = options != nil ? " " + options!.gameArguments : ""
    // A guard for an engine configured before the block existed, or chosen
    // some other way. Refusing at the picker alone would let a machine that
    // already points at a 27 keep launching on it.
    if let refusal = EngineLayout.refusal(for: URL(fileURLWithPath: cxAppPath)) {
        console.error(refusal)
        return
    }
    let x87cxAppURL = f.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).appendingPathComponent(PATCHED_CX_X87_APPNAME)
    // El bundle x87 sólo existe en 26; en 27 la precisión x87 es una variable.
    let useX87Bundle = options!.x87PatchEnabled && EngineLayout.of(URL(fileURLWithPath: cxAppPath)) == .cx26
    let steamBootOptions = "-nochatui -nofriendsui -silent -no-browser -no-cef-sandbox -skipinitialbootstrap"
    // CX_BOTTLE_PATH names the root this bottle lives under, so `--bottle` can
    // only resolve to this one.
    //
    // Without it the name is looked up under whatever root the engine happens
    // to use, and a name that also exists elsewhere wins there instead. This
    // machine has SteamARM under CrossOver's root and SteamArm under Procyon's;
    // macOS does not distinguish the case, so the launch would go to the wrong
    // bottle in silence. It works today only because the patched engine happens
    // to carry the redirection in its own configuration -- an accident to
    // depend on, not a design.
    let bottleRoot = URL(string: selectedBottle)?.deletingLastPathComponent().path(percentEncoded: false) ?? ""
    let wineEnvs = "CX_BOTTLE_PATH=\"\(bottleRoot)\" CX_ROOT=\"\(useX87Bundle ? x87cxAppURL.path() : cxAppPath)/Contents/SharedSupport/CrossOver\" WINEPREFIX=\"\(URL(string: selectedBottle)?.path ?? "")\" WINEDEBUG=-all WINEMSYNC=\(options!.wineMSync ? "1" : "0")"
    
//    try cpyd8d9DLLs(to: bottleURL, enable: options!.dx9PatchEnabled)
    
    let gameLaunchCommand = appExeURL != nil ? "\"\(appExeURL!.path(percentEncoded: false))\"" : "\"\(steamExePath)\" \(steamBootOptions) -applaunch \(String(id))"
    let cxAppURL = URL(fileURLWithPath: cxAppPath)
    // D3DMetal is x86 and an ARM bottle never loads it: there Direct3D goes
    // through DXMT. Copying ~60 MB of toolkit into the engine on every launch
    // to leave it unread is work for nothing, and it would misreport in the
    // HUD what is actually drawing.
    if bottleInfo(bottleURL)?.isARM == true {
        console.log("ARM bottle: skipping the D3DMetal install, DXMT draws here")
    } else {
        // Only where D3DMetal is what draws.
        //
        // The reasoning above about ARM applies to every backend that is not
        // D3DMetal, and was only applied to ARM. A DXMT title landed in
        // `default` and had sixty megabytes of toolkit copied into the engine
        // on every launch to be left unread -- and copied OVER whatever was
        // there. A machine set to D3DMetal 4 for one game had its engine put
        // back to 3 by the next game that used DXMT, and only half back: four
        // of those files exist in 4 and not in 3, so the copy fails partway
        // and leaves the two generations mixed. Those four "Couldn't find
        // source" errors in the log are that.
        //
        // `auto` still installs, because there the engine chooses and it may
        // choose D3DMetal.
        switch (options!.cxGraphicsBackend) {
        case "d3dmetal4":
            try installd3dMetal(at: cxAppURL, version: "4")
        case "d3dmetal3", "d3dmetal", "auto", "":
            try installd3dMetal(at: cxAppURL, version: "3")
        default:
            console.log("\(options!.cxGraphicsBackend) does not draw through D3DMetal; leaving the toolkit alone")
        }
    }
    
    if useX87Bundle {
        if(!f.fileExists(atPath: x87cxAppURL.path())) {
            console.error("Couldn't find \(x87cxAppURL.path())")
            return
        }
        let workdirCommand = appExeURL != nil ? "cd \"\(appExeURL!.deletingLastPathComponent().path(percentEncoded: false))\" && " : ""
        command = "\(workdirCommand)env \(EnvAssignments.removalArguments(options!.envVariables))\(getInlineEnvs(from: options!, cxAppPath: cxAppPath) + wineEnvs) \(x87cxAppURL.path())Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine \(gameLaunchCommand) \(arguments)"
    } else {
        command = "env \(EnvAssignments.removalArguments(options!.envVariables))\(getInlineEnvs(from: options!, cxAppPath: cxAppPath) + wineEnvs) \(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \(gameLaunchCommand) \(arguments)"
    }
    
    #if DEBUG
    console.log(command)
    #endif
    try safeShell(command)
}

func launchNativeGame(id: String, cxAppPath: String, selectedBottle: String, options: GameOptions? = nil, appExeURL: URL? = nil) async throws {
    let arguments = options != nil ? " " + options!.gameArguments : ""
    let steamBootOptions = "-nochatui -nofriendsui -silent -no-browser -applaunch"
    var command = ""
    if(appExeURL != nil) {
        command = "env \(getInlineEnvs(from: options!)) open \"\(appExeURL!.path(percentEncoded: false))\" \(arguments)"
    } else {
        command = "env \(getInlineEnvs(from: options!)) /Applications/Steam.app/Contents/MacOS/steam_osx \(steamBootOptions) \(String(id)) \(arguments)"
    }
    console.warn(command)
    try safeShell(command)
}

/// Ask the Steam client in the bottle to install a title.
///
/// This was an empty body with three commented-out steamcmd invocations and no
/// callers, so the button on every not-installed card did nothing. steamcmd was
/// the wrong tool anyway: it wants the user's credentials. The protocol handler
/// wants nothing, and Steam asks the user itself.
func installGame(id: String, cxAppPath: String?, selectedBottle: String?, SteamX86AppPath: String) {
    runSteamAction(.install(id), cxAppPath: cxAppPath,
                   selectedBottle: selectedBottle, SteamX86AppPath: SteamX86AppPath)
}
