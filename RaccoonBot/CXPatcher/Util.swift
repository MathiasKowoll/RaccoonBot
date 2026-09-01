//
//  Util.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 26/03/2026.
//
import Foundation
import AppKit

let D3DM_CACHE_FOLDER = "d3dm"
/// Where the bottles live.
///
/// Prefers our own directory and falls back to the one inherited from upstream,
/// which is what makes the move safe: the migration CLONES rather than moves,
/// the original stays exactly where it was, and a build from either side of the
/// change finds a working set of bottles.
///
/// Resolved once, at launch. A bottle path that changed under a running
/// application would be worse than either answer.
nonisolated(unsafe) let PROCYON_SUPPORT_FOLDER_URL: URL = {
    let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first!
    let ours = root.appendingPathComponent("RaccoonBot")
    let inherited = root.appendingPathComponent("Procyon")
    let bottles = ours.appendingPathComponent("CXPBottles")
    // Ours only counts once it actually holds bottles: an empty directory left
    // by a half-finished migration must not shadow a working one.
    if let contents = try? FileManager.default.contentsOfDirectory(atPath: bottles.path(percentEncoded: false)),
       contents.contains(where: { !$0.hasPrefix(".") }) {
        return ours
    }
    return FileManager.default.fileExists(atPath: inherited.path(percentEncoded: false)) ? inherited : ours
}()

let PATCHED_CX_APPNAME = "Crossover_patched.app"
private let DEFAULT_CXP_BOTTLES_ROOTPATH = "/Users/${USER}/"
nonisolated let DEFAULT_CXP_BOTTLES_FOLDER = "CXPBottles"
//private let DEFAULT_CXP_BOTTLES_ROOTPATH = "/Users/${USER}/Application Support/Procyon/"
//private let DEFAULT_CXP_BOTTLES_FOLDER = "Bottles"
//private let DEFAULT_CXP_BOTTLES_PATH = DEFAULT_CXP_BOTTLES_ROOTPATH + DEFAULT_CXP_BOTTLES_FOLDER
let DEFAULT_BOTTLES_ROOT = PROCYON_SUPPORT_FOLDER_URL.appendingPathComponent(DEFAULT_CXP_BOTTLES_FOLDER).path(percentEncoded: false)
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

// WINE_D3DM_RESOURCES_PATHS is gone: see d3dMetalResources(version:).


private let dxvkRes: [(res: String, dest: String)] = WINE_DXVK_RESOURCES_PATHS.map { path in
    (res: path, dest: "/lib/" + path)
}

private let allResources = dxvkRes + [
    (res: "wine/x86_64-unix/ntdll.so", dest: "/lib/wine/x86_64-unix/ntdll.so"),
    (res: "wine/x86_64-unix/win32u.so", dest: "/lib/wine/x86_64-unix/win32u.so"),
    (res: "wine/i386-windows/ntdll.dll", dest: "/lib/wine/i386-windows/ntdll.dll"),
    (res: "wine/x86_64-windows/ntdll.dll", dest: "/lib/wine/x86_64-windows/ntdll.dll"),
    (res: "wine/i386-windows/win32u.dll", dest: "/lib/wine/i386-windows/win32u.dll"),
    (res: "wine/x86_64-windows/win32u.dll", dest: "/lib/wine/x86_64-windows/win32u.dll"),
    (res: "d9vk/x32/d3d9_builtin.dll", dest: "/lib/wine/i386-windows/d3d9.dll"),
    (res: "d9vk/x64/d3d9_builtin.dll", dest: "/lib/wine/x86_64-windows/d3d9.dll"),
]

// Three resources are deliberately NOT in that list any more:
//
//     wine/x86_64-unix/winegstreamer.so
//     wine/x86_64-unix/winedmo.so
//     wine/x86_64-windows/winegstreamer.dll
//
// They are Wine's bridge to GStreamer, built to load it out of the framework
// the patcher used to install. `otool -l` on the shipped .so files gives
//
//     LC_RPATH  @loader_path/../../../lib64/GStreamer.framework/Libraries
//
// while CrossOver 27's own build carries @loader_path/../../../lib/x86_64 --
// and 27 has no lib64 at all, so the copied bridge resolves its libraries to
// nothing. Since the framework install is gone (we stage two plugins beside
// the engine's own GStreamer instead of replacing it), these binaries now
// point at something that will never exist. The engine's own are correct for
// the engine, so they are left alone.

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
    var cxbottlesPath = DEFAULT_BOTTLES_ROOT
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

