//
//  Crossover.swift
//  RaccoonBot
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
    console.log("Loading CrossOver configuration from \(confPath.path) ...")
    let envSection = getConfigSection(fileURL: confPath, section: "EnvironmentVariables")
    console.log("Finding CX_BOTTLE_PATH in configuration ...")
    let cxBottlePath = envSection["CX_BOTTLE_PATH"]
    if let cxBottlePath {
        console.log("Found CX_BOTTLE_PATH in configuration: \(cxBottlePath)")

        if cxBottlePath.hasPrefix("/Users/${USER}/") {
            console.log("Found user based path, transforming to local user path ...")
            let components = cxBottlePath.split(separator: "/").dropFirst(2) // ["Users", "${USER}", "..."]
            let path = components.joined(separator: "/")
            return base.appendingPathComponent(path, isDirectory: true)
        } else {
            return URL(filePath: cxBottlePath)
        }
    }
    
    // fallback if it doesn't find it in the config file (just in case)
    console.warn("Couldn't find CXPatcher bottles configuration: " + confPath.absoluteString)
    let bottlePathForCXP: URL = PROCYON_SUPPORT_FOLDER_URL.appendingPathComponent(DEFAULT_CXP_BOTTLES_FOLDER, isDirectory: true)
    return bottlePathForCXP
}

/// What a bottle records about itself.
///
/// The architecture is read from cxbottle.conf and never inferred from the
/// name: this machine has two ARM bottles called "SteamARM" and "SteamArm",
/// in different roots, on different engines. The same lesson as with engines --
/// identity comes from the contents, not the filename.
struct BottleInfo {
    let url: URL
    let name: String
    /// "win64" for a normal bottle, "arm64" for an ARM one.
    let arch: String
    /// The engine CFBundleVersion this bottle was last touched by.
    let version: String

    var isARM: Bool { arch == "arm64" }

    /// Can this bottle run x86 games?
    ///
    /// An ARM bottle needs FEX to emulate x86, and FEX ships only with
    /// CrossOver 27 (lib/wine/aarch64-unix/libwow64fex.so). An ARM bottle on 26
    /// runs ARM-native Windows binaries and nothing else, so offering it for a
    /// Steam game would be offering the one bottle that cannot run it.
    var canRunX86: Bool {
        guard isARM else { return true }
        return version.split(separator: ".").first.flatMap { Int($0) }.map { $0 >= 27 } ?? false
    }
}

func bottleInfo(_ bottleURL: URL) -> BottleInfo? {
    let conf = bottleURL.appendingPathComponent("cxbottle.conf")
    guard let text = try? String(contentsOf: conf, encoding: .utf8) else { return nil }
    func value(_ key: String) -> String? {
        for line in text.components(separatedBy: .newlines) where line.hasPrefix("\"\(key)\"") {
            let parts = line.components(separatedBy: "\"")
            if parts.count >= 4 { return parts[3] }
        }
        return nil
    }
    return BottleInfo(url: bottleURL,
                      name: bottleURL.lastPathComponent,
                      arch: value("WineArch") ?? "win64",
                      version: value("Version") ?? "")
}

/// Set one key in a bottle's [EnvironmentVariables], leaving every other key
/// alone, and creating the section if it is missing.
///
/// Per key, never per section. Truncating the section is what took other
/// tools' keys with it -- and losing GST_PLUGIN_PATH turns a working cutscene
/// into a black screen with nothing to explain it.
func setBottleEnv(_ bottleURL: URL, key: String, value: String) {
    let conf = bottleURL.appendingPathComponent("cxbottle.conf")
    guard let original = try? String(contentsOf: conf, encoding: .utf8) else {
        console.error("Couldn't read \(conf.path(percentEncoded: false))")
        return
    }
    let line = "\"\(key)\" = \"\(value)\""
    var out: [String] = []
    var inSection = false, written = false
    for l in original.components(separatedBy: .newlines) {
        if l.hasPrefix("[") {
            if inSection && !written { out.append(line); written = true }
            inSection = (l == "[EnvironmentVariables]")
            out.append(l)
            continue
        }
        if inSection && l.hasPrefix("\"\(key)\"") {
            if !written { out.append(line); written = true }
            continue
        }
        out.append(l)
    }
    if !written {
        if !inSection { out.append("[EnvironmentVariables]") }
        out.append(line)
    }
    do {
        // Trailing newline, because this key is often the last line written.
        // Without it the next tool to append a line lands on the end of ours,
        // and CrossOver's parser reads the fused result as a key nobody set.
        try (out.joined(separator: "\n") + "\n").write(to: conf, atomically: true, encoding: .utf8)
        console.log("\(key) set in \(bottleURL.lastPathComponent)")
    } catch {
        console.error(String(reflecting: error))
    }
}

