//
//  Util.swift
//  Procyon
//
//  Created by Italo Mandara on 03/02/2026.
//

import UniformTypeIdentifiers
import Combine

let blacklist: [String] = ["228980"]
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



func getSteamLibraryFolders(from: URL) -> [URL] {
    let drives = getBottleDrives(bottleURL: from)
    console.log("drives: \(String(describing: drives))")
    let steamSettingsPath = from.appendingPathComponent("/drive_c/Program Files (x86)/Steam/config/libraryfolders.vdf")
    do {
        var steamLibraries: [URL] = []
        let steamSettingsFile = try String(contentsOfFile: steamSettingsPath.path, encoding: .utf8)
        let parsed = parseVDFToDict(from: steamSettingsFile)
        if let libraries = parsed["libraryfolders"] as? [String: Any] {
            for (key, value) in libraries {
                if let val = (value as? [String: Any]) {
                    if let path = val["path"] as? String{
                        print("Key: \(key), Value: \(path)")
                        let driveAlias = String(path.split(separator: ":/")[0]) + ":"
                        let partial = path.split(separator: ":")[1].replacingOccurrences(of: "//", with: "/")
                        if let newPath = drives[driveAlias]?.appendingPathComponent(partial).appendingPathComponent("/steamapps") {
                            print("newPath \(newPath)")
                            steamLibraries.append(newPath)
                        }
                    }
                }
            }
        }
        return steamLibraries
    } catch {
        console.error(error.localizedDescription)
    }
    return []
}
