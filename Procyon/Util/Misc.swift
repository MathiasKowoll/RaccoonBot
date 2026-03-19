//
//  Util.swift
//  Procyon
//
//  Created by Italo Mandara on 03/02/2026.
//

import UniformTypeIdentifiers
import Combine

let DEFAULT_BOTTLE_PATH = "Library/Application Support/CrossOver/Bottles/"
let BLACKLIST = [
    "228980", // Steamworks
]
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

func prettyPrinted(dict: Dictionary<String, Any>) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
       let str = String(data: data, encoding: .utf8) {
        return str
    }
    return "{}"
}

func addSteamFolderPaths(_ url: URL) {
    do {
        if (try getIDsFromFolder(dest: url).isEmpty) {
            console.warn("\(url) Folder is empty")
            return
        }
    } catch {
        console.warn("Failed to validate steam folder")
        console.error(String(reflecting: error))
    }
    do {
        try persistFolderAccess(url: url)
    } catch {
        console.error("Failed to save steam folder")
        console.error(String(reflecting: error))
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
            .filter { !BLACKLIST.contains($0) }
    } ?? []
}

func getIsNative(fromURL: URL) -> Bool {
    if !folderContainsFile(withExtension: "exe", at: fromURL) && folderContainsFile(withExtension: "app", at: fromURL) {
        return true
    }
    return false
}

func safeShell(_ command: String) throws {
    let task = Process()
    
    task.standardInput = FileHandle.nullDevice
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")

    try task.run()
}