/// The bottles this application manages.
///
/// Its own, and only its own. They live under the patched engine's
/// CX_BOTTLE_PATH -- ~/Library/Application Support/RaccoonBot/CXPBottles --
/// which is a different directory from the one a CrossOver install of its own
/// uses. A machine can easily have both, and the CrossOver ones are not listed
/// here, not written into, and not pointed at the staged codecs. They belong
/// to CrossOver.
func getAllBottles(appDir: URL) throws -> [URL] {
    let f = FileManager.default
    let FORCE_IS_CXPATCHED = true
    
    
    var subfolders: [URL] = []
    
    if(FORCE_IS_CXPATCHED || isCXPatched(appDir: appDir)) {
        let bottleURLForCXP = try getCXPatcherBottlesURL(appDir: appDir)
        console.log("app is patched with CXPatcher")
        do {
            subfolders = try f.contentsOfDirectory(at: bottleURLForCXP, includingPropertiesForKeys: [.isDirectoryKey], options: [])
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
        console.error("No bottle selected in RaccoonBot config")
    }
}

/// The environment keys RaccoonBot itself sets at launch time.
///
/// Only these are cleared from a bottle. Clearing them is necessary, not
/// cosmetic: CrossOver's own launcher (lib/perl/CXBottle.pm) applies whatever
/// cxbottle.conf holds *after* the command line and assigns it
/// unconditionally, so a stale key here silently beats the per-game choice.
///
/// GST_PLUGIN_PATH and its siblings are deliberately absent from this list.
/// They are how staged codecs reach the engine, they may have been put there
/// by another tool, and losing one turns a working cutscene into a black
/// screen with no error to explain it. Leaving them also means a staged path
/// in the bottle wins over the framework path injected at launch, which is
/// the behaviour we want.
let PROCYON_MANAGED_ENV_KEYS: Set<String> = [
    "D3DM_ENABLE_METALFX", "D3DM_MTL4", "D3DM_MAX_FPS",
    "DXMT_ENABLE_NVEXT", "DXMT_CONFIG", "DXMT_METALFX_SPATIAL_SWAPCHAIN",
    "DXVK_ASYNC",
    "MTL_HUD_ENABLED",
    "MVK_CONFIG_UE4_HACK_ENABLED", "NAS_DISABLE_UE4_HACK",
    "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS",
    "ROSETTA_ADVERTISE_AVX",
    "CX_GRAPHICS_BACKEND", "CX_LIBVULKAN",
]

/// Remove RaccoonBot's own keys from a bottle, leaving every other key intact.
///
/// This used to truncate the whole `[EnvironmentVariables]` section. That took
/// third-party keys with it, and it assumed the section was the last one in the
/// file -- anything CrossOver wrote after it was destroyed too. A pristine copy
/// is kept once, the first time we ever touch the file.
func stripEnvsInCXBottleConfigFile(selectedBottle: String) throws {
    guard let bottleURL = getCXBottleConfigFileURL(selectedBottle: selectedBottle) else {
        console.error("No bottle selected in RaccoonBot config")
        return
    }
    let original = try String(contentsOf: bottleURL, encoding: .utf8)

    var out: [String] = []
    var inSection = false
    var changed = false
    for line in original.components(separatedBy: .newlines) {
        if line.hasPrefix("[") {
            inSection = (line == "[EnvironmentVariables]")
            out.append(line)
            continue
        }
        if inSection, line.hasPrefix("\"") {
            let key = String(line.dropFirst().prefix(while: { $0 != "\"" }))
            if PROCYON_MANAGED_ENV_KEYS.contains(key) {
                changed = true
                continue
            }
        }
        out.append(line)
    }
    guard changed else { return }

    let backup = bottleURL.appendingPathExtension("procyon-orig")
    if !FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)) {
        try? original.write(to: backup, atomically: true, encoding: .utf8)
    }
    try out.joined(separator: "\n").write(to: bottleURL, atomically: true, encoding: .utf8)
}

func getDxmtConfigEnv(values: [String]) -> String {
    return values.count == 0 ? "" : "DXMT_CONFIG=\"\(values.joined(separator: ";"))\" "
}

