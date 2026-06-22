//
//  Gstreamer.swift
//  Procyon
//
//  Created by Italo Mandara on 30/03/2026.
//
import Foundation

let BUILTIN_LIBS_GSTREAMER64 = [
    "libgmodule-2.0.dylib",
    "libgthread-2.0.dylib",
    "libgstplayer-1.0.0.dylib",
    "libgstaudio-1.0.0.dylib",
    "libgstsdp-1.0.dylib",
    "libgstmpegts-1.0.0.dylib",
    "libgstnet-1.0.0.dylib",
    "libgstmpegts-1.0.dylib",
    "libgstrtsp-1.0.dylib",
    "libffi.8.dylib",
    "libgstreamer-1.0.dylib",
    "libgsttranscoder-1.0.dylib",
    "libgstisoff-1.0.0.dylib",
    "libgstphotography-1.0.0.dylib",
    "libgstsdp-1.0.0.dylib",
    "libgstplay-1.0.dylib",
    "libgstplay-1.0.0.dylib",
    "libgobject-2.0.dylib",
    "libgstreamer-1.0.0.dylib",
    "libgstcodecs-1.0.dylib",
    "libpcre2-8.0.dylib",
    "libgstwebrtc-1.0.0.dylib",
    "libgstcontroller-1.0.0.dylib",
    "libgstcodecparsers-1.0.dylib",
    "libgstbadaudio-1.0.dylib",
    "libglib-2.0.0.dylib",
    "libgstrtp-1.0.dylib",
    "libgstwebrtc-1.0.dylib",
    "libgsttag-1.0.dylib",
    "libgstinsertbin-1.0.0.dylib",
    "libgstisoff-1.0.dylib",
    "libgstfft-1.0.0.dylib",
    "libgstbadaudio-1.0.0.dylib",
    "libgio-2.0.dylib",
    "libglib-2.0.dylib",
    "libgobject-2.0.0.dylib",
    "libgsttag-1.0.0.dylib",
    "libgstvideo-1.0.0.dylib",
    "libgsttranscoder-1.0.0.dylib",
    "libgstrtp-1.0.0.dylib",
    "libgstanalytics-1.0.dylib",
    "libgstanalytics-1.0.0.dylib",
    "libgstmse-1.0.dylib",
    "libgstmse-1.0.0.dylib",
    "libgstapp-1.0.0.dylib",
    "libgstrtsp-1.0.0.dylib",
    "libintl.dylib",
    "libgstvideo-1.0.dylib",
    "libgstfft-1.0.dylib",
    "libgstadaptivedemux-1.0.dylib",
    "libgmodule-2.0.0.dylib",
    "libgstbasecamerabinsrc-1.0.dylib",
    "libgstsctp-1.0.0.dylib",
    "libintl.8.dylib",
    "libgstphotography-1.0.dylib",
    "libgsturidownloader-1.0.0.dylib",
    "libgstpbutils-1.0.dylib",
    "libgstbase-1.0.0.dylib",
    "libgstallocators-1.0.dylib",
    "libpcre2-posix.3.dylib",
    "libffi.dylib",
    "libgstcontroller-1.0.dylib",
    "libgstcodecparsers-1.0.0.dylib",
    "libgthread-2.0.0.dylib",
    "libpcre2-8.dylib",
    "libgstriff-1.0.0.dylib",
    "libgstadaptivedemux-1.0.0.dylib",
    "libgstnet-1.0.dylib",
    "libgstriff-1.0.dylib",
    "libgsturidownloader-1.0.dylib",
    "libgstbasecamerabinsrc-1.0.0.dylib",
    "libgstaudio-1.0.dylib",
    "libgstinsertbin-1.0.dylib",
    "libgstcodecs-1.0.0.dylib",
    "libgstbase-1.0.dylib",
    "libgstgl-1.0.dylib",
    "libgstgl-1.0.0.dylib",
    "libgstallocators-1.0.0.dylib",
    "libgstplayer-1.0.dylib",
    "libgstpbutils-1.0.0.dylib",
    "libpcre2-posix.dylib",
    "libgstsctp-1.0.dylib",
    "libgstapp-1.0.dylib",
    "libgio-2.0.0.dylib",
    "gstreamer-1.0",
]

func getGstreamerDownloadURL() async throws -> URL {
    let path = "https://api.github.com/repos/Sikarugir-App/gstreamer"
    let version = try await fetchLatestRelease(from: path)
    return URL(string: "https://github.com/Sikarugir-App/gstreamer/releases/download/\(version)/gstreamer-1.0-\(version)-x86_64.tar.xz")!
}

func installGstreamer (srcUrl: URL,destUrl: URL ) throws {
    let f = FileManager.default
    let src = srcUrl.appendingPathComponent("GStreamer.framework")
    let dst = destUrl.appendingPathComponent("Contents/SharedSupport/CrossOver/\(LIB_ROOT)/")
    try f.copyItem(at: src, to: dst.appendingPathComponent("GStreamer.framework"))
    if f.fileExists(atPath: dst.appendingPathComponent("GStreamer.framework/.gitignore").path) { // need to remove this
        try f.removeItem(at: dst.appendingPathComponent("GStreamer.framework/.gitignore"))
    }
    for filename in BUILTIN_LIBS_GSTREAMER64 {
        console.log("removing \(filename)")
        try? f.removeItem(at: dst.appendingPathComponent(filename))
    }
}
