//
//  AppInfoVDFTests.swift
//  RaccoonBotTests
//
//  Reading Steam's binary app cache. The names for every title a user owns but
//  has not installed come from here; the alternative is one network request per
//  title, which for a 400-game library is seven minutes of asking Valve for
//  something already on the disk.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct AppInfoVDFTests {

    /// Builds a v29 file by hand, so the parser is tested against the format
    /// rather than against one machine's cache.
    private func makeFile(apps: [(id: UInt32, name: String, type: String, os: String)]) -> Data {
        let strings = ["appinfo", "common", "name", "type", "oslist"]
        func index(_ s: String) -> UInt32 { UInt32(strings.firstIndex(of: s)!) }
        func u32(_ v: UInt32) -> [UInt8] { [0, 8, 16, 24].map { UInt8((v >> $0) & 0xFF) } }
        func i64(_ v: Int64) -> [UInt8] {
            let u = UInt64(bitPattern: v); return (0..<8).map { UInt8((u >> ($0 * 8)) & 0xFF) }
        }
        func str(_ key: String, _ value: String) -> [UInt8] {
            [0x01] + u32(index(key)) + Array(value.utf8) + [0x00]
        }

        var body: [UInt8] = []
        for app in apps {
            var blob: [UInt8] = [0x00] + u32(index("appinfo"))
            blob += [0x00] + u32(index("common"))
            blob += str("name", app.name)
            blob += str("type", app.type)
            blob += str("oslist", app.os)
            blob += [0x08]                       // close common
            blob += [0x08]                       // close appinfo
            let metadata = [UInt8](repeating: 0, count: 60)
            body += u32(app.id) + u32(UInt32(metadata.count + blob.count)) + metadata + blob
        }
        body += u32(0)                            // no more apps

        var file: [UInt8] = u32(0x07564429) + u32(1)
        let tableOffset = Int64(16 + body.count)
        file += i64(tableOffset) + body
        file += u32(UInt32(strings.count))
        for s in strings { file += Array(s.utf8) + [0x00] }
        return Data(file)
    }

    @Test func readsNamePlatformAndTypeForEveryApp() {
        let data = makeFile(apps: [
            (220, "Half-Life 2", "Game", "windows,macos,linux"),
            (1325200, "Nioh 2 – The Complete Edition", "Game", "windows"),
        ])
        let apps = AppInfoVDF.parse(data)
        #expect(apps.count == 2)
        #expect(apps["220"]?.name == "Half-Life 2")
        #expect(apps["220"]?.runsOnMac == true)
        #expect(apps["220"]?.runsOnWindows == true)
        #expect(apps["1325200"]?.name == "Nioh 2 – The Complete Edition")
        #expect(apps["1325200"]?.runsOnMac == false)
    }

    @Test func toleratesTheStrayLeadingSpaceInOsList() {
        // Observed in the real cache: one record carries " macos" with a leading
        // space. Splitting on the comma alone drops that title from the Mac
        // side, silently and only for that one game.
        let apps = AppInfoVDF.parse(makeFile(apps: [(1, "Odd", "Game", "windows, macos")]))
        #expect(apps["1"]?.runsOnMac == true)
    }

    @Test func keepsOnlyWhatIsActuallyAGame() {
        let apps = AppInfoVDF.parse(makeFile(apps: [
            (1, "A Game", "Game", "windows"),
            (2, "Its Soundtrack", "Music", "windows"),
            (3, "Some Editor", "Tool", "windows"),
        ]))
        #expect(apps.values.filter(\.isGame).count == 1)
    }

    @Test func refusesRatherThanGuessingAtAnUnfamiliarFile() {
        // A cache Steam writes in a future format must produce no names, not
        // wrong ones. Nothing here is worth a crash or an invented title.
        #expect(AppInfoVDF.parse(Data([0xDE, 0xAD, 0xBE, 0xEF])).isEmpty)
        #expect(AppInfoVDF.parse(Data()).isEmpty)
        #expect(AppInfoVDF.parse(Data(repeating: 0, count: 64)).isEmpty)
    }

    @Test func survivesATruncatedFile() {
        var data = makeFile(apps: [(220, "Half-Life 2", "Game", "windows")])
        data = data.prefix(data.count / 2)
        // The only requirement is that it returns, rather than reading past the
        // end of a file Steam was halfway through writing.
        _ = AppInfoVDF.parse(data)
    }
}
