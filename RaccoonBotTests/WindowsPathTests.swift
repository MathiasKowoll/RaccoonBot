//
//  WindowsPathTests.swift
//  RaccoonBotTests
//
//  Built against a dosdevices directory made here rather than the one on this
//  machine, so the cases that matter -- a dead drive, a device entry, a
//  relative link -- are all present and none of them depend on what happens to
//  be plugged in.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct WindowsPathTests {

    /// A bottle shaped like the real thing: drive_c behind a relative link,
    /// a live external, a dead external, and the device entries CrossOver
    /// writes alongside both.
    private func makeBottle() throws -> URL {
        let f = FileManager.default
        let bottle = f.temporaryDirectory
            .appendingPathComponent("wp-\(UUID().uuidString)", isDirectory: true)
        let dos = bottle.appendingPathComponent("dosdevices", isDirectory: true)
        let driveC = bottle.appendingPathComponent("drive_c", isDirectory: true)
        let live = bottle.appendingPathComponent("live-volume", isDirectory: true)

        try f.createDirectory(at: dos, withIntermediateDirectories: true)
        try f.createDirectory(at: driveC.appendingPathComponent("Program Files (x86)/Steam"),
                              withIntermediateDirectories: true)
        try f.createDirectory(at: live.appendingPathComponent("SteamLibrary/steamapps"),
                              withIntermediateDirectories: true)

        func link(_ name: String, _ target: String) throws {
            try f.createSymbolicLink(atPath: dos.appendingPathComponent(name).path(percentEncoded: false),
                                     withDestinationPath: target)
        }
        try link("c:", "../drive_c")                       // relative, as CrossOver writes it
        try link("d:", live.path(percentEncoded: false))   // mounted
        try link("e:", "/Volumes/NoSuchVolume-\(UUID().uuidString)") // unplugged
        try link("d::", "/dev/rdisk7s2")                   // device, not a path
        try link("e::", "/dev/rdisk8s2")
        try link("z:", "/")
        return bottle
    }

    @Test func readsOnlyLetterDrives() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let drives = BottleDrives(bottle: bottle)

        #expect(drives.letters.keys.sorted() == ["C:", "D:", "E:", "Z:"])
        // The device entries are the trap: they are symlinks in the same
        // directory whose targets exist, so anything keying on "has a colon"
        // picks them up and hands back /dev/rdisk7s2 as a folder.
        #expect(drives.letters["D::"] == nil)
    }

    /// Two spellings of one place must compare equal whether or not the disk
    /// is plugged in -- the bug that made the first version of this test fail.
    @Test func theTextFormDoesNotDependOnWhatIsMounted() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let drives = BottleDrives(bottle: bottle)

        let present = drives.resolve(#"D:\SteamLibrary\steamapps"#)     // exists, a directory
        let absent  = drives.resolve(#"E:\SteamLibrary\steamapps"#)     // drive unplugged
        for r in [present, absent] {
            #expect(r.url?.path(percentEncoded: false).hasSuffix("/steamapps") == true,
                    "una barra final aquí depende de lo que esté montado")
        }
    }

    @Test func resolvesTheRelativeLinkToDriveC() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let drives = BottleDrives(bottle: bottle)

        let r = drives.resolve(#"C:\Program Files (x86)\Steam"#)
        #expect(r.isPresent)
        #expect(r.url?.path(percentEncoded: false).hasSuffix("/drive_c/Program Files (x86)/Steam") == true)
        // Read as an absolute path, "../drive_c" becomes "/drive_c".
        #expect(r.url?.path(percentEncoded: false).hasPrefix("/drive_c") == false)
    }

    @Test func unpluggedDriveIsOfflineNotMissing() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let drives = BottleDrives(bottle: bottle)

        let r = drives.resolve(#"E:\SteamLibrary\steamapps"#)
        #expect(r == .volumeOffline(r.url!))
        #expect(r.isOffline)
        #expect(!r.isPresent)
    }

    @Test func deletedFolderOnAMountedDriveIsMissing() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let drives = BottleDrives(bottle: bottle)

        let r = drives.resolve(#"D:\SteamLibrary\GoneForever"#)
        #expect(r == .missing(r.url!))
        // The distinction the interface acts on: this one really is gone,
        // the offline one is not.
        #expect(!r.isOffline)
        #expect(!r.isPresent)
    }

    @Test func unknownLetterSaysSo() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let drives = BottleDrives(bottle: bottle)

        #expect(drives.resolve(#"Q:\Games"#) == .noSuchDrive("Q:"))
        #expect(drives.resolve("/usr/local") == .noSuchDrive("/U"))
        #expect(drives.resolve("") == .noSuchDrive(""))
    }

    @Test func acceptsEitherSeparatorAndEitherCase() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let drives = BottleDrives(bottle: bottle)

        // Epic's manifests use backslashes; libraryfolders.vdf escapes them;
        // some tools hand back forward slashes. All three mean one place.
        let a = drives.resolve(#"d:\SteamLibrary\steamapps"#)
        let b = drives.resolve("D:/SteamLibrary/steamapps")
        let c = drives.resolve(#"D:\SteamLibrary/steamapps"#)
        #expect(a.isPresent && b.isPresent && c.isPresent)
        #expect(a.url == b.url && b.url == c.url)
    }

    @Test func rootOfDriveTakesALetterAnyWayItIsWritten() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let drives = BottleDrives(bottle: bottle)

        #expect(drives.root(ofDrive: "c") == drives.root(ofDrive: "C:"))
        #expect(drives.root(ofDrive: "z:") != nil)
    }

    @Test func aBottleWithNoDosdevicesIsEmptyRatherThanFatal() {
        let nowhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-bottle-\(UUID().uuidString)", isDirectory: true)
        let drives = BottleDrives(bottle: nowhere)
        #expect(drives.letters.isEmpty)
        #expect(drives.resolve(#"C:\Windows"#) == .noSuchDrive("C:"))
    }
}
