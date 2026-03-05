//
//  Util.swift
//  Procyon
//
//  Created by Italo Mandara on 03/02/2026.
//

import UniformTypeIdentifiers
import Combine

let DEFAULT_BOTTLE_PATH = "Library/Application Support/CrossOver/Bottles/"
let debugEnabled: Bool = {
    let env = ProcessInfo.processInfo.environment["PROCYON_DEBUG"]?.lowercased()
    switch env {
    case "1", "true", "yes":
        return true
    case "0", "false", "no":
        return false
    default:
        return false
    }
}()
let useLogger: Bool = false

func addSteamFolderPaths(_ url: URL) {
    do {
        if (try getIDsFromFolder(dest: url).isEmpty) {
            console.warn("\(url) Folder is empty")
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
            .filter { $0.pathExtension == "acf"}
            .map {
                extractAppIDRegex(from: $0.lastPathComponent) ?? "0"
            }
//            .filter { !blacklist.contains($0) }
    } ?? []
}

func getIsNative(fromURL: URL) -> Bool {
    if folderContainsFile(withExtension: "exe", at: fromURL) {
        return false
    }
    return true
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

let DEFAULT_STEAM_MAC_PATH = "/Library/Application Support/Steam/config/"
let DEFAULT_STEAM_WINE_PATH = "/drive_c/Program Files (x86)/Steam/config/"

func getSteamUserID (usingBottlePath: URL) -> String? {
    let steamLoginUsersPath = usingBottlePath.appendingPathComponent(DEFAULT_STEAM_WINE_PATH)
        .appendingPathComponent("loginusers.vdf")
    guard let steamSettingsFile = try? String(contentsOfFile: steamLoginUsersPath.path(percentEncoded: false), encoding: .utf8) else { return nil }
    let parsed = parseVDFToDict(from: steamSettingsFile)
    let users = parsed["users"] as? [String: Any]
    return users?.keys.first?.description
}

func getSteamLibraryFolders(from: URL) -> [URL] {
    let f = FileManager.default
    var steamLibraries: [URL] = []
    let drives = getBottleDrives(bottleURL: from)
    console.log("drives: \(String(describing: drives))")
    let steamSettingsPaths = [
        from.appendingPathComponent(DEFAULT_STEAM_WINE_PATH)
            .appendingPathComponent("libraryfolders.vdf"),
        f.homeDirectoryForCurrentUser
            .appendingPathComponent(DEFAULT_STEAM_MAC_PATH)
            .appendingPathComponent("libraryfolders.vdf")
    ].filter{ f.fileExists(atPath: $0.path(percentEncoded: false)) }
    for steamSettingsPath in steamSettingsPaths {
        do {
            let steamSettingsFile = try String(contentsOfFile: steamSettingsPath.path(percentEncoded: false), encoding: .utf8)
            let parsed = parseVDFToDict(from: steamSettingsFile)
            if let libraries = parsed["libraryfolders"] as? [String: Any] {
                for (_, value) in libraries {
                    if let val = (value as? [String: Any]) {
                        if let path = val["path"] as? String{
                            let driveAlias = String(path.split(separator: ":/")[0]) + ":"
                            let splitPath = path.split(separator: ":")
                            if (splitPath.count > 1){
                                let partial = splitPath[1].replacingOccurrences(of: "//", with: "/")
                                if let newPath = drives[driveAlias]?.appendingPathComponent(partial).appendingPathComponent("/steamapps") {
                                    steamLibraries.append(newPath)
                                } else {
                                    console.log("couldn't find mac Steam config")
                                }
                            } else {
                                let macNewPath = URL(fileURLWithPath: path).appendingPathComponent("/steamapps")
                                steamLibraries.append(macNewPath)
                            }
                        }
                    }
                }
            }
        } catch {
            console.error(error.localizedDescription)
            return []
        }
    }
    console.log("all steam libraries \(steamLibraries.debugDescription)")
    return steamLibraries
}

func validateAddSteamFolder(_ url: URL, to folders: inout [String]) {
    if folders.contains(url.absoluteString) {
        console.log("\(url.absoluteString) folder exists!")
        return
    }
    addSteamFolderPaths(url)
    folders.append(url.absoluteString)
}

func mapPersonaState(_ state: Int) -> String {
    let states = ["Offline", "Online", "Busy", "Away", "Snooze", "looking to trade", "looking to play"]
    if (0..<states.count).contains(state){
        return states[state]
    }
    return "Unknown"
}

func getAppNames(isNative: Bool, gameURL: URL?) -> [String] {
    let ext = isNative ? "app" : "exe"
    let f = FileManager.default
    var results: [String] = []
    if(gameURL == nil) {
        return []
    }
    guard let enumerator = f.enumerator(at: gameURL!, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
        return []
    }
    for case let fileURL as URL in enumerator  {
        if(fileURL.pathExtension == ext) {
            results.append(fileURL.lastPathComponent)
        }
    }
    return results
}

func getGameTracker(appNames: [String], cxAppPath: String, bottleName: String, onLoad: @escaping () -> Void, onTerminate: @escaping () -> Void) async throws -> TerminationObserver {
    let tOb = TerminationObserver(then: { output in
        let terminatedAppName = output.userInfo?[AnyHashable("NSApplicationName")] as? String ?? "unknown"
        if (appNames.contains(terminatedAppName)) {
            Task {
                try await quitSteam(cxAppPath: cxAppPath, bottleName: bottleName)
                try await closeWineActivities()
                onTerminate()
            }
        }
    })
    try await trackPlaying(apps: appNames, then: {
        onLoad()
    })
    return tOb
}

    