func getInlineEnvs(from: GameOptions, cxAppPath: String? = nil) -> String {
    /**
     @TO DO:
     "MVK_CONFIG_FAST_MATH", "1"
     "MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS", "3"
     "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "1"
     "MVK_CONFIG_USE_MTLHEAP", "2"
     MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1 -> used by d9vk
     
     # 1. Point to your driver
     export VK_ICD_FILENAMES="/Volumes/Card/code/mesa/build_x86/src/kosmickrisp/vulkan/kosmickrisp_mesa_icd.x86_64.json"

     # 2. Tell the loader to ignore MoltenVK and use ONLY your driver
     export VK_ICD_FILENAMES_ONLY=1

     # 3. Disable the "Portability" check that confuses old DXVK
     export VK_KHR_PORTABILITY_ENUMERATION=0

     # 4. Force DXVK to accept the "Conformant" surface KosmicKrisp provides
     export DXVK_WSI_DRIVER="vulkan"
     export DXVK_CONFIG="dxvk.allowNativeVulkan = True"
     */
    func DoubleToFormattedStr(_ value: Double, _ digits: Int = 2) -> String {
        return String(value.formatted(.number.precision(.fractionLength(0...digits))))
    }
    func onOff(_ value: Bool?) -> String {
        return value != nil && value == true ? "1" : "0"
    }
    var value = from.envVariables == "" ? "" : "\(from.envVariables) "
    var defaults = [
        "D3DM_ENABLE_METALFX=1",
        "DXMT_ENABLE_NVEXT=1",
        "DXVK_ASYNC=1",
//        "MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1", //slower, but more reliable
//        "MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS=3", //this actually slows down everything
//        "MVK_CONFIG_USE_MTLHEAP=2",
//        "D3DM_MTL4=0",
//        "D3DM_MAX_FPS=60",
    ]
    if let cxpath = cxAppPath  {
        defaults += [
            "GST_PLUGIN_SYSTEM_PATH=\(cxpath)/Contents/SharedSupport/CrossOver/lib64/GStreamer.framework/Versions/Current/lib/gstreamer-1.0",
            "GST_PLUGIN_PATH=\(cxpath)/Contents/SharedSupport/CrossOver/lib64/GStreamer.framework/Versions/Current/lib/gstreamer-1.0",
            "GST_PLUGIN_SCANNER=\(cxpath)/Contents/SharedSupport/CrossOver/lib64/GStreamer.framework/Versions/Current/bin/gst-plugin-scanner",
        ]
    }
    let cxGraphicsBackend = from.cxGraphicsBackend.contains("d3dmetal") ? "d3dmetal" : from.cxGraphicsBackend
    value += defaults.joined(separator: " ") + " "
    value += from.mtlHudEnabled ? "MTL_HUD_ENABLED=1 " : ""
    value += from.ue4Hack ? "MVK_CONFIG_UE4_HACK_ENABLED=1 NAS_DISABLE_UE4_HACK=0 " : "MVK_CONFIG_UE4_HACK_ENABLED=0 NAS_DISABLE_UE4_HACK=1 "
    value += from.mvkArgBuff ? "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1 " : "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0 "
    value += "ROSETTA_ADVERTISE_AVX=\(onOff(from.advertiseAVX)) "
    value += "CX_GRAPHICS_BACKEND=\"\(cxGraphicsBackend)\" "
    value += "D3DM_MTL4=\(from.d3dMtl4Enabled ? "1" : "0") "
    if from.d3dMaxFPS > 20 {
        value += "D3DM_MAX_FPS=\(DoubleToFormattedStr(from.d3dMaxFPS)) "
    }
//    switch (from.vulkanLib) {
//        case "latest":
//            if let url = Bundle.main.url(forResource: "libMoltenVK-latest", withExtension: "dylib") {
//                value += "CX_LIBVULKAN=\"\(url.path(percentEncoded: false))\" "
//            }
//        case "experimental":
//            if let url = Bundle.main.url(forResource: "libMoltenVK-experimental", withExtension: "dylib") {
//                value += "CX_LIBVULKAN=\"\(url.path(percentEncoded: false))\" "
//            }
//        case "experimental2":
//            if let url = Bundle.main.url(forResource: "libMoltenVK-experimental2", withExtension: "dylib") {
//                value += "CX_LIBVULKAN=\"\(url.path(percentEncoded: false))\" "
//            }
//        //    case "kosmickrisp":
//        //        if let url = Bundle.main.url(forResource: "libvulkan_kosmickrisp", withExtension: "dylib") {
//        //            value += "CX_LIBVULKAN=\"\(url.path(percentEncoded: false))\" "
//        //        }
//        default:
//            break
//    }
    let dxmtMetalFXSpatial = from.dxmtMetalFXSpatial ? "DXMT_METALFX_SPATIAL_SWAPCHAIN=1 " : ""
    value += dxmtMetalFXSpatial
    
    var dxmtConfigValues: [String] = []
    if from.dxmtPreferredMaxFrameRate > 20 {
        dxmtConfigValues.append("d3d11.preferredMaxFrameRate=\(DoubleToFormattedStr(from.dxmtPreferredMaxFrameRate))")
    }
    if from.dxmtMetalFXSpatial == true  {
        dxmtConfigValues.append("d3d11.metalSpatialUpscaleFactor=\(from.dxmtMetalSpatialUpscaleFactor)")
    }
    
    // Reduced x87 precision.
    //
    // This used to point ROSETTA_X87_PATH at a bundled loader, which only
    // worked alongside a second, signature-stripped copy of CrossOver -- 1.9 GB
    // whose only difference was that missing signature. On CrossOver 27 an ARM
    // bottle runs x86 code through FEX (lib/wine/aarch64-unix/libwow64fex.so),
    // and the same knob is one environment variable.
    //
    // NOT VERIFIED on this engine: the string FEX_X87REDUCEDPRECISION does not
    // appear in any binary CrossOver 27 ships, so whether this build reads FEX
    // configuration from the environment still has to be measured against a
    // real ARM bottle.
    if (from.x87PatchEnabled) {
        // Which lever exists depends on what is translating the x86 code, and
        // that is decided by the BOTTLE, not by the engine: an ARM bottle runs
        // x86 through FEX, an x86_64 bottle runs it through Rosetta. Keying
        // this on the engine alone emitted the FEX variable for a win64 bottle
        // on 27, where FEX is not involved at all.
        let layout = cxAppPath.flatMap { EngineLayout.of(URL(fileURLWithPath: $0)) }
        switch (from.useArmBottle, layout) {
        case (true, .cx27):
            // ARM bottle: x86 is emulated by FEX, which CrossOver 27 ships as
            // lib/wine/aarch64-unix/libwow64fex.so and libarm64ecfex.so. This
            // is a supported CrossOver variable and it works.
            //
            // Grepping the shipped binaries for the name finds nothing, which
            // is not evidence of anything: FEX builds its option names at
            // runtime rather than storing them whole.
            value += "FEX_X87REDUCEDPRECISION=1 "
        case (false, .cx26):
            // x86_64 bottle under Rosetta: the only lever is rosettaX87, and
            // it needs the signature-stripped copy of the engine.
            if let runtimex87Url = Bundle.main.url(forResource: "runtime_loader", withExtension: nil) {
                value += "ROSETTA_X87_PATH=\"\(runtimex87Url.path())\" "
            } else {
                console.error("Couldn't find runtime_loader")
            }
        case (true, _):
            console.error("Reduced x87 precision needs FEX, which ships with CrossOver 27; nothing applied")
        case (false, .cx27):
            // Rosetta translates here, so the lever would be rosettaX87 -- and
            // that needs the signature-stripped copy of the engine, which is
            // not built for 27 on purpose.
            console.error("Reduced x87 precision is only available in an ARM bottle on CrossOver 27; nothing applied")
        case (false, .none):
            console.error("x87 requested but the engine version is unknown; nothing applied")
        }
    }
    
    value += getDxmtConfigEnv(values:  dxmtConfigValues)
    return value
}

func toCrossoverENVString(_ key: String, _ value: String) -> String {
    return "\"\(key)\" = \"\(value)\""
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

func createBottle(cxAppPath: String, bottleName: String = "Steam", template: String = "win10_64") throws -> Process {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: cxAppPath).appendingPathComponent("/Contents/SharedSupport/CrossOver/bin/cxbottle")
    proc.arguments = ["--create", "--bottle", bottleName, "--template", template]
    try proc.run()
    return proc
}

func install(cxAppPath: String, bottleName: String = "Steam", template: String = "win10_64") throws -> Process {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: cxAppPath).appendingPathComponent("/Contents/SharedSupport/CrossOver/bin/cxbottle")
    proc.arguments = ["--create", "--bottle", bottleName, "--template", template]
    try proc.run()
    return proc
}
