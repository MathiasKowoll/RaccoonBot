//
//  Util.swift
//  Procyon
//
//  Created by Italo Mandara on 26/03/2026.
//
import Foundation
import AppKit

let D3DM_CACHE_FOLDER = "d3dm"
let PROCYON_SUPPORT_FOLDER_URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Procyon")
let PATCHED_CX_APPNAME = "Crossover_patched.app"
let PATCHED_CX_X87_APPNAME = "Crossover_patched_x87.app"
private let DEFAULT_CXP_BOTTLES_ROOTPATH = "/Users/${USER}/"
let DEFAULT_CXP_BOTTLES_FOLDER = "CXPBottles"
//private let DEFAULT_CXP_BOTTLES_ROOTPATH = "/Users/${USER}/Application Support/Procyon/"
//private let DEFAULT_CXP_BOTTLES_FOLDER = "Bottles"
//private let DEFAULT_CXP_BOTTLES_PATH = DEFAULT_CXP_BOTTLES_ROOTPATH + DEFAULT_CXP_BOTTLES_FOLDER
private let DEFAULT_CXP_BOTTLES_PATH = PROCYON_SUPPORT_FOLDER_URL.appendingPathComponent(DEFAULT_CXP_BOTTLES_FOLDER).path(percentEncoded: false)
private let CROSSOVER_MAIN_CONFIGURATION = "/etc/CrossOver.conf"
private let WINE_RESOURCES_ROOT = "Crossover"
let SHARED_SUPPORT_COMPONENT = "Contents/SharedSupport/CrossOver"
let SHARED_SUPPORT_PATH = "/" + SHARED_SUPPORT_COMPONENT
private let INFO_PLIST_PATH = "Contents/Info.plist"

let OSVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

struct PathMap {
    var src: String
    var dst: String
}
private struct CXPlist: Decodable {
    private enum CodingKeys: String, CodingKey {
        case CFBundleIdentifier, CFBundleShortVersionString
    }

    let CFBundleIdentifier: String
    let CFBundleShortVersionString: String
}


private let WINE_DXVK_RESOURCES_PATHS: [String] = [
    "dxvk/i386-windows/d3d9.dll",
    "dxvk/i386-windows/d3d10core.dll",
    "dxvk/i386-windows/d3d11.dll",
    "dxvk/x86_64-windows/d3d9.dll",
    "dxvk/x86_64-windows/d3d10core.dll",
    "dxvk/x86_64-windows/d3d11.dll",
]

private let WINE_D3DM_RESOURCES_PATHS: [String] = [
    "external",
    "wine/x86_64-unix/d3d10.so",
    "wine/x86_64-unix/d3d11.so",
    "wine/x86_64-unix/d3d12.so",
    "wine/x86_64-unix/dxgi.so",
    "wine/x86_64-unix/nvapi64.so",
    "wine/x86_64-unix/nvngx-on-metalfx.so",
    "wine/x86_64-windows/d3d10.dll",
    "wine/x86_64-windows/d3d11.dll",
    "wine/x86_64-windows/d3d12.dll",
    "wine/x86_64-windows/dxgi.dll",
    "wine/x86_64-windows/nvapi64.dll",
    "wine/x86_64-windows/nvngx-on-metalfx.dll",
]

private let d3dmRes: [(res: String, dest: String)] = WINE_D3DM_RESOURCES_PATHS.map { path in
    let destPath = path.replacingOccurrences(of: "nvngx-on-metalfx", with: "nvngx")
    return (res: "d3dMetal/" + path, dest: "/\(LIB_ROOT)/apple_gptk/" + destPath)
}

private let dxvkRes: [(res: String, dest: String)] = WINE_DXVK_RESOURCES_PATHS.map { path in
    (res: path, dest: "/lib/" + path)
}

private let allResources = dxvkRes + [
    (res: "wine/x86_64-unix/winegstreamer.so", dest: "/lib/wine/x86_64-unix/winegstreamer.so"),
    (res: "wine/x86_64-unix/ntdll.so", dest: "/lib/wine/x86_64-unix/ntdll.so"),
    (res: "wine/x86_64-unix/winedmo.so", dest: "/lib/wine/x86_64-unix/winedmo.so"),
    (res: "wine/x86_64-unix/win32u.so", dest: "/lib/wine/x86_64-unix/win32u.so"),
    (res: "wine/i386-windows/ntdll.dll", dest: "/lib/wine/i386-windows/ntdll.dll"),
    (res: "wine/x86_64-windows/ntdll.dll", dest: "/lib/wine/x86_64-windows/ntdll.dll"),
    (res: "wine/i386-windows/win32u.dll", dest: "/lib/wine/i386-windows/win32u.dll"),
    (res: "wine/x86_64-windows/win32u.dll", dest: "/lib/wine/x86_64-windows/win32u.dll"),
    (res: "wine/x86_64-windows/winegstreamer.dll", dest: "/lib/wine/x86_64-windows/winegstreamer.dll"),
    (res: "d9vk/x32/d3d9_builtin.dll", dest: "/lib/wine/i386-windows/d3d9.dll"),
    (res: "d9vk/x64/d3d9_builtin.dll", dest: "/lib/wine/x86_64-windows/d3d9.dll"),
]

