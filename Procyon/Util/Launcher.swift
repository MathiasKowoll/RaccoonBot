//
//  Launcher.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//

import AppKit

func closeWineActivities(cxAppPath: String, bottleName: String) async throws {
    // Wait for graceful termination, then escalate to forceTerminate, then give a final wait
    let gracePeriod: UInt64 = 2_000_000_000 // 2 seconds in nanoseconds
    let pollInterval: UInt64 = 200_000_000  // 0.2 seconds in nanoseconds
//    let forceTimeout: UInt64 = 6_000_000_000 // ~6 seconds total before force
    let absoluteTimeout: UInt64 = 12_000_000_000 // ~12 seconds absolute timeout

    
    // Capture the target apps first to avoid the list changing while iterating
    let targets = NSWorkspace.shared.runningApplications.filter { app in
        guard let url = app.executableURL else { return false }
        return url.lastPathComponent.lowercased().hasSuffix(".exe")
    }
    
    try await quitSteam(cxAppPath: cxAppPath, bottleName: bottleName) // try to close steam properly first

    // Send terminate to all matching apps
    for app in targets {
        if let name = app.executableURL?.lastPathComponent {
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

func quitSteam(cxAppPath: String, bottleName: String) async throws -> Void {
    try safeShell("\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \"C:\\Program Files (x86)\\Steam\\Steam.exe\" -shutdown")
    try safeShell("\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) wineserver -k")
}

func launchWindowsGame(id: String, cxAppPath: String, selectedBottle: String, options: GameOptions? = nil) async throws -> Void {
    if(options != nil){
        let optionsDictionary = [
            "CX_GRAPHICS_BACKEND": options!.cxGraphicsBackend,
            "WINEMSYNC": options!.wineMSync ? "1" : "0",
            "MTL_HUD_ENABLED": options!.mtlHudEnabled ? "1" : "0"
        ]
        let regOptionsDictionary = [
            "DisableHidraw":options!.disableHidraw ? "1" : "0",
            "Enable SDL": options!.enableSDL ? "1" : "0"
        ]
        console.warn("applying config changes to the bottle \(selectedBottle)...")
        try editCXBottleConfigFile(selectedBottle: selectedBottle, options: optionsDictionary)
        try regOptionsDictionary.keys.forEach { key in
            let value = regOptionsDictionary[key]!
            try setReg(cxAppPath: cxAppPath, selectedBottle: selectedBottle, key: key, value: value)
        }
    }
    let bottleName = URL(string: selectedBottle)?.lastPathComponent ?? ""
    console.warn("restarting bottle...")
    try await closeWineActivities(cxAppPath: cxAppPath, bottleName: bottleName)
//    try await quitSteam(cxAppPath: cxAppPath, bottleName: bottleName)

    console.warn("attempting to run steam.exe on game id \(id)")
    let arguments = options != nil ? " " + options!.gameArguments : ""
    let command = "\(getInlineEnvs(from: options!)) \(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \"C:\\Program Files (x86)\\Steam\\Steam.exe\" -nochatui -nofriendsui -silent -no-browser -no-cef-sandbox -skipinitialbootstrap -applaunch \(String(id))" + arguments
    console.warn(command)
    try safeShell(command)
}

func setReg (cxAppPath: String, selectedBottle: String, key: String, value: String) throws -> Void {
    // wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\winebus" /v "Enable SDL" /t REG_DWORD /d 1 /f
    let bottleName = URL(string: selectedBottle)?.lastPathComponent ?? ""
    let command = "\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) reg add \"HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\winebus\\\" /v \"\(key)\" /t REG_DWORD /d \(value) /f"
    try safeShell(command)
}

func launchNativeGame(id: String, cxAppPath: String, selectedBottle: String, options: GameOptions? = nil) async throws {
    let bottleName = URL(string: selectedBottle)?.lastPathComponent ?? ""
    try await closeWineActivities(cxAppPath: cxAppPath, bottleName: bottleName)
    let arguments = options != nil ? " " + options!.gameArguments : ""
    let command = "\(getInlineEnvs(from: options!)) /Applications/Steam.app/Contents/MacOS/steam_osx -nochatui -nofriendsui -silent -no-browser -applaunch \(String(id))" + arguments
    console.warn(command)
    try safeShell(command)
}

func installGame(id: String) {
//    https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip
//    steamcmd +login YOUR_USERNAME +app_update 1489410 validate +quit
//    steamcmd +login USER +force_install_dir "C:\Program Files (x86)\Steam\steamapps\common\MyGame" +app_update 1489410 validate +quit
}