/// `resources` exists so this can be exercised against the source tree.
///
/// In a test host `Bundle.main` is not the application -- measured: asking it
/// for a toolkit generation returns nothing -- so anything reaching for
/// resources through it can only be tested by shape, never by behaviour. That
/// is the gap that left the .orig contract agreed by both sides and exercised
/// by neither.
func copyResource(name: String, destUrl: URL, resources: URL? = nil) throws {
    let f = FileManager.default
    let located = resources.map { $0.appendingPathComponent(name) }
        .flatMap { f.fileExists(atPath: $0.path(percentEncoded: false)) ? $0 : nil }
    if let resUrl = located ?? Bundle.main.url(forResource: name, withExtension: nil) {
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

func removeSignature(destURL: URL) throws {
    try safeShell("/usr/bin/codesign --remove-signature \"\(destURL.path())\"")
    let command = "/usr/bin/codesign --remove-signature \"\(destURL.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine").path())\""
    try safeShell(command)
}

// makeX87CrossoverPatchedCopy is gone: see the note in Launcher.swift.

func signAndFixup(destPath: String) throws {
    try safeShell("/usr/bin/codesign --force --deep --sign - \"\(destPath)\"")
    try fixup(destPath: destPath)
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

enum ReleaseLookupError: LocalizedError {
    case http(Int)
    case noTag

    var errorDescription: String? {
        switch self {
        case .http(403), .http(429):
            return "GitHub is rate limiting this machine. It allows sixty anonymous requests an hour; try again shortly."
        case .http(let code):
            return "GitHub answered HTTP \(code)"
        case .noTag:
            return "GitHub's answer carried no release tag"
        }
    }
}

/// The newest release tag of a GitHub repository.
///
/// Every value here used to be force-unwrapped, on a response from the
/// network. The anonymous API allows sixty requests an hour and answers 403
/// with a body that has a `message` and no `tag_name` -- so `as! String` on a
/// missing key trapped, and a trap is not something the do/catch around the
/// call site can catch. Being rate limited while patching CrossOver killed the
/// application.
func fetchLatestRelease(from path: String) async throws -> String {
    guard let url = URL(string: "\(path)/releases/latest") else {
        throw ReleaseLookupError.noTag
    }
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        throw ReleaseLookupError.http(http.statusCode)
    }
    let parsed = try? JSONSerialization.jsonObject(with: data)
    guard let json = parsed as? [String: Any],
          let tag = json["tag_name"] as? String, !tag.isEmpty else {
        throw ReleaseLookupError.noTag
    }
    return tag
}

/// The files a toolkit generation actually carries, relative to its resource
/// directory, plus `external` as a whole.
///
/// Read from the bundle rather than from a written list, because the two
/// generations do not carry the same names: 3 has `atidxx64.dll` and
/// `nvngx.dll` where 4 has `d3d10.dll` and `nvngx-on-metalfx.dll`. The list
/// this replaced named 4's spellings, so installing 3 could not find two of
/// them and never installed two of its own -- and `copyResource` logs
/// "Couldn't find source" and carries on, so the install reported success. It
/// also named six `wine/x86_64-unix/*.so` that neither generation has ever
/// carried; those directories ship empty. Six errors on every launch, for
/// years, meaning nothing.
func d3dMetalResources(version: String, resources: URL? = nil) -> [String] {
    guard let root = (resources ?? Bundle.main.resourceURL)?
        .appendingPathComponent("d3dMetal\(version)") else {
        return ["external"]
    }
    return d3dMetalResources(inGeneration: root)
}