let WINE_WINEINF_PATH: String = "/share/wine/wine.inf"

enum PatchMVK {
    case legacyUE4
    case latestUE4
    case experimentalUE4
    case none
}

struct GlobalEnvs {
    var fastMathDisabled = false
    var dxvkAsync = true
    var disableUE4Hack = false
    var disableMVKArgumentBuffers = true
}

struct Opts {
    var overrideBottlePath: Bool = true
    var copyGptk = false
    var patchGStreamer = true
    var cxbottlesPath = DEFAULT_CXP_BOTTLES_PATH
    var selectedPrefix: String = ""
    var patchMVK: PatchMVK = PatchMVK.none
    var autoUpdateDisable = true
    var patchDXVK = true
    var globalEnvs = GlobalEnvs()
    var removeSignaure = true
    var xtLibsUrl: URL? = nil
    var copyXtLibs = false
}

private struct Env {
    var key: String
    var value: String
}

private func disable(dest: String) {
    let f = FileManager.default
    if f.fileExists(atPath: dest  + "_disabled") {
        do {
            try f.removeItem(atPath: dest  + "_disabled")
        } catch {
            console.error("can't remove file \(dest + "_disabled")")
        }
    }
    do {
        try f.moveItem(atPath: dest, toPath: dest  + "_disabled")
        console.log("disabling \(dest)")
    } catch {
        console.error("can't move file \(dest)")
    }
}

func copyResource(name: String, destUrl: URL) throws {
    let f = FileManager.default
    if let resUrl = Bundle.main.url(forResource: name, withExtension: nil) {
        if(f.fileExists(atPath: destUrl.path())) {
            let orig = destUrl.appendingPathExtension("orig")
            if(!f.fileExists(atPath: orig.path())) {
                try f.moveItem(at: destUrl, to: orig)
            } else {
                try f.removeItem(at: destUrl)
            }
        } else {
            console.warn("Couldn't find destination \(destUrl.path())")
        }
        try f.copyItem(at: resUrl, to: destUrl)
    } else {
        console.error("Couldn't find source \(name)")
    }
}

func restoreOrig(destUrl: URL) throws {
    let f = FileManager.default
    let orig = destUrl.appendingPathExtension("orig")
    if(f.fileExists(atPath: destUrl.path()) && f.fileExists(atPath: orig.path())) {
        try f.removeItem(at: destUrl)
    } else {
        console.error("Couldn't find destination \(destUrl.path())")
    }
    if(f.fileExists(atPath: orig.path())) {
        try f.moveItem(at: orig, to: destUrl)
    } else {
        console.error("Couldn't find original \(orig.path())")
    }
}

func safeFileCopy(source: URL, dest: URL) throws {
    let f = FileManager.default
    if(f.fileExists(atPath: dest.path())) {
        do {
            try f.moveItem(at: dest, to: dest.appendingPathExtension("orig"))
        } catch {
            console.log(String(reflecting: error))
        }
    } else {
        console.log("file doesn't exist I'll just copy then")
    }

    do {
        try f.copyItem(at: source, to: dest)
        console.log("\(source) copied")
    }
}

private func editInfoPlist(at: URL, key: String, value: String) {
    let f = FileManager.default
    let url = at.appendingPathComponent(INFO_PLIST_PATH)
    var plist: [String:Any] = [:]
    if let data = f.contents(atPath: url.path) {
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options:PropertyListSerialization.ReadOptions(), format:nil) as! [String:Any]
            plist[key] = value
            console.log("set info property list \(key) = \(value)")
        } catch {
            console.error("there was a problem parsing the xml")
            console.error(String(reflecting: error))
        }
    }
    disable(dest: url.path(percentEncoded: false))
    NSDictionary(dictionary: plist).write(to: url, atomically: true)
}

func disableAutoUpdate(url: URL) {
    editInfoPlist(at: url, key: "SUFeedURL", value: "")
}

private func appendLinesToFile(fileURL: URL, additionalLines: [String]) -> String {
    console.log("trying to read \(fileURL.debugDescription)")
    do { let text = try String(contentsOf: fileURL, encoding: .utf8)
        var finalLines: String = ""
        console.log("total envs: \(additionalLines.count)")
        for additionalLine in additionalLines {
            finalLines += additionalLine + "\n"
            console.log(additionalLine)
        }
        return text + finalLines
    } catch {
        console.error("failed opening config file")
        console.error(String(reflecting: error))
    }
    return ""
}

