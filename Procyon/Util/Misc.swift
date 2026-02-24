//
//  Util.swift
//  Procyon
//
//  Created by Italo Mandara on 03/02/2026.
//

import UniformTypeIdentifiers
import Combine

let blacklist: [String] = ["228980"]

func addSteamFolderPaths(_ url: URL) {
    do {
        if (try getIDsFromFolder(dest: url).isEmpty) {
            console.warn("Folder is empty")
            return
        }
    } catch {
        console.warn("Failed to validate steam folder")
        console.error(error.localizedDescription)
    }
    do {
        try persistFolderAccess(url: url)
    } catch {
        console.error("Failed to save steam folder")
        console.error(error.localizedDescription)
    }
}

func removeSteamFolderPath(_ path: String) {
    let url = URL(string: path)!
    removePersistedFolderAccess(url: url)
}

func getSteamFolderPaths() -> [String] {
    return resolvePersistedFolders().map { $0.absoluteString }
}

func extractAppIDRegex(from filename: String) -> String? {
    let pattern = #"^appmanifest_(\d+)\.acf$"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
    guard let match = regex?.firstMatch(in: filename, options: [], range: range),
          match.numberOfRanges == 2,
          let idRange = Range(match.range(at: 1), in: filename) else { return nil }
    return String(filename[idRange])
}

func extractFolderNameRegex(_ path: String) -> String {
    let pattern = #"^file:\/\/\/Volumes\/(.+)\/steamapps\/$"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let decodedpath = path.removingPercentEncoding ?? path
    let range = NSRange(decodedpath.startIndex..<decodedpath.endIndex, in: decodedpath)
    guard let match = regex?.firstMatch(in: decodedpath, options: [], range: range),
          match.numberOfRanges == 2,
          let idRange = Range(match.range(at: 1), in: decodedpath) else { return decodedpath }
    return String(decodedpath[idRange])
}

//let id = extractAppIDRegex(from: "appmanifest_8870.acf") // "8870"

func getIDsFromFolder(dest: URL) throws -> [String] {
    /**
     scans a folder and returns an array of steam games ids
     */
    try withSecurityScope(for: dest) {
        let f = FileManager.default
        let urls = try f.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])
        return urls
            .filter { $0.pathExtension == "acf" }
            .map {
                extractAppIDRegex(from: $0.lastPathComponent)!
            }
            .filter { !blacklist.contains($0) }
    } ?? []
}

func getIsNative(fromURL: URL) -> Bool {
    if folderContainsFile(withExtension: "exe", at: fromURL) {
        return false
    }
    return true
}

func getCXDefaultBottlesURL() -> URL {
    let appID = "com.codeweavers.CrossOver" as CFString
    let key = "BottleDir" as CFString
    let bottlesPath = CFPreferencesCopyAppValue(key, appID)

    return URL(filePath: bottlesPath as! String)
}

func isCXPatched(appDir: URL) -> Bool {
    let f = FileManager.default
    return f.fileExists(atPath: appDir.appendingPathComponent("Contents/cxplog.txt").path)
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
//    let DEFAULT_BOTTLE_PATH = "Library/Application Support/CrossOver/Bottles/"
    let f = FileManager.default
    
    let bottlePath = getCXDefaultBottlesURL()
    
    console.warn(bottlePath.absoluteString)
    do {
        let bottlePathForCXP = try getCXPatcherBottlesURL(appDir: appDir)
        var subfolders: [URL] = try f.contentsOfDirectory(at: bottlePath, includingPropertiesForKeys: [.isDirectoryKey], options: [])
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
            subfolders = try f.contentsOfDirectory(at: bottlePath, includingPropertiesForKeys: [.isDirectoryKey], options: [])
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

@discardableResult
func safeShell(_ command: String) throws -> String {
    let task = Process()
    let pipe = Pipe()
    
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.standardInput = nil

    try task.run()
    
//    let data = pipe.fileHandleForReading.readDataToEndOfFile()
//    let output = String(data: data, encoding: .utf8)!
//    console.warn(output)
//    return output
    return "OK"
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

func getSteamLibraryFolders(from: URL) -> [URL] {
    let drives = getBottleDrives(bottleURL: from)
    let steamSettingsPath = from.appendingPathComponent("/drive_c/Program Files (x86)/Steam/config/libraryfolders.vdf")
    do {
        let steamSettingsFile = try String(contentsOfFile: steamSettingsPath.path, encoding: .utf8)
        let parsed = parseVDFToDict(from: steamSettingsFile)
        print(parsed.description)
    } catch {
        console.error(error.localizedDescription)
    }
    return []
}
