//
//  Launcher.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 24/02/2026.
//

import AppKit

func closeWineActivities() async throws {
    // Wait for graceful termination, then escalate to forceTerminate, then give a final wait
    let gracePeriod: UInt64 = 2_000_000_000 // 2 seconds in nanoseconds
    let pollInterval: UInt64 = 200_000_000  // 0.2 seconds in nanoseconds
//    let forceTimeout: UInt64 = 6_000_000_000 // ~6 seconds total before force
    let absoluteTimeout: UInt64 = 12_000_000_000 // ~12 seconds absolute timeout

    
    // Capture the target apps first to avoid the list changing while iterating
    let targets = NSWorkspace.shared.runningApplications.filter { app in
        if let bundleURL = app.bundleURL {
            return bundleURL.lastPathComponent.lowercased().hasSuffix(".exe") || bundleURL.lastPathComponent.lowercased().contains("wine")
        }
        if let executableURL = app.executableURL {
            return (
                executableURL.lastPathComponent.lowercased().hasSuffix(".exe") || executableURL.lastPathComponent.lowercased().contains("wine")
            )
        }
        return false
    }
    print(
        NSWorkspace.shared.runningApplications.flatMap({
            [$0.localizedName ?? "-" , $0.bundleURL?.lastPathComponent ?? "-", $0.executableURL?.lastPathComponent ?? "-"]
        })
    )
    print(targets.debugDescription)
    // Send terminate to all matching apps
    for app in targets {
        if let name = (app.executableURL != nil ? app.executableURL : app.bundleURL)?.lastPathComponent {
            console.warn("terminating \(name)")
        }
        app.terminate()
    }

    // Helper to check if all targets have terminated
    func allTerminated(_ apps: [NSRunningApplication]) -> Bool {
        apps.allSatisfy { $0.isTerminated }
    }

    var elapsed: UInt64 = 0
    // First grace period loop
    while !allTerminated(targets) && elapsed < gracePeriod {
        try await Task.sleep(nanoseconds: pollInterval)
        elapsed += pollInterval
    }

    // If still not all terminated after grace period, escalate with terminate
    if !allTerminated(targets) {
        for app in targets where !app.isTerminated {
            console.warn("force terminating \(app.executableURL?.lastPathComponent ?? "<unknown>")")
            app.forceTerminate()
        }
    }

    // Final wait until absolute timeout or done
    while !allTerminated(targets) && elapsed < absoluteTimeout {
        try await Task.sleep(nanoseconds: pollInterval)
        elapsed += pollInterval
    }
}

func quitSteam(cxAppPath: String, bottleName: String, isNative: Bool) async throws -> Void {
    console.log("quitting steam...")
    if(isNative) {
        let steamBundleID = "com.valvesoftware.steam"
        if let steamApp = NSRunningApplication.runningApplications(withBundleIdentifier: steamBundleID).first {
            steamApp.terminate() // polite request to quit
        }
    } else {
        try safeShell("\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \"C:\\Program Files (x86)\\Steam\\Steam.exe\" -shutdown")
    }
}

func quitWine(cxAppPath: String, bottleName: String) async throws -> Void {
    console.log("quitting wine...")
    try safeShell("\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) wineserver -k")
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
        regOptionsDictionary.keys.forEach { key in
            let value = regOptionsDictionary[key]!
            console.log("setting \(key) to \(value)")
            controllersSection.addOrSetDword(forKey: key, value: value)
        }
        try registry.save()
    } else {
        console.error("\\\\winebus section not found in system.reg file for the bottle \(selectedBottle)")
    }
    
    console.warn("applying config changes to the bottle \(selectedBottle)...")
    
    let bottleName = URL(string: selectedBottle)?.lastPathComponent ?? ""
    console.warn("attempting to run steam.exe on game id \(id)")
    let arguments = options != nil ? " " + options!.gameArguments : ""
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
        switch (options!.cxGraphicsBackend) {
            case "d3dmetal4":
                try installd3dMetal(at: cxAppURL, version: "4")
            case "d3dmetal3":
                try installd3dMetal(at: cxAppURL, version: "3")
            default:
                try  installd3dMetal(at: cxAppURL, version: "3")
        }
    }
    
    if useX87Bundle {
        if(!f.fileExists(atPath: x87cxAppURL.path())) {
            console.error("Couldn't find \(x87cxAppURL.path())")
            return
        }
        let workdirCommand = appExeURL != nil ? "cd \"\(appExeURL!.deletingLastPathComponent().path(percentEncoded: false))\" && " : ""
        command = "\(workdirCommand)env \(getInlineEnvs(from: options!, cxAppPath: cxAppPath) + wineEnvs) \(x87cxAppURL.path())Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine \(gameLaunchCommand) \(arguments)"
    } else {
        command = "env \(getInlineEnvs(from: options!, cxAppPath: cxAppPath) + wineEnvs) \(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \(gameLaunchCommand) \(arguments)"
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