private func getENVOverrideConfigfile(envs: [Env], fileURL: URL) -> String {
    let additionallines: [String] = ["[EnvironmentVariables]"] + envs.map { env in
        toCrossoverENVString(env.key, env.value)
    }
    
    return appendLinesToFile(fileURL: fileURL, additionalLines: additionallines)
}

private func addEnvs(_ envs: [Env], to: URL, from: URL) {
    let file = getENVOverrideConfigfile(envs: envs, fileURL: from)
    do {
        try file.write(to: to, atomically: false, encoding: .utf8)
        console.log("added: \(envs) in \(to.path)")
    } catch {
        console.error("There was an error writing the envs to the file \(to.path)")
        console.error(String(reflecting: error))
    }
}

func addGlobals(appURL: URL, opts: Opts) {
    disable(dest: appURL.path + SHARED_SUPPORT_PATH + CROSSOVER_MAIN_CONFIGURATION)
    let envs: [Env] = [Env(key: "CX_BOTTLE_PATH", value: opts.cxbottlesPath)] // other envs to be added later
    
    addEnvs(envs, to: appURL.appendingPathComponent(SHARED_SUPPORT_PATH + CROSSOVER_MAIN_CONFIGURATION), from: appURL.appendingPathComponent(SHARED_SUPPORT_PATH + CROSSOVER_MAIN_CONFIGURATION + "_disabled"))
}

func fixup(destPath: String) throws {
    try safeShell("/usr/bin/xattr -cr \"\(destPath)\"")
}

func signAndFixup(destPath: String) throws {
    try safeShell("/usr/bin/codesign --force --deep --sign - \"\(destPath)\"")
    try fixup(destPath: destPath)
}

func removeSignature(destURL: URL) throws {
    try safeShell("/usr/bin/codesign --remove-signature \"\(destURL.path())\"")
    let command = "/usr/bin/codesign --remove-signature \"\(destURL.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine").path())\""
    try safeShell(command)
}

private func parseCXPlist(plistPath: String) -> CXPlist {
    let data = try! Data(contentsOf: URL(filePath: plistPath))
    let decoder = PropertyListDecoder()
    return try! decoder.decode(CXPlist.self, from: data)
}

private func markAsPatched(url: URL) {
    let plist = parseCXPlist(plistPath: url.path + "/Contents/Info.plist")
    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
        editInfoPlist(at: url, key: "CFBundleShortVersionString", value: plist.CFBundleShortVersionString + "p" + version)
    }
}

func makeX87CrossoverPatchedCopy (sourceCXPath: URL, patchedApp: URL) async -> Void {
    await makeCrossoverPatchedCopy(sourceCXPath: sourceCXPath, setProgress: { _, _ in }, setLoading: { _ in }, isX87: true)
}

func fetchLatestRelease(from path: String) async throws -> String {
    let url = URL(string: "\(path)/releases/latest")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    return json["tag_name"] as! String
}

func installd3dMetal(at: URL, version: String) throws -> Void {
    let d3dmRes: [(res: String, dest: String)] = WINE_D3DM_RESOURCES_PATHS.map { path in
        let destPath = path.replacingOccurrences(of: "nvngx-on-metalfx", with: "nvngx")
        return (res: "d3dMetal\(version)/" + path, dest: "/\(LIB_ROOT)/apple_gptk/" + destPath)
    }
    
    let resources = d3dmRes
        .map { item in
            (res: item.res, dest: at.appendingPathComponent(SHARED_SUPPORT_COMPONENT).appendingPathComponent(item.dest))
        }
    
    for (res, dest) in resources {
        console.log("Copying \(res) to \(dest.path())")
        try copyResource(name: res, destUrl: dest)
    }
}

func activateApp(_ gameName: String) -> Void {
    //do nothing
    let app = NSWorkspace().runningApplications.first(where: { gameName.contains($0.localizedName ?? "none")})
    console.log("attempting to put your game in the foreground")
    console.log(app?.executableURL?.lastPathComponent ?? app?.localizedName ?? "couldn't get app")
    app?.activate()
}

