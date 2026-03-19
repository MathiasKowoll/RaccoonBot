//
//  Crossover.swift
//  Procyon
//
//  Created by Italo Mandara on 26/02/2026.
//

import Foundation

func getCXDefaultBottlesURL() -> URL {
    let appID = "com.codeweavers.CrossOver" as CFString
    let key = "BottleDir" as CFString
    guard let bottlesPath = CFPreferencesCopyAppValue(key, appID) else {
        console.error("CrossOver preference 'BottleDir' not found")
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(DEFAULT_BOTTLE_PATH, isDirectory: true)
        return fallback
    }

    return URL(filePath: bottlesPath as! String)
}

func isCXPatched(appDir: URL) -> Bool {
    let f = FileManager.default
    return f.fileExists(atPath: appDir.appendingPathComponent("Contents/cxplog.txt").path(percentEncoded: false))
}

func getCXPatcherBottlesURL(appDir: URL)  throws -> URL {
    let f = FileManager.default
    let base = f.homeDirectoryForCurrentUser
    
    let confPath: URL = appDir.appendingPathComponent("/Contents/SharedSupport/CrossOver/etc/CrossOver.conf")
    let confFile = try String(contentsOf: confPath, encoding: .utf8)
    for line in confFile.components(separatedBy: "\n") {
        let (key, value) = parseCXEnvVarString(String(line))
        if key == "CX_BOTTLE_PATH" {
            if(value.contains("/Users/${USER}/")) {
                let path = value.split(separator: "/").last?.description ?? ""
                return base.appendingPathComponent(path, isDirectory: true)
            } else {
                return URL(filePath: value)
            }
        }
    }
    // fallback if it doesn't find it in the config file (just in case)
    console.warn("Couldn't find CXPatcher bottles configuration")
    let bottlePathForCXP: URL = base.appendingPathComponent("CXPBottles", isDirectory: true)
    return bottlePathForCXP
}

func getAllBottles(appDir: URL) -> [URL] {
    let f = FileManager.default
    
    do {
        var subfolders: [URL] = []
        
        if(isCXPatched(appDir: appDir)) {
            let bottlePathForCXP = try getCXPatcherBottlesURL(appDir: appDir)
            console.log("app is patched with CXPatcher")
            do {
                subfolders = try f.contentsOfDirectory(at: bottlePathForCXP, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            } catch {
                console.error(String(reflecting: error))
                console.error("couldn't find the CXPatched bottles")
            }
        } else {
            let bottlePath = getCXDefaultBottlesURL()
            console.warn(bottlePath.absoluteString)
            console.log("app is normal crossover")
            do {
                subfolders = try f.contentsOfDirectory(at: bottlePath, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants])
            } catch {
                console.error(String(reflecting: error))
                console.error("couldn't find the crossover bottles in \(bottlePath.path(percentEncoded: false))")
            }
        }
        console.warn("subfolders \(subfolders.debugDescription)")
        let filtered = subfolders.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        console.warn("filtered: \(filtered.debugDescription)")
        return filtered
    } catch {
        console.error(String(reflecting: error))
    }
    return []
}

func modifyBottleSettingOptions(selectedBottle: String, options: [String: String]) {
    options.forEach { option in
        console.warn("key: \(option.key), value: \(option.value)")
    }
}

func getCXBottleConfigFileURL(selectedBottle: String) -> URL? {
    return URL(string: selectedBottle)?.appendingPathComponent("cxbottle.conf")
}

func editCXBottleConfigFile(selectedBottle: String, options: [String: String]) throws {
    if let bottleURL = getCXBottleConfigFileURL(selectedBottle: selectedBottle) {
        let original = try String(contentsOf: bottleURL, encoding: .utf8)
        let lines = original.components(separatedBy: .newlines)
        let newLines = lines.map { line in
            for (key, value) in options {
                if(line.hasPrefix("\"\(key)\"")) {
                    return toCrossoverENVString(key, value)
                }
            }
            return line
        }
        let updated = newLines.joined(separator: "\n")
        try updated.write(to: bottleURL, atomically: true, encoding: .utf8)
    } else {
        console.error("No bottle selected in Procyon config")
    }
}

func getDxmtConfigEnv(values: String) -> String {
    return values == "" ? "" : "DXMT_CONFIG=\(values)"
}

