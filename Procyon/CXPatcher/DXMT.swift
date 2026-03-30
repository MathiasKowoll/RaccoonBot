//
//  DXMT.swift
//  Procyon
//
//  Created by Italo Mandara on 30/03/2026.
//
import Foundation

private let WINE_DXMT_RESOURCES_PATHS: [String] = [
    "/lib/wine/i386-windows/winemetal.dll",
    "/lib/wine/x86_64-windows/winemetal.dll",
]

private let DXMT_PATHS = [
    PathMap(src: "src/winemetal/unix/winemetal.so", dst: "/lib/dxmt/x86_64-unix/winemetal.so"),
    PathMap(src: "src/winemetal/winemetal.dll", dst: "/lib/dxmt/x86_64-windows/winemetal.dll"),
    PathMap(src: "src/dxgi/dxgi.dll", dst: "/lib/dxmt/x86_64-windows/dxgi.dll"),
    PathMap(src: "src/d3d11/d3d11.dll", dst: "/lib/dxmt/x86_64-windows/d3d11.dll"),
    PathMap(src: "src/d3d10/d3d10core.dll", dst: "/lib/dxmt/x86_64-windows/d3d10core.dll"),
]

private let DXMT_PATHS_RELEASE = [
    PathMap(src: "x86_64-unix/winemetal.so", dst: "/lib/dxmt/x86_64-unix/winemetal.so"),
    PathMap(src: "x86_64-windows/winemetal.dll", dst: "/lib/dxmt/x86_64-windows/winemetal.dll"),
    PathMap(src: "x86_64-windows/dxgi.dll", dst: "/lib/dxmt/x86_64-windows/dxgi.dll"),
    PathMap(src: "x86_64-windows/d3d11.dll", dst: "/lib/dxmt/x86_64-windows/d3d11.dll"),
    PathMap(src: "x86_64-windows/d3d10core.dll", dst: "/lib/dxmt/x86_64-windows/d3d10core.dll"),
    PathMap(src: "i386-windows/winemetal.dll", dst: "/lib/dxmt/i386-windows/winemetal.dll"),
    PathMap(src: "i386-windows/dxgi.dll", dst: "/lib/dxmt/i386-windows/dxgi.dll"),
    PathMap(src: "i386-windows/d3d11.dll", dst: "/lib/dxmt/i386-windows/d3d11.dll"),
    PathMap(src: "i386-windows/d3d10core.dll", dst: "/lib/dxmt/i386-windows/d3d10core.dll"),
]

func getDXMTDownloadURL() async throws -> (url: URL, versionTag: String) {
    let path = "https://api.github.com/repos/3Shain/dxmt"
    let version = try await fetchLatestRelease(from: path)
    return (URL(string: "https://github.com/3Shain/dxmt/releases/download/\(version)/dxmt-\(version)-builtin.tar.gz")!, versionTag: version)
}

func installDXMT(srcURL: URL, destUrl: URL, versionTag: String) throws {
    let f = FileManager.default
    let dxmtURL = srcURL.appendingPathComponent(versionTag)
//    let artifactTestPath = dxmtURL.appendingPathComponent(DXMT_PATHS[0].src).path
    let releaseTestPath = dxmtURL.appendingPathComponent(DXMT_PATHS_RELEASE[0].src).path
    
//    if(f.fileExists(atPath: artifactTestPath)) {
//        console.log("Artifact version detected, copying DXMT")
//        try DXMT_PATHS.forEach { path in
//            let artifactSrc = URL(fileURLWithPath: dxmtPath + path.src)
//            let artifactDest = URL(fileURLWithPath: destUrl.path() + SHARED_SUPPORT_PATH + path.dst)
//            try f.copyItem(at: artifactSrc, to: artifactDest)
//        }
//    } else
    if (f.fileExists(atPath: releaseTestPath)) {
        console.log("Release version detected, copying DXMT")
        let dxmt32Folder = destUrl.appendingPathComponent(SHARED_SUPPORT_PATH).appendingPathComponent("lib/dxmt/i386-windows")
        
        if(f.fileExists(atPath: dxmt32Folder.path() ) == false){
            console.log("\(dxmt32Folder.path()) does not exist, creating")
            do {
                try f.createDirectory(at: dxmt32Folder, withIntermediateDirectories: true)
                console.log("\(dxmt32Folder.path()) created")
            } catch {
                console.log(error.localizedDescription)
            }
        }
        try DXMT_PATHS_RELEASE.forEach { path in
            let releaseSrc = dxmtURL.appendingPathComponent(path.src)
            let releaseDest = destUrl.appendingPathComponent(SHARED_SUPPORT_PATH + path.dst)
            try safeFileCopy(source: releaseSrc, dest: releaseDest)
        }
    } else {
//        console.log("Could not find dxmt source at '\(artifactTestPath)' nor '\(releaseTestPath)', skipping installation")
        console.log("Could not find dxmt source at '\(releaseTestPath)', skipping installation")
    }
}
