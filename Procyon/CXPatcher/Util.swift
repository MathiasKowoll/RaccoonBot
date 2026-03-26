//
//  Util.swift
//  Procyon
//
//  Created by Italo Mandara on 26/03/2026.
//
import Foundation

private let DEFAULT_CXP_BOTTLES_ROOTPATH = "/Users/${USER}/"
private let DEFAULT_CXP_BOTTLES_FOLDER = "CXPBottles"
private let DEFAULT_CXP_BOTTLES_PATH = DEFAULT_CXP_BOTTLES_ROOTPATH + DEFAULT_CXP_BOTTLES_FOLDER
private let CROSSOVER_MAIN_CONFIGURATION = "/etc/CrossOver.conf"
private let WINE_RESOURCES_ROOT = "Crossover"
private let SHARED_SUPPORT_COMPONENT = "Contents/SharedSupport/CrossOver"
private let SHARED_SUPPORT_PATH = "/" + SHARED_SUPPORT_COMPONENT
private let INFO_PLIST_PATH = "Contents/Info.plist"

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
    do {try f.moveItem(atPath: dest, toPath: dest  + "_disabled")
        console.log("disabling \(dest)")
    } catch {
        console.error("can't move file \(dest)")
    }
}

func copyResource(name: String, destUrl: URL) throws {
    let f = FileManager.default
    if let resUrl = Bundle.main.url(forResource: name, withExtension: nil) {
        if(f.fileExists(atPath: destUrl.path())) {
            try f.removeItem(at: destUrl)
        }
        try f.copyItem(at: resUrl, to: destUrl)
    } else {
        console.error("Couldn't find \(name)")
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
    let additionallines: [String] = envs.map { env in
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
    var envs: [Env] = [Env(key: "CX_BOTTLE_PATH", value: opts.cxbottlesPath)]
    if(opts.patchMVK == .legacyUE4) {
        console.log("add enable UE4 Hack env")
        envs += [Env(key: "MVK_CONFIG_UE4_HACK_ENABLED", value: "1")]
    }
    if(opts.globalEnvs.dxvkAsync == true) {
        console.log("add DXVK async env")
        envs += [Env(key: "DXVK_ASYNC", value: "1")]
    }
    if(opts.globalEnvs.disableUE4Hack == true) {
        console.log("add UE4 disable env")
        envs += [Env(key: "NAS_DISABLE_UE4_HACK", value: "1")]
    }
    if(opts.globalEnvs.disableMVKArgumentBuffers == true) { // to add the option later
        console.log("disable MoltenVK Argument Buffers")
        envs += [Env(key: "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", value: "0")]
    }
    console.log("enable MoltenVK UE4 HAck")
    envs += [Env(key: "MVK_CONFIG_UE4_HACK_ENABLED", value: "1")]
    
    addEnvs(envs, to: appURL.appendingPathComponent(SHARED_SUPPORT_PATH + CROSSOVER_MAIN_CONFIGURATION), from: appURL.appendingPathComponent(SHARED_SUPPORT_PATH + CROSSOVER_MAIN_CONFIGURATION + "_disabled"))
}

func fixup(destPath: String) throws {
    try safeShell("/usr/bin/xattr -cr \"\(destPath)\"")
}

func signAndFixup(destPath: String) throws {
    try safeShell("/usr/bin/codesign --force --deep --sign - \"\(destPath)\"")
    try fixup(destPath: destPath)
}

func makeX87CrossoverPatchedCopy (sourceCXPath: URL, patchedApp: URL) -> Void {
    let f = FileManager.default
    do {
        let destUrl = f.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).appendingPathComponent("Crossover_x87.app")
        // Make sure destination app doesn't exist and if it does, delete it
        if (f.fileExists(atPath: destUrl.path())) {
            try f.removeItem(at: destUrl)
        }
        // MARK: Step 1 copy the app in the user's application folder
        try f.copyItem(at: sourceCXPath, to: destUrl)
        
        // MARK: Step 2 remove signature
        if(f.fileExists(atPath: destUrl.path())) {
            // Step 2 unsign app
            try safeShell("codesign --remove-signature \"\(destUrl.path())\"")
            try safeShell("codesign --remove-signature \"\(destUrl.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine").path())\"")
            
            // MARK: Step 3 fix app after patching
            try fixup(destPath: destUrl.path())
        } else {
            console.error("Couldn't find Crossover_x87.app in \(destUrl.path())")
        }
    } catch {
        console.error(String(reflecting: error))
    }
}



func makeCrossoverPatchedCopy (sourceCXPath: URL, setProgress: @escaping (Double) -> Void, setLoading: @escaping (Bool) -> Void) async -> URL {
    let f = FileManager.default
    let name = "Crossover_patched.app"
    let ROOT = "Contents/SharedSupport/"
    let destUrl = f.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).appendingPathComponent(name)
    let resources: [(res: String, dest: URL)] = [
        (res: "ntdll.so", dest: "CrossOver/lib/wine/x86_64-unix/"),
        (res: "winedmo.so", dest: "CrossOver/lib/wine/x86_64-unix/"),
        (res: "winegstreamer.so", dest: "CrossOver/lib/wine/x86_64-unix/"),
    ].map { item in
        (res: item.res, dest: destUrl.appendingPathComponent(ROOT + item.dest + item.res))
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
            for (res, dest) in resources{
                console.log("Copying \(res) to \(dest.path())")
                try copyResource(name: res, destUrl: dest)
            }
            // MARK: Step 2 download gstreamer
            let gstURL = try await getGstreamerDownloadURL()
            console.log("Gstreamer download url: \(gstURL)")
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gstreamerDownloader = TarDownloader(
                    fromUrl: gstURL,
                    onProgress: { progress in
                        setProgress(progress)
                    },
                    onComplete: { url in
                        do {
                            let src = url.appendingPathComponent("GStreamer.framework")
                            let dst = destUrl.appendingPathComponent("Contents/SharedSupport/CrossOver/lib64/")
                            if f.fileExists(atPath: dst.appendingPathComponent("GStreamer.framework/.gitignore").path) { // need to remove this
                                try f.removeItem(at: dst.appendingPathComponent("GStreamer.framework/.gitignore"))
                            }
                            try f.copyItem(at: src, to: dst.appendingPathComponent("GStreamer.framework"))
                            try f.removeItem(at: dst.appendingPathComponent("gstreamer-1.0"))
                            let opts = Opts()
                            // MARK: Step 3 add env variables to crossover configuration
                            addGlobals(appURL: destUrl, opts: opts)
                            // MARK: Step 4 disable auto update
                            if(opts.autoUpdateDisable) {
                                disableAutoUpdate(url: destUrl)
                            }
                            // MARK: Step 5 sign
                            // MARK: Step 6 fix app after patching
                            try signAndFixup(destPath: destUrl.path())
                            continuation.resume()
                        } catch {
                            console.error(String(reflecting: error))
                            continuation.resume(throwing: error)
                        }
                        setLoading(false)
                    },
                    onError: { error in
                        console.error(String(reflecting: error))
                        continuation.resume(throwing: error)
                    }
                )
                setLoading(true)
                gstreamerDownloader.download()
            }
        } else {
            console.error("Couldn't find Crossover_x87.app in \(destUrl.path())")
        }
    } catch {
        console.error(String(reflecting: error))
    }
    return destUrl
}