func safeShellWithOutput(_ command: String) throws -> String {
    let task = Process()
    let pipe = Pipe()
    
    task.standardInput = nil
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")

    try task.run()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!
    console.warn(output)
    return output
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

func getSteamUserDataFallback (usingBottlePath: URL) -> UserInfo? {
    let steamLoginUsersPath = usingBottlePath.appendingPathComponent(DEFAULT_STEAM_WINE_PATH)
        .appendingPathComponent("loginusers.vdf")
    guard let steamSettingsFile = try? String(contentsOfFile: steamLoginUsersPath.path(percentEncoded: false), encoding: .utf8) else { return nil }
    let parsed = parseVDFToDict(from: steamSettingsFile)
    let users = parsed["users"] as? [String: Any]
    if let key = users?.keys.first {
        let user = users![key] as? [String: Any]
        let personaName = user?["PersonaName"] as? String ?? ""
        let avatar = usingBottlePath.appendingPathComponent("/drive_c/Program Files (x86)/Steam/config/avatarcache/").appendingPathComponent(key).appendingPathExtension("png").absoluteString
        let fallbackProfileData = UserInfo(
            steamID: "",
            communityVisibilityState: 0,
            profileState: 0,
            personaName: personaName,
            profileURL: "",
            avatar: avatar,
            avatarMedium: avatar,
            avatarFull: avatar,
            avatarHash: "",
            lastLogOff: 0,
            personaState: 0,
            primaryClanID: "",
            timeCreated: 0,
            personaStateFlags: 0,
            locCountryCode: nil,
            locStateCode: nil
        )
        return fallbackProfileData
    }
    return nil
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
                for (_, value) in libraries { // Refactor this mess
                    if let val = (value as? [String: Any]) {
                        if let path = val["path"] as? String{
                            let driveAlias = String(path.split(separator: ":\\")[0]) + ":"
                            let splitPath = path.split(separator: ":")
                            if (splitPath.count > 1){
                                let partial = splitPath[1].replacingOccurrences(of: "\\\\", with: "/")
                                if let newPath = drives[driveAlias]?.appendingPathComponent(partial).appendingPathComponent("/steamapps") {
                                    steamLibraries.append(newPath)
                                } else {
                                    console.log("couldn't find Windows Steam config")
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
            console.error(String(reflecting: error))
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

func getGameTracker(appNames: [String], cxAppPath: String, bottleName: String, onLoad: @escaping () -> Void, onTerminate: @escaping () -> Void, isNative: Bool) async throws -> TerminationObserver {
    let tOb = TerminationObserver(then: { output in
        console.log(output.userInfo?.description ?? "no userInfo")
        let terminatedAppProcessName = output.userInfo?[AnyHashable("NSApplicationName")] as? String ?? "unknown"
        let terminatedAppPath = output.userInfo?[AnyHashable("NSApplicationPath")] as? String ?? "unknown"
        let terminatedAppName = String(terminatedAppPath.split(separator: "/").last ?? "unknown")
        if (appNames.contains(terminatedAppName) || appNames.contains(terminatedAppProcessName)) {
            console.log("\(appNames) -> \(terminatedAppName) or \(terminatedAppProcessName) has been terminated, closing steam...")
            Task {
                try await quitSteam(cxAppPath: cxAppPath, bottleName: bottleName, isNative: isNative)
                if (!isNative) {
                    try await closeWineActivities()
                }
                onTerminate()
                console.log("onTerminate() was called")
            }
        }
    })
    try await trackPlaying(apps: appNames, then: {
        console.log("found game \(appNames.joined(separator: ", ")), loading...")
        onLoad()
    }, onTimeout: {
        console.log("\(appNames.joined(separator: ", ")), timeout...")
        onTerminate()
    }, isNative: isNative)
    return tOb
}

func makeX87CrossoverPatchedCopy (sourceCXPath: URL) -> Void {
    let f = FileManager.default
    do {
        let destUrl = f.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).appendingPathComponent("Crossover_x87.app")
        // Make sure destination app doesn't exist and if it does, delete it
        if (f.fileExists(atPath: destUrl.path())) {
            try f.removeItem(at: destUrl)
        }
        // Step 1 copy the app in the user's application folder
        
        try f.copyItem(at: sourceCXPath, to: destUrl)
        
        if(f.fileExists(atPath: destUrl.path())) {
            // Step 2 unsign app
            try safeShell("codesign --remove-signature \"\(destUrl.path())\"")
            try safeShell("codesign --remove-signature \"\(destUrl.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine").path())\"")
            
            // Step 3 copy ntdll.so to CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/ntdll.so
            if let ntdllUrl = Bundle.main.url(forResource: "ntdll", withExtension: "so") {
                let ntdllDest = destUrl.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/ntdll.so")
                if(f.fileExists(atPath: ntdllDest.path())) {
                    try f.removeItem(at: ntdllDest)
                }
                try f.copyItem(at: ntdllUrl, to: ntdllDest)
            } else {
                console.error("Couldn't find ntdll.so")
            }
            
            // Step 4 fix app after patching
            try safeShell("xattr -cr \"\(destUrl.path())\"")
        } else {
            console.error("Couldn't find Crossover_x87.app in \(destUrl.path())")
        }
    } catch {
        console.error(String(reflecting: error))
    }
}

func isSameFile(_ file1URL: URL, _ file2URL: URL) -> Bool {
    let f = FileManager.default
    do {
        let attrs1 = try f.attributesOfItem(atPath: file1URL.path())
        let attrs2 = try f.attributesOfItem(atPath: file2URL.path())
        let sameSize = attrs1[.size] as? Int == attrs2[.size] as? Int
        let sameDate = attrs1[.modificationDate] as? Date == attrs2[.modificationDate] as? Date
        if(sameSize && sameDate) {
            // just comparing attributes for now
            return true
        }
    } catch {
        console.error("couldn't get file attributes")
        console.error(String(reflecting: error))
        return false
    }
    return false
}

func getSystemWOW64URL(from: URL) -> URL {
    return from
        .appending(path: "drive_c")
        .appending(path: "windows")
        .appending(path: "syswow64")
}

func cpyd8d9DLLs(to: URL) throws -> Void {
    let f = FileManager.default
    let files = ["d3d9.dll", "d3d8.dll"]
    for file in files {
        if let dllsUrl = Bundle.main.url(forResource: "dlls", withExtension: nil) {
            let dllPath = dllsUrl.appendingPathComponent(file)
            let dllDest = to.appendingPathComponent(file)
            if(f.fileExists(atPath: dllDest.path())) {
                console.log("\(file) exists")
                if(!isSameFile(dllPath, dllDest)){
                    try f.moveItem(at: dllDest, to: dllDest.appendingPathExtension(".old"))
                    try f.copyItem(at: dllPath, to: dllDest)
                } else {
                    console.log("already patched with the latest dx9 skipping copy")
                }
            }
            
        } else {
            console.log("Couldn't find \(file)")
        }
    }
}
