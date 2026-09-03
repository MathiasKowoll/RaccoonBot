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
/// `clients` are the name prefixes of the store clients waited for: "steam"
/// for Steam, "epic" for the Epic launcher, whose processes are
/// EpicGamesLauncher, EpicWebHelper and EpicOnlineServices.
///
/// More than one because a bottle can hold more than one: the Epic launcher
/// is installed into whichever bottle the user pointed at, which here is the
/// Steam one, and a teardown that waited only for Epic's processes would
/// reach `wineserver -k` while Steam was still winding down.
func closeBottle(cxAppPath: String, bottle: String,
                 waitingUpTo settleTimeout: TimeInterval = 30,
                 clients: [String] = ["steam"],
                 decidedAt generation: Int? = nil) async throws {
    // Taken here rather than as a default argument: the generation belongs to
    // a bottle now, and Swift will not let one default argument read another
    // parameter.
    let generation = generation ?? LaunchGeneration.shared.current(for: bottle)
    // Asked before every destructive step, not once at the top. The waits below
    // run for half a minute, and a launch inside that window was destroyed by a
    // decision taken before it existed.
    func superseded() -> Bool {
        if LaunchGeneration.shared.supersedes(generation, for: bottle) {
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
        if !here.contains(where: { p in clients.contains { p.name.lowercased().hasPrefix($0) } }) {
            console.log("\(clients.joined(separator: " and ")) has gone; ending what wine keeps running")
            break
        }
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    let left = BottleProcesses.running(inBottleAt: directory)
    if left.contains(where: { p in clients.contains { p.name.lowercased().hasPrefix($0) } }) {
        console.warn("\(clients.joined(separator: " and ")) did not go in \(Int(settleTimeout))s: "
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

/// Ask the Epic launcher to leave. `taskkill` without /F sends WM_CLOSE, the
/// same request the launcher's own close button makes; /F would be the kill
/// that this whole path exists to avoid. The launcher has no `-shutdown` of
/// Steam's kind (read from the 5.5.4 binary: it has -silent, -noselfupdate,
/// -nullrhi, nothing to end it). If it stays in the tray anyway, closeBottle
/// waits for it as it waits for Steam and then ends the prefix; by then the
/// launcher has been given its time.
func quitEpic(cxAppPath: String, bottle: String) async throws {
    console.log("asking the epic launcher to leave...")
    guard let ref = BottleReference(bottle) else {
        console.error("cannot quit the epic launcher: \(bottle) does not name a bottle")
        return
    }
    try safeShell("\(ref.environmentPrefix)\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \"\(ref.name)\" taskkill /IM EpicGamesLauncher.exe")
}

/// Stop an Epic title by hand: the GAME is asked to close, not the launcher.
///
/// Stopping a Steam title asks Steam to shut down, which takes the game with
/// it and syncs on the way. The Epic launcher has no such request, and ending
/// the bottle under a running game is a save lost. So the game itself gets
/// WM_CLOSE -- most titles quit and save on it -- and the session's tracker
/// then does what it does when a game exits on its own: waits for the
/// launcher to finish syncing, asks it to leave, closes the bottle.
func stopEpicGame(appNames: [String], cxAppPath: String, bottle: String) async throws {
    guard let ref = BottleReference(bottle) else { return }
    for name in appNames where name.lowercased().hasSuffix(".exe") {
        console.log("asking \(name) to close...")
        try safeShell("\(ref.environmentPrefix)\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \"\(ref.name)\" taskkill /IM \"\(name)\"")
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

/// Open the Epic Games Launcher.
///
/// Ours showed "Unsupported Graphics Card". Its log: a Direct3D 11 device,
/// then every CreateVertexShader and CreatePixelShader returning E_INVALIDARG,
/// then "failed to initialise slate renderer". It was a 32-bit UE 4.27 launcher
/// from a March-2025 installer that had never managed its first self-update.
/// The bottle that works runs a self-updated UE 5.5.4, x86-64 -- on the same
/// generation-4 toolkit build as ours, byte for byte. The launcher was the
/// difference, and putting generation 3 in first was tried and changed
/// nothing, so this no longer touches the toolkit: whatever the last game
/// asked for stays, and the launcher is what gets fixed.
///
/// Refuses a bottle newer than the engine. Wine updates a bottle it meets
/// with a different engine, and with an older engine that is a downgrade of
/// the bottle's system files -- the one way to take a working Epic bottle and
/// leave it like ours.
/// `uri`, when given, is handed to the launcher as its one argument, the way
/// its own shortcuts do it: that is how the client is asked to install a
/// title. With no argument the launcher just opens.
func openEpic(cxAppPath: String?, bottle: String, clientPath: String, uri: String? = nil) {
    guard let cxAppPath, !cxAppPath.isEmpty, let bottleURL = URL(string: bottle) else { return }
    if let made = EpicLaunch.bottleVersion(of: bottle),
       let engine = (NSDictionary(contentsOfFile: cxAppPath + "/Contents/Info.plist")?["CFBundleVersion"] as? String),
       EpicLaunch.bottleIsNewer(bottleVersion: made, engineVersion: engine) {
        console.error("epic: refusing to open a bottle made by CrossOver \(made) with engine \(engine); wine would downgrade it")
        return
    }
    let bottleName = bottleURL.lastPathComponent
    let bottleRoot = bottleURL.deletingLastPathComponent().path(percentEncoded: false)
    let command = "CX_BOTTLE_PATH=\"\(bottleRoot)\" MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0 "
        + "CX_GRAPHICS_BACKEND=\"d3dmetal\" "
        + "\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \"\(clientPath)\""
        + (uri.map { " \"\($0)\"" } ?? "")
    do {
        try safeShell(command)
        console.log(command)
    } catch {
        console.error(String(reflecting: error))
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
    /// Steam's own way out, not ours: for every installed title Steam writes
    /// `UninstallString = "steam.exe" steam://uninstall/<appid>` under
    /// Uninstall in the bottle's registry, so this is the exact command
    /// Windows would run from Add/Remove Programs. The client asks for
    /// confirmation itself and removes the files, the manifest and the
    /// shortcut together -- which is what deleting the folder by hand does
    /// not do.
    case uninstall(String)

    var url: String {
        switch self {
        case .install(let id):   return "steam://install/\(id)"
        case .run(let id):       return "steam://run/\(id)"
        case .validate(let id):  return "steam://validate/\(id)"
        case .uninstall(let id): return "steam://uninstall/\(id)"
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

/// `launcherURI`, when given, is handed to `appExeURL` as its one argument:
/// that is how an Epic title starts -- the Epic launcher is the executable and
/// the com.epicgames.launcher:// URI names the game -- so everything this
/// function sets up for a Steam or a custom title (the winebus keys, the
/// D3DMetal generation, the environment from the game's options, msync) is set
/// up for the launcher, and the game inherits it from there. If a launcher is
/// ALREADY running in the bottle, the new one hands the URI over and exits,
/// and the game inherits the running launcher's environment instead: opened
/// from the Epic panel, say, without any of this. That is the one case in
/// which the game's options do not reach it.
func launchWindowsGame(id: String, cxAppPath: String, selectedBottle: String, steamExePath: String, options: GameOptions? = nil, appExeURL: URL? = nil, launcherURI: String? = nil) async throws -> Void {
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
    LaunchGeneration.shared.launched(bottle: selectedBottle)
    console.warn("attempting to run steam.exe on game id \(id)")
    let arguments = options != nil ? " " + options!.gameArguments : ""
    // A guard for an engine configured before the block existed, or chosen
    // some other way. Refusing at the picker alone would let a machine that
    // already points at a 27 keep launching on it.
    if let refusal = EngineLayout.refusal(for: URL(fileURLWithPath: cxAppPath)) {
        console.error(refusal)
        return
    }
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
    let wineEnvs = "CX_BOTTLE_PATH=\"\(bottleRoot)\" CX_ROOT=\"\(cxAppPath)/Contents/SharedSupport/CrossOver\" WINEPREFIX=\"\(URL(string: selectedBottle)?.path ?? "")\" WINEDEBUG=-all WINEMSYNC=\(options!.wineMSync ? "1" : "0")"
    
//    try cpyd8d9DLLs(to: bottleURL, enable: options!.dx9PatchEnabled)
    
    let gameLaunchCommand: String
    if let appExeURL, let launcherURI {
        gameLaunchCommand = "\"\(appExeURL.path(percentEncoded: false))\" \"\(launcherURI)\""
    } else if let appExeURL {
        gameLaunchCommand = "\"\(appExeURL.path(percentEncoded: false))\""
    } else {
        gameLaunchCommand = "\"\(steamExePath)\" \(steamBootOptions) -applaunch \(String(id))"
    }
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
    
    // The x87 bundle is gone (2026-09-01). It was a second engine selected by
    // the "reduced x87 precision" toggle, and what actually distinguished it
    // was not precision: d9vk, ntdll and win32u lived only there, because the
    // resource table filtered them out of the normal copy. So the toggle meant
    // "use the engine that has d9vk", two unrelated things behind one switch.
    //
    // Removed because no current title needs it, confirmed with Mathias, and
    // because it was the last path that derived an engine from a NAME rather
    // than from the configured path -- which would have broken the moment
    // MacGameVideoFix started making the copy and calling it something else.
    //
    // Reduced precision itself stays: on 27 it is FEX_X87REDUCEDPRECISION and
    // on 26 ROSETTA_X87_PATH, both environment, neither needing a bundle.
        command = "env \(EnvAssignments.removalArguments(options!.envVariables))\(getInlineEnvs(from: options!, cxAppPath: cxAppPath) + wineEnvs) \(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \(gameLaunchCommand) \(arguments)"
    
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

/// Carry out an install, whichever client it belongs to.
///
/// One function for both lists: the not-installed tab and the mixed grid both
/// offer Install, and each used to work it out for itself.
func runInstall(_ route: Install.Route, cxAppPath: String?, selectedBottle: String,
                windowsSteamFolder: URL?) {
    switch route {
    case .steamOnMac(let appID):
        guard let url = URL(string: "steam://install/\(appID)") else { return }
        NSWorkspace.shared.open(url)
    case .steamInBottle(let appID):
        let steamX86AppPath = windowsSteamFolder?
            .appendingPathComponent("Steam.exe").path(percentEncoded: false)
            ?? "C:\\Program Files (x86)\\Steam\\Steam.exe"
        installGame(id: appID, cxAppPath: cxAppPath, selectedBottle: selectedBottle,
                    SteamX86AppPath: steamX86AppPath)
    case .epicInBottle(let uri):
        guard let epic = EpicLaunch.target(settings: StoreConfig.settings(for: .epic),
                                           selectedBottle: selectedBottle) else {
            console.error("epic: no bottle configured for the launcher; nothing can install this")
            return
        }
        if uri == nil {
            console.error("epic: the id is missing the namespace or the catalogue item, so there is no install URI; opening the launcher instead")
        }
        openEpic(cxAppPath: cxAppPath, bottle: epic.bottle, clientPath: epic.clientPath, uri: uri)
    }
}

/// Asks Steam to uninstall the title. The removal, and the confirmation in
/// front of it, are the client's: this only knocks on the door.
func uninstallSteamGame(id: String, cxAppPath: String?, selectedBottle: String?, SteamX86AppPath: String) {
    runSteamAction(.uninstall(id), cxAppPath: cxAppPath,
                   selectedBottle: selectedBottle, SteamX86AppPath: SteamX86AppPath)
}