func getInlineEnvs(from: GameOptions) -> String {
    func onOff(_ value: Bool?) -> String {
        return value != nil && value == true ? "1" : "0"
    }
    var value = "\(from.envVariables) "
    let defaults = "WINEDEBUG=-all "
    func DoubleToFormattedStr(_ value: Double, _ digits: Int = 2) -> String {
        return String(value.formatted(.number.precision(.fractionLength(0...digits))))
    }
    value += defaults
    let mtlHudEnabled = "MTL_HUD_ENABLED=\(onOff(from.mtlHudEnabled)) "
    value += mtlHudEnabled
    let advertiseAVX = "ROSETTA_ADVERTISE_AVX=\(onOff(from.advertiseAVX)) "
    value += advertiseAVX
    let dxmtMetalFXSpatial = "DXMT_METALFX_SPATIAL_SWAPCHAIN=\(onOff(from.dxmtMetalFXSpatial)) "
    value += dxmtMetalFXSpatial
    
    let dxmtPreferredMaxFrameRate = from.dxmtPreferredMaxFrameRate > 20 ? "d3d11.preferredMaxFrameRate=\(DoubleToFormattedStr(from.dxmtPreferredMaxFrameRate));" : ""
    let dxmtMetalSpatialUpscaleFactor = from.dxmtMetalFXSpatial == true ? "d3d11.metalSpatialUpscaleFactor=\(from.dxmtMetalSpatialUpscaleFactor);" : ""
    
    if (from.x87PatchEnabled) {
        if let runtimex87Url = Bundle.main.url(forResource: "runtime_loader", withExtension: nil) {
            value += "ROSETTA_X87_PATH=\"\(runtimex87Url.path())\" "
        } else {
            console.error("Couldn't find runtime_loader")
        }
    }
    
//    if (from.dx9PatchEnabled) {
//        value += "MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1 DXVK_ASYNC=1 WINEDLLOVERRIDES=\"d3d9=n,b;d3d8=n,b\" "
//    }
    
    value += getDxmtConfigEnv(values:  dxmtMetalSpatialUpscaleFactor + dxmtPreferredMaxFrameRate)
    return value
}

func toCrossoverENVString(_ key: String, _ value: String) -> String {
    return "\"\(key)\"=\"\(value)\""
}

func parseCXEnvVarString(_ string: String) -> (String, String){
    // "KEY"="VALUE"
    // e.g.: "CX_BOTTLE_PATH"="/Users/${USER}/CXPBottles"
    let regex = /\"(\w+?)\"\=\"(.+?)\"/
    var key = ""
    var value = ""
    do {
        let match = try regex.firstMatch(in: string)
        key = match?.1.description ?? ""
        value = match?.2.description ?? ""
    } catch {
        console.error("parseCXEnvVarString: \(String(reflecting: error))")
    }
    return (key, value)
}

func getBottleDrives(bottleURL: URL) -> CXDrives {
    let at = bottleURL.appendingPathComponent("dosdevices", isDirectory: true)
    return getDrivesPaths(at: at)
}

func getDrivesPaths(at: URL) -> CXDrives {
    let f = FileManager.default
    do {
        let simLinks = try f.contentsOfDirectory(at: at , includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        let drives = try simLinks.reduce(into: [String: URL]()) { result, link in
            let key = link.lastPathComponent.uppercased()
            let value = try f.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
            if (value.contains("drive_c")) {
                result[key] = at.deletingLastPathComponent().appendingPathComponent("drive_c")
            } else {
                result[key] = URL(filePath: value)
            }
        }
        
        return drives
    } catch {
        console.error("getDrivesPaths failed")
        console.error(String(reflecting: error))
        return [:]
    }
}

func getSetRegCommand (cxAppPath: String, selectedBottle: String, key: String, value: String) -> String {
    let bottleName = URL(string: selectedBottle)?.lastPathComponent ?? ""
    let command = "\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) reg add 'HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\winebus\\' /v '\(key)' /t REG_DWORD /d \(value) /f"
    console.log(command)
    return command
}

func setReg (cxAppPath: String, selectedBottle: String, key: String, value: String) throws -> Void {
    // example: wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\winebus" /v "Enable SDL" /t REG_DWORD /d 1 /f

    try safeShell(getSetRegCommand(cxAppPath: cxAppPath, selectedBottle: selectedBottle, key: key, value: value))
}
