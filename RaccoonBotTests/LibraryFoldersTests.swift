//
//  LibraryFoldersTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// One folder, once, whatever the bookmarks say.
struct LibraryFoldersTests {
    @Test func theSameFolderTwiceIsOnce() {
        let a = URL(fileURLWithPath: "/Volumes/X/SteamLibrary/steamapps")
        let b = URL(fileURLWithPath: "/Volumes/X/SteamLibrary/steamapps/")
        #expect(uniqueLibraryFolders([a, b, a]).count == 1)
    }

    @Test func differentFoldersStay() {
        let a = URL(fileURLWithPath: "/Volumes/X/A/steamapps")
        let b = URL(fileURLWithPath: "/Volumes/X/B/steamapps")
        #expect(uniqueLibraryFolders([a, b]).count == 2)
    }

    /// First occurrence wins, so the order somebody added them in is kept.
    @Test func orderIsKept() {
        let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/b")
        #expect(uniqueLibraryFolders([b, a, b]).map(\.path) == ["/b", "/a"])
    }
}