/// The same, of a directory named outright, so a test can read the generations
/// in the source tree rather than depend on which bundle it is hosted by.
func d3dMetalResources(inGeneration generation: URL) -> [String] {
    var paths = ["external"]
    let wine = generation.appendingPathComponent("wine")
    let f = FileManager.default
    // Each architecture directory read on its own rather than through a
    // recursive enumerator. Half of what a generation carries are symlinks --
    // every `wine/x86_64-unix/*.so` points at `external/libd3dshared.dylib` --
    // and `contentsOfDirectory` lists them where a filter on regular files
    // drops them. `find -type f` hides them the same way, which is how they
    // were first mistaken for missing.
    for arch in (try? f.contentsOfDirectory(atPath: wine.path(percentEncoded: false)))?.sorted() ?? [] {
        let dir = wine.appendingPathComponent(arch)
        var isDirectory: ObjCBool = false
        guard f.fileExists(atPath: dir.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else { continue }
        for name in (try? f.contentsOfDirectory(atPath: dir.path(percentEncoded: false)))?.sorted() ?? [] {
            paths.append("wine/\(arch)/\(name)")
        }
    }
    return paths
}


func installd3dMetal(at: URL, version: String, resources: URL? = nil) throws -> Void {
    guard let layout = EngineLayout.of(at) else {
        throw UnsupportedEngine(path: at.path(percentEncoded: false))
    }
    // Put the engine back before putting a generation in.
    //
    // Otherwise switching generations mixes them: 4 installs `d3d10.dll`, 3
    // does not carry that name, and the file stays behind with 4's bytes while
    // the engine reports as 3. Restoring first means the only toolkit files in
    // the engine are the engine's own plus this generation's.
    let wineHalf = at.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
        .appendingPathComponent("/\(layout.gptkRoot)/apple_gptk/wine")
    if let walker = FileManager.default.enumerator(at: wineHalf, includingPropertiesForKeys: nil) {
        for case let url as URL in walker where url.pathExtension == "orig" {
            try? restoreOrig(destUrl: url.deletingPathExtension())
        }
    }

    // Two things recorded here rather than guessed at.
    //
    // A synthetic reproduction of an MGVF backup set -- same shapes, same
    // symlinks -- made copyResource fail with "an item with the same name
    // already exists" on wine/x86_64-unix/d3d11.so, where the same code
    // against a real MGVF-made engine succeeded. `fileExists` follows a
    // symlink, so a link whose target is momentarily absent reads as missing,
    // the move-aside is skipped, and the copy then hits the link that is still
    // there. Not chased to the bottom and not reproduced against a real
    // engine, so it is a thread rather than a defect -- but it is the kind
    // that only shows when external is being replaced underneath.
    //
    // A leftover this does NOT fix, measured against a real engine.
    //
    // Generation 4 ships d3d10, which CrossOver does not, so installing 4
    // creates it with no .orig -- and restoring cannot remove it, because
    // restoring gives back what was displaced and cannot give back an absence.
    // An engine reporting as generation 3 can hold that one file of 4.
    //
    // The obvious fix is wrong and was measured to be wrong: deleting files
    // that have no .orig and whose names belong to the other generation also
    // deletes CrossOver's OWN atidxx64 and nvngx, because after a restore a
    // stock file has no backup either and the filesystem cannot tell the two
    // apart. That version removed two files the engine shipped with. Doing it
    // safely needs a record of what we placed, written when we place it --
    // which is a change worth making deliberately rather than at the end of a
    // long day.
    let d3dmRes: [(res: String, dest: String)] = d3dMetalResources(version: version, resources: resources).map { path in
        let destPath = path.replacingOccurrences(of: "nvngx-on-metalfx", with: "nvngx")
        return (res: "d3dMetal\(version)/" + path, dest: "/\(layout.gptkRoot)/apple_gptk/" + destPath)
    }
    
    let toCopy = d3dmRes
        .map { item in
            (res: item.res, dest: at.appendingPathComponent(SHARED_SUPPORT_COMPONENT).appendingPathComponent(item.dest))
        }
    
    for (res, dest) in toCopy {
        console.log("Copying \(res) to \(dest.path())")
        try copyResource(name: res, destUrl: dest, resources: resources)
    }
}

func activateApp(_ gameName: String) -> Void {
    //do nothing
    let app = NSWorkspace().runningApplications.first(where: { gameName.contains($0.localizedName ?? "none")})
    console.log("attempting to put your game in the foreground")
    console.log(app?.executableURL?.lastPathComponent ?? app?.localizedName ?? "couldn't get app")
    app?.activate()
}

// makeCrossoverPatchedCopy is gone, and with it the x87 variant.
//
// MacGameVideoFix makes the engine now -- one application owning the engine
// means one thing to validate rather than two, which was the whole reason.
// See Util/EngineMaker.swift for what replaced it.
//
// The x87 bundle went with it. It was a second engine chosen by the "reduced
// x87 precision" toggle, and what distinguished it was not precision: d9vk,
// ntdll and win32u lived only there because the resource table filtered them
// out of the normal copy. No current title needs it. Reduced precision itself
// survives as what it always should have been -- an environment variable, in
// getInlineEnvs, with no second engine behind it.

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
