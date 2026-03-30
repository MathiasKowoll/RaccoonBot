//
//  Util.swift
//  Procyon
//
//  Created by Italo Mandara on 26/03/2026.
//
import Foundation

let PATCHED_CX_APPNAME = "Crossover_patched.app"
let PATCHED_CX_X87_APPNAME = "Crossover_patched_x87.app"
private let DEFAULT_CXP_BOTTLES_ROOTPATH = "/Users/${USER}/"
private let DEFAULT_CXP_BOTTLES_FOLDER = "CXPBottles"
private let DEFAULT_CXP_BOTTLES_PATH = DEFAULT_CXP_BOTTLES_ROOTPATH + DEFAULT_CXP_BOTTLES_FOLDER
private let CROSSOVER_MAIN_CONFIGURATION = "/etc/CrossOver.conf"
private let WINE_RESOURCES_ROOT = "Crossover"
private let SHARED_SUPPORT_COMPONENT = "Contents/SharedSupport/CrossOver"
let SHARED_SUPPORT_PATH = "/" + SHARED_SUPPORT_COMPONENT
private let INFO_PLIST_PATH = "Contents/Info.plist"
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
    "/lib/dxvk/i386-windows/d3d10core.dll",
    "/lib/dxvk/i386-windows/d3d11.dll",
    "/lib/dxvk/x86_64-windows/d3d10core.dll",
    "/lib/dxvk/x86_64-windows/d3d11.dll",
]

let WINE_WINEINF_PATH: String = "/share/wine/wine.inf"


let WINE_RESOURCES_PATHS: [String] = [
    //    "/lib64/libinotify.0.dylib",
    //    "/lib64/libinotify.dylib",
    //    "/lib/wine/i386-windows/kernelbase.dll",
    //    "/lib/wine/i386-windows/ntdll.dll",
    //    "/lib/wine/i386-windows/winegstreamer.dll",
    //    "lib/wine/i386-windows/wineboot.exe",
    //    "/lib/wine/i386-windows/winecfg.exe",
    //    "/lib/wine/x86_64-unix/ntdll.so",
    //    "/lib/wine/x86_64-windows/kernelbase.dll",
    //    "/lib/wine/x86_64-windows/ntdll.dll",
    //    "/lib/wine/x86_64-windows/wineboot.exe",
    //    "/lib/wine/x86_64-windows/winecfg.exe",
//        "/share/crossover/bottle_data/crossover.inf",
    //    "/CrossOver-Hosted Application/wineserver",
]
//+ [MOLTENVK_BASELINE]
//+ [WINE_WINEINF_PATH]
//+ WINE_DXVK_RESOURCES_PATHS
//+ WINE_GSTREAMER_RESOURCES_PATHS
//+ WINE_DXMT_RESOURCES_PATHS



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
            try f.copyItem(at: resUrl, to: destUrl)
        } else {
            console.error("Couldn't find \(name)")
        }
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
    var envs: [Env] = [Env(key: "CX_BOTTLE_PATH", value: opts.cxbottlesPath)] // other envs to be added later
//    envs += [Env(key: "NAS_DISABLE_UE4_HACK", value: "1")]
//    if(opts.patchMVK == .legacyUE4) {
//        console.log("add enable UE4 Hack env")
//        envs += [Env(key: "MVK_CONFIG_UE4_HACK_ENABLED", value: "1")]
//    }
//    if(opts.globalEnvs.dxvkAsync == true) {
//        console.log("add DXVK async env")
//        envs += [Env(key: "DXVK_ASYNC", value: "1")]
//    }
//    if(opts.globalEnvs.disableUE4Hack == true) {
//        console.log("add UE4 disable env")
//        envs += [Env(key: "NAS_DISABLE_UE4_HACK", value: "1")]
//    }
    if(opts.globalEnvs.disableMVKArgumentBuffers == true) { // to add the option later
        console.log("disable MoltenVK Argument Buffers")
        envs += [Env(key: "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", value: "0")]
    }
//    console.log("enable MoltenVK UE4 Hack")
//    envs += [Env(key: "MVK_CONFIG_UE4_HACK_ENABLED", value: "1")]
    
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
    try safeShell("codesign --remove-signature \"\(destURL.path())\"")
    let command = "codesign --remove-signature \"\(destURL.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine").path())\""
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
    await makeCrossoverPatchedCopy(sourceCXPath: sourceCXPath, setProgress: { _ in }, setLoading: { _ in }, isX87: true)
}

func fetchLatestRelease(from path: String) async throws -> String {
    let url = URL(string: "\(path)/releases/latest")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    return json["tag_name"] as! String
}


@discardableResult
func makeCrossoverPatchedCopy(sourceCXPath: URL, setProgress: @escaping (Double) -> Void, setLoading: @escaping (Bool) -> Void, isX87: Bool = false) async -> URL {
    let f = FileManager.default
    let name = isX87 ? PATCHED_CX_X87_APPNAME : PATCHED_CX_APPNAME
    let destUrl = f.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).appendingPathComponent(name)
    let resources: [(res: String, dest: URL)] = [
        (res: "ntdll.so", dest: "/lib/wine/x86_64-unix/ntdll.so"),
        (res: "winedmo.so", dest: "/lib/wine/x86_64-unix/winedmo.so"),
        (res: "d9vk/x32/d3d9.dll", dest: "/lib/wine/i386-windows/d3d9.dll"),
        (res: "d9vk/x64/d3d9.dll", dest: "/lib/wine/x86_64-windows/d3d9.dll"),
        (res: "winegstreamer.so", dest: "/lib/wine/x86_64-unix/winegstreamer.so"),
//        (res: "libMoltenVK-experimental.dylib", dest: "/lib64/libMoltenVK.dylib"),
    ].compactMap { item in
        (res: item.res, dest: destUrl.appendingPathComponent(SHARED_SUPPORT_COMPONENT + item.dest))
    }.filter {
        resource in
        isX87 ? true : !resource.res.contains("d3d9")
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
                console.log("Copying \(res) to \(dest.path())")
                try copyResource(name: res, destUrl: dest)
            }
            // MARK: Step 2 download gstreamer
            let gstURL = try await getGstreamerDownloadURL()
            let (url: dxmtURL, versionTag: dxmtVersion) = try await getDXMTDownloadURL()
            console.log("Gstreamer download url: \(gstURL)")
            try await withCheckedThrowingContinuation { continuation in
                let gstreamerDownloader = TarDownloader(
                    fromUrl: gstURL,
                    onProgress: { progress in
                        setProgress(progress)
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
                        setProgress(progress)
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
