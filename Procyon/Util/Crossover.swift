//
//  Crossover.swift
//  Procyon
//
//  Created by Italo Mandara on 26/02/2026.
//

internal import Foundation

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
        let bottlePath = getCXDefaultBottlesURL()
        console.warn(bottlePath.absoluteString)
        let bottlePathForCXP = try getCXPatcherBottlesURL(appDir: appDir)
        var subfolders: [URL] = try f.contentsOfDirectory(at: bottlePath, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants])
        if(isCXPatched(appDir: appDir)) {
            console.log("app is patched with CXPatcher")
            do {
                subfolders = try f.contentsOfDirectory(at: bottlePathForCXP, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            } catch {
                console.error(error.localizedDescription)
                console.error("couldn't find the CXPatched bottles")
            }
        } else {
            console.log("app is normal crossover")
            do {
                subfolders = try f.contentsOfDirectory(at: bottlePath, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants])
            } catch {
                console.error(error.localizedDescription)
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
        console.error(error.localizedDescription)
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
    let bottleURL = getCXBottleConfigFileURL(selectedBottle: selectedBottle)
    let original = try String(contentsOf: bottleURL!, encoding: .utf8)
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
    try updated.write(to: bottleURL!, atomically: true, encoding: .utf8)
}

func getInlineEnvs(from: GameOptions) -> String {
    func onOff(_ value: Bool?) -> String {
        return value != nil && value == true ? "1" : "0"
    }
    var value = "\(from.envVariables) "
    let defaults = "WINEDEBUG=-all "
    func getDxmtConfigEnv(values: String) -> String {
        return "DXMT_CONFIG=\"\(values)\""
    }
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
    value += getDxmtConfigEnv(values:  dxmtMetalSpatialUpscaleFactor + dxmtPreferredMaxFrameRate)
    return value
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
            let value = try f.destinationOfSymbolicLink(atPath: link.path)
            result[key] = URL(filePath: value)
        }
        
        return drives
    } catch {
        console.error("getDrivesPaths failed")
        console.error(error.localizedDescription)
        return [:]
    }
}