@discardableResult
func makeCrossoverPatchedCopy(sourceCXPath: URL, setProgress: @escaping (Double, String) -> Void, setLoading: @escaping (Bool) -> Void, isX87: Bool = false) async -> URL {
    let f = FileManager.default
    let name = isX87 ? PATCHED_CX_X87_APPNAME : PATCHED_CX_APPNAME
    let destUrl = f.homeDirectoryForCurrentUser.appendingPathComponent("Applications").appendingPathComponent(name)
    let resources = allResources
        .map { item in
            (res: item.res, dest: destUrl.appendingPathComponent(SHARED_SUPPORT_COMPONENT + item.dest))
        }
    do {
        // Make sure destination app doesn't exist and if it does, delete it
        if (f.fileExists(atPath: destUrl.path())) {
            try f.removeItem(at: destUrl)
        }
        // MARK: Step 1 copy the app in the user's application folder
        try f.copyItem(at: sourceCXPath, to: destUrl)
        
        if(f.fileExists(atPath: destUrl.path())) {
            // MARK: Step 1 copy resources
            for (res, dest) in resources {
                if(isX87) {
                    console.log("Copying \(res) to \(dest.path())")
                    try copyResource(name: res, destUrl: dest)
                } else if (!res.contains(/ntdll|d3d9|win32u/)){
                    console.log("Copying \(res) to \(dest.path())")
                    try copyResource(name: res, destUrl: dest)
                }
            }
            // MARK: Step 2 download gstreamer
            let gstURL = try await getGstreamerDownloadURL()
            let (url: dxmtURL, versionTag: dxmtVersion) = try await getDXMTDownloadURL()
            console.log("Gstreamer download url: \(gstURL)")
            try await withCheckedThrowingContinuation { continuation in
                let gstreamerDownloader = TarDownloader(
                    fromUrl: gstURL,
                    onProgress: { progress in
                        setProgress(progress, "Downloading GStreamer")
                    },
                    onComplete: { srcUrl in
                        do {
                            try installGstreamer(srcUrl: srcUrl, destUrl: destUrl )
                            continuation.resume()
                        } catch {
                            console.error(String(reflecting: error))
                            continuation.resume(throwing: error)
                        }
                        setLoading(false)
                    },
                    onError: { error in
                        console.error("Error while downloading GStreamer")
                        setProgress(0, "Error while downloading GStreamer")
                        console.error(String(reflecting: error))
                        continuation.resume(throwing: error)
                    }
                )
                setLoading(true)
                gstreamerDownloader.download()
            }
            try await withCheckedThrowingContinuation { continuation in
                let dxmtDownloader = TarDownloader(
                    fromUrl: dxmtURL,
                    onProgress: { progress in
                        setProgress(progress, "Downloading DXMT")
                    },
                    onComplete: { srcURL in
                        do {
                            try installDXMT(srcURL: srcURL, destUrl: destUrl, versionTag: dxmtVersion)
                            continuation.resume()
                        } catch {
                            console.error(String(reflecting: error))
                            continuation.resume(throwing: error)
                        }
                        setLoading(false)
                    },
                    onError: { error in
                        console.error("Error while downloading DXMT")
                        setProgress(0, "Error while downloading DXMT")
                        console.error(String(reflecting: error))
                        continuation.resume(throwing: error)
                    }
                )
                setLoading(true)
                dxmtDownloader.download()
            }
            let opts = Opts()
            // MARK: Step 3 add env variables to crossover configuration
            addGlobals(appURL: destUrl, opts: opts)
            // MARK: Step 4 disable auto update
            if(opts.autoUpdateDisable) {
                disableAutoUpdate(url: destUrl)
            }
            markAsPatched(url: destUrl)
            // MARK: Step 5 sign
            // MARK: Step 6 fix app after patching
            if !isX87 {
                try signAndFixup(destPath: destUrl.path())
            } else {
                try removeSignature(destURL: destUrl)
            }
        } else {
            console.error("Couldn't find Crossover app in \(destUrl.path())")
        }
    } catch {
        console.error(String(reflecting: error))
    }
    return destUrl
}

func darwinUserCacheDir() -> URL? {
    var buf = [CChar](repeating: 0, count: 1024)
    let success = confstr(_CS_DARWIN_USER_CACHE_DIR, &buf, buf.count) >= 0
    guard success else { return nil }
    return URL(fileURLWithFileSystemRepresentation: &buf, isDirectory: true, relativeTo: nil)
}

enum DeleteStatus {
    case failed
    case success
    case idle
    case progress
}

func removeD3DMetalCaches() -> DeleteStatus {
    let f = FileManager.default
    do {
        let d3dmPath = darwinUserCacheDir()!.appendingPathComponent(D3DM_CACHE_FOLDER, isDirectory: true).path

        let _items = try f.contentsOfDirectory(atPath: d3dmPath)
        let items = try _items.filter { d3dmPath in
                let pattern = try Regex(#"^.*\.exe$"#)
                return d3dmPath.contains(pattern)
        }
        for itemPath in items {
            console.log("Deleting \(itemPath)")
            try f.removeItem(atPath: d3dmPath + "/"  + itemPath)
        }
    } catch {
        console.log(error.localizedDescription)
        return DeleteStatus.failed
    }

    return DeleteStatus.success
}
