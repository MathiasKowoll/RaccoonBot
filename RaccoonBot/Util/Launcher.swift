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

/// The bottle a Stop pressed now acts on, marked stopped before anything is
/// done about it.
///
/// Marked at the press, not when the stop's own task first runs: a launch
/// still waiting for this bottle asks as soon as its wait is over, and must not
/// start into a bottle the user has just stopped -- see
/// LaunchGeneration.stopped. One function for every Stop button, so a button
/// learns which bottle to close only by marking it, and the bottle it closes
/// and the bottle it marks are the same one. An Epic title runs where its
/// launcher is.
@discardableResult
func stopPressed(isEpic: Bool, selectedBottle: String) -> String {
    let bottle = isEpic
        ? (EpicLaunch.target(settings: StoreConfig.settings(for: .epic), selectedBottle: selectedBottle)?.bottle ?? selectedBottle)
        : selectedBottle
    LaunchGeneration.shared.stopped(bottle: bottle)
    return bottle
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
/// Where a HID trace of this launch is kept.
///
/// The Desktop, named by the clock, the same shape
/// MacGameVideoFix's diagnostics/capture-hid-trace.sh uses -- so the reader
/// that answers these logs takes either without being told which made it.
func hidTraceLogPath() -> String {
    let f = DateFormatter()
    f.dateFormat = "HHmmss"
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/hid-\(f.string(from: Date())).log")
        .path(percentEncoded: false)
}

/// The part of a launch that comes before anything is done to the bottle: the
/// launch is counted, the bottle is waited for and its orphans cleared, and
/// after each of those waits the launch asks whether it is still wanted.
///
/// Returns the generation the launch goes ahead as, or nil when it is no
/// longer wanted -- and then `launch` has been told why, so the tracker armed
/// for it stands down.
///
/// Out of launchWindowsGame so its order can be tested. The count comes before
/// the first wait, and it used to come after the registry. The wait can last
/// BottleProcesses' whole bound, and two things can happen during it that must
/// be judged against this launch. A grace teardown of the last session in this
/// bottle can reach its check inside the wait: with no count yet it passes,
/// and Steam is sent its shutdown under this launch. And a Stop pressed inside
/// the wait closes the bottle with the generation it finds: a count after that
/// stands its teardown down, and the title is started anyway. The two waits
/// are parameters only so a test can press Stop or Play inside them; the
/// launch passes neither.
func readyBottleForLaunch(id: String, bottle: String, bottleURL: URL, hidTraceEnabled: Bool,
                          launch: PendingLaunch?,
                          settle: (URL) async -> BottleProcesses.Settling = { await BottleProcesses.letShortLivedPrefixComeDown(inBottleAt: $0) },
                          clearOrphans: (URL) async -> Void = { await BottleProcesses.clearOrphans(inBottleAt: $0) }) async -> Int? {
    // From here on, any teardown decided before this moment is about a session
    // that no longer exists. So nothing between the top of this function and
    // this line may await.
    let generation = LaunchGeneration.shared.launched(bottle: bottle)

    // Whether this launch is still wanted, asked once each wait below is over
    // and before the next thing it does to the bottle. A Play pressed in the
    // meantime has a launch of its own coming through the same wait. A Stop
    // pressed in the meantime has closed the bottle or is closing it, and that
    // teardown cannot end a launch that has not run anything yet, so the
    // launch has to ask -- see LaunchGeneration.stopped.
    func noLongerWanted() -> Bool {
        if LaunchGeneration.shared.supersedes(generation, for: bottle) {
            console.log("not launching game id \(id): another launch was started while this one waited for the bottle")
            launch?.decide(.superseded)
            return true
        }
        if LaunchGeneration.shared.wasStopped(generation, for: bottle) {
            console.log("not launching game id \(id): Stop was pressed while this launch waited for the bottle")
            launch?.decide(.abandoned)
            return true
        }
        return false
    }

    // A launch that follows a short wine command -- such as the reg.exe runs
    // PatchAll already waits out -- can find that command's prefix still up,
    // and then joins it instead of starting the bottle: the registry rule
    // in launchWindowsGame skips this title's controller settings with nothing
    // of the user's in the bottle, and a HID trace misses winebus, which keeps
    // the debug channels of whatever started it. So a bottle holding only
    // wine's own processes gets up to BottleProcesses' bound to come down
    // first. It only waits; nothing is ended, and a bottle in use is not
    // waited for.
    let settling = await settle(bottleURL)
    // Before the lines about the wait and before clearOrphans: a launch
    // nobody wants any more has nothing to say about a trace it will not
    // write, and no business ending processes in a bottle that a Stop is
    // closing or a newer launch will clear for itself.
    if noLongerWanted() { return nil }
    if case .cameDown(let seconds) = settling {
        console.log("this bottle was up with only wine's own processes in it; it came down after \(seconds) s, before this launch")
    }
    if hidTraceEnabled, let warning = BottleProcesses.hidTraceWarning(after: settling) {
        console.warn(warning)
    } else if case .stillUp(let seconds, let names) = settling {
        console.log("this bottle stayed up for \(seconds) s with only wine's own processes in it (\(names.joined(separator: ", "))); launching into it as it is")
    }

    // Wine services that outlived the server that owned them keep this bottle's
    // devices and registry claimed, and the next launch fails because of them.
    // They are cleared here rather than hoped away -- but only when no server
    // is alive in this bottle, because a live server means somebody is playing.
    //
    // After the wait, not before it. Before it, a server still alive made this
    // leave the bottle alone, and whatever outlived that server when it went
    // during the wait reached the launch uncleared.
    await clearOrphans(bottleURL)
    // Asked again, because clearing orphans waits for them to end.
    if noLongerWanted() { return nil }
    return generation
}

func launchWindowsGame(id: String, cxAppPath: String, selectedBottle: String, steamExePath: String, options: GameOptions? = nil, appExeURL: URL? = nil, launcherURI: String? = nil, launch: PendingLaunch? = nil) async throws -> Void {
    // However this function ends before the title's command has run -- a
    // guard, a refusal, a throw, a stand-down -- the tracker armed for it is
    // told that nothing was started. Only the first answer counts, so this
    // does not undo the start recorded after the command, nor a stand-down.
    defer { launch?.decide(.abandoned) }
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

    if(options == nil) {
        console.error("Missing game options for game with id \(id) - cannot launch (options = nil)")
        return
    }

    // Counted, waited for and cleared of orphans before anything below is done
    // to the bottle -- see readyBottleForLaunch. It is the only wait in this
    // function: from here the registry is written and the title started
    // without another suspension, so a Stop or a Play that its last check
    // did not see comes after the title's command.
    guard let generation = await readyBottleForLaunch(id: id, bottle: selectedBottle, bottleURL: bottleURL,
                                                      hidTraceEnabled: options!.hidTraceEnabled,
                                                      launch: launch) else { return }
    let f = FileManager.default

    var command = ""
    
    // registry
    let regOptionsDictionary: [String: UInt32] = [
        "DisableHidraw":options!.disableHidraw ? 1 : 0,
        "Enable SDL": options!.enableSDL ? 1 : 0
    ]
    
    let registryURL = bottleURL.appendingPathComponent("system.reg")
    let registry = WineRegistryFile(fileURL: registryURL)
    // Not while the bottle is up. Before the per-game pad option, these two
    // or three values changed only when the pad's transport did, so this file
    // was almost never written; now a value is written for both DualSense
    // models on every launch, and alternating between a title set to wired and
    // one set to as-is would rewrite all 160,000 lines of it every time --
    // possibly under a wineserver that holds its own copy and flushes it on
    // shutdown, which would both lose our write and put the file at risk. So
    // the bottle that is up keeps its registry, and the console says so: a
    // running bottle read these values when it booted and cannot be told
    // otherwise from here anyway.
    if !BottleProcesses.registryIsOursToWrite(inBottleAt: bottleURL) {
        console.warn("this bottle is already running, so its registry was left alone: the controller settings for this title -- Enable SDL, Disable Hidraw, what a DualSense is seen as, what its motors do, its lights and when an idle one is turned off -- were not written. A running bottle whose engine turns off an idle pad uses the time it booted with, or 20 minutes where it was never given one, even with the setting Off. A bottle reads them when it boots, so close what is running in it (the launcher and its games) and start this title again.")
    } else {
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
            // A DualSense goes through SDL when it is on Bluetooth and stays raw
            // when it is not -- see DualSenseRoute for the measurement behind it --
            // and, on an engine that can do it, is presented to this title the way
            // this title's own options ask for and its motors do what they ask
            // for. Written the same way as the two keys above, into the same
            // file, on the same condition: only when something would change.
            //
            // All nine values -- the six for route, presentation, motors and
            // XInput, the two for the lights, and IdlePowerOffMinutes -- are
            // written for both models on every launch, the neutral ones
            // included, and whatever is attached at this moment. The first
            // eight follow this title's options; IdlePowerOffMinutes is the
            // one application-wide setting, the same under both keys for
            // every title.
            // That is what makes these per game -- the title that wants the pad
            // as it is clears what the last title set rather than inheriting it
            // -- and it is what lets the console's own advice work: winebus reads
            // them as the pad arrives, so the pad plugged in or woken up after
            // this finds them already there. Neutral is not all zeros: a
            // VibrationGain of 0 is silence, and 100 is the value that leaves a
            // game's rumble alone.
            //
            // Every question about the engine -- the route, the emulation, the
            // motors, XInput and the lights -- is asked of its winebus by the
            // name of a value in the binary, never a version number, and the
            // console sentence and the registry values are built together from
            // one reading of the saved options. A pad on SDL or an engine
            // without a patch gets the neutral values, and the summary says why.
            let plan = DualSenseRoute.launchPlan(options: options!, pads: SonyPads.attached(),
                                                 engine: .of(cxAppPath: cxAppPath),
                                                 idlePowerOffMinutes: IdlePadPowerOff.storedMinutes())
            if let summary = plan.summary {
                console.log("controller: \(summary)")
            }
            for override in plan.overrides {
                for (key, value) in DualSenseRoute.write(override, into: registry) {
                    console.log("setting \(override.path) \(key) to \(value)")
                    changed = true
                }
            }
            if changed { try registry.save() }
        } else {
            console.error("\\\\winebus section not found in system.reg file for the bottle \(selectedBottle)")
        }
    }
    
    // An Unreal title reads its own Engine.ini at startup, so whatever it needs
    // from us has to be on disk before the process exists. Today that is one
    // console variable: D3DMetal presents the adapter as "AMD Compatibility
    // Mode" with NVIDIA's vendor id and a driver version of "10.00", Unreal
    // matches its NVIDIA deny-list, and every Unreal title opens with a
    // graphics-driver warning that has nothing to do with the title.
    //
    // Written on every launch rather than once, because a title can delete an
    // Engine.ini it did not write -- Beast of Reincarnation does, on exit --
    // and making the file read-only does not stop it: unlink needs write
    // permission on the directory, not on the file.
    //
    // A Steam launch has no executable path here, only the app id, so the two
    // stores are answered from different sources. Quiet when it cannot name a
    // directory: nothing is guessed into one that might be another title's.
    UnrealConfig.applyAtLaunch(
        bottle: bottleURL,
        steamAppID: Int(id) != nil ? id : nil,
        steamRoot: bottleURL.appendingPathComponent(DEFAULT_STEAM_WINE_PATH.hasPrefix("/")
                                                    ? String(DEFAULT_STEAM_WINE_PATH.dropFirst())
                                                    : DEFAULT_STEAM_WINE_PATH),
        exe: appExeURL)

    console.warn("applying config changes to the bottle \(selectedBottle)...")
    
    let bottleName = URL(string: selectedBottle)?.lastPathComponent ?? ""
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
    // CX_DEBUGMSG, not WINEDEBUG, and it took a whole session to learn why.
    // The command below goes through CrossOver's bin/wine, which is a Perl
    // script that BUILDS the environment of everything it starts and feeds
    // WINEDEBUG from its own CX_DEBUGMSG:
    //
    //     $ENV{WINEDEBUG} = $opt_debugmsg if (defined $opt_debugmsg);
    //
    // So a WINEDEBUG set here never reaches the wineserver it forks, and so
    // never reaches winedevice.exe -- which is where winebus lives and the only
    // process whose traces answer a controller question. What that failure
    // looks like is a log full of msync and MoltenVK lines and not one line of
    // trace:hid: output flowing, channel off, every count reading as "the pad
    // did nothing". The WINEDEBUG below is kept because it costs nothing and
    // would be read if this ever stopped going through the Perl script.
    //
    // "-all" first and then "+hid": asking for +hid alone leaves unwind,
    // module, process, seh and loaddll on as well -- 1.6 million lines in under
    // two minutes, a third of them nothing to do with the pad, and the game too
    // slow to reach the thing being investigated. The trace would change what
    // it measures.
    let traceChannels = options!.hidTraceEnabled ? "-all,+timestamp,+hid" : "-all"
    let wineEnvs = "CX_BOTTLE_PATH=\"\(bottleRoot)\" CX_ROOT=\"\(cxAppPath)/Contents/SharedSupport/CrossOver\" WINEPREFIX=\"\(URL(string: selectedBottle)?.path ?? "")\" WINEDEBUG=\(traceChannels) CX_DEBUGMSG=\(traceChannels) WINEMSYNC=\(options!.wineMSync ? "1" : "0")"
    
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

        // The trace goes to a file rather than to this application's console.
        // A +hid session is hundreds of thousands of lines and the console is
        // where a person reads what the launcher decided; drowning it would
        // cost more than the trace is worth. The redirect also outlives this
        // command: Steam forks and returns, and the descriptor stays open in
        // the processes that keep writing, which is what makes the log cover
        // the whole session and not just the launch.
        if options!.hidTraceEnabled {
            let log = hidTraceLogPath()
            command += " > \"\(log)\" 2>&1"
            console.log("HID trace: keeping this session's controller traffic in \(log)")
            console.log("read it with MacGameVideoFix's diagnostics/read-hid-trace.sh")
        }
    
    #if DEBUG
    console.log(command)
    #endif
    try safeShell(command)
    // Recorded once the command has run and not before: a command that throws
    // started nothing, and the tracker's watches should count from here rather
    // than from the wait for the bottle.
    launch?.decide(.started(generation: generation))

    // While a game runs under wine, macOS sees no input at all: the pad is
    // opened exclusively by the bottle, so not one of its reports reaches the
    // system, and a game asks for no keyboard and no mouse. Half an hour in,
    // the idle timer runs out and the screen saver comes up over the game. So
    // it is told, the way a video player tells it, for as long as this bottle
    // has a game in it.
    ScreenAwake.watch(bottleAt: bottleURL)
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
/// Install through the Epic launcher, which will not take one on its own
/// command line -- see `EpicReadiness`. Start it plain, wait for its own log to
/// say it is up, then knock: delivering to a launcher already running is the
/// only shape ever measured to reach the install dialog.
///
/// The wait is visible without any spinner of ours: the launcher window opens
/// within a second or two, and the install dialog lands on top of it about ten
/// seconds later.
func openEpicForInstall(cxAppPath: String?, bottle: String, clientPath: String, uri: String) async {
    guard let directory = BottleReference(bottle)?.directory else {
        console.error("epic: cannot resolve the bottle directory for \(bottle)")
        return
    }
    if EpicReadiness.isRunning(inBottleAt: directory) {
        openEpic(cxAppPath: cxAppPath, bottle: bottle, clientPath: clientPath, uri: uri)
        return
    }
    // Read the header BEFORE starting, or the log we later find is this same
    // file and its old marker answers for the new session.
    let log = EpicLauncherLogWatcher.logURL(inBottleAt: directory)
    let previousHeader = (try? String(contentsOf: log, encoding: .utf8))
        .flatMap(EpicReadiness.header(of:))
    console.log("epic: launcher not running; starting it before the install")
    openEpic(cxAppPath: cxAppPath, bottle: bottle, clientPath: clientPath)
    let ready = await EpicReadiness.waitUntilInstallable(log: log, after: previousHeader)
    if !ready {
        console.error("epic: the launcher never said it was ready; sending the install anyway")
    }
    openEpic(cxAppPath: cxAppPath, bottle: bottle, clientPath: clientPath, uri: uri)
}

func runInstall(_ route: Install.Route, cxAppPath: String?, selectedBottle: String,
                windowsSteamFolder: URL?) async {
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
        guard let uri else {
            console.error("epic: the id is missing the namespace or the catalogue item, so there is no install URI; opening the launcher instead")
            openEpic(cxAppPath: cxAppPath, bottle: epic.bottle, clientPath: epic.clientPath)
            return
        }
        await openEpicForInstall(cxAppPath: cxAppPath, bottle: epic.bottle,
                                 clientPath: epic.clientPath, uri: uri)
    }
}

/// Asks Steam to uninstall the title. The removal, and the confirmation in
/// front of it, are the client's: this only knocks on the door.
func uninstallSteamGame(id: String, cxAppPath: String?, selectedBottle: String?, SteamX86AppPath: String) {
    runSteamAction(.uninstall(id), cxAppPath: cxAppPath,
                   selectedBottle: selectedBottle, SteamX86AppPath: SteamX86AppPath)
}
