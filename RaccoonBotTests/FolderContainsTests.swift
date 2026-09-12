//
//  FolderContainsTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Telling a Mac game from a Windows one without walking the whole disk.
struct FolderContainsTests {

    private func tree(_ paths: [String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("folders-\(UUID().uuidString)")
        for p in paths {
            let url = root.appendingPathComponent(p)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        return root
    }

    @Test func findsWhatIsAtTheTop() throws {
        let root = try tree(["Game.exe", "readme.txt"]); defer { try? FileManager.default.removeItem(at: root) }
        #expect(folderContains(extensions: ["exe", "app"], at: root) == ["exe"])
        #expect(!getIsNative(fromURL: root))
    }

    @Test func aBundleAndNoExecutableIsNative() throws {
        let root = try tree(["Game.app/Contents/MacOS/Game", "data/pak01.pak"]); defer { try? FileManager.default.removeItem(at: root) }
        #expect(getIsNative(fromURL: root))
    }

    /// A bundle is a package: what is inside it is not walked, so a `.exe`
    /// shipped inside one does not make a Mac game a Windows one.
    @Test func insideABundleDoesNotCount() throws {
        let root = try tree(["Game.app/Contents/Resources/tool.exe"]); defer { try? FileManager.default.removeItem(at: root) }
        #expect(getIsNative(fromURL: root))
    }

    @Test func findsWhatIsAFewLevelsDown() throws {
        let root = try tree(["Bin/Win64/Game.exe"]); defer { try? FileManager.default.removeItem(at: root) }
        #expect(folderContains(extensions: ["exe"], at: root) == ["exe"])
    }

    /// The point of the change: it does not go deeper than it must. Below the
    /// limit is where the minutes were spent.
    @Test func stopsAtTheDepthLimit() throws {
        let root = try tree(["a/b/c/d/e/Deep.exe"]); defer { try? FileManager.default.removeItem(at: root) }
        #expect(folderContains(extensions: ["exe"], at: root, maxDepth: 2).isEmpty, "five levels down is not looked at")
        #expect(folderContains(extensions: ["exe"], at: root, maxDepth: 6) == ["exe"])
    }

    /// The defect that froze the window: a depth-first walk takes the first
    /// subfolder before the rest of the top level, so an executable sitting
    /// beside a big folder was reached only after everything inside it. In
    /// breadth, the whole top level is seen first.
    @Test func theTopLevelIsSeenBeforeAnythingBelowIt() throws {
        var paths = ["Game.exe"]
        for i in 0..<300 { paths.append("aaa_data/file\(i).pak") }        // sorts first
        let root = try tree(paths); defer { try? FileManager.default.removeItem(at: root) }
        #expect(folderContains(extensions: ["exe"], at: root, maxFolders: 1) == ["exe"],
                "found without opening the big folder at all")
    }

    /// And it will not open an unbounded number of folders looking.
    @Test func itStopsAfterSoManyFolders() throws {
        var paths: [String] = []
        for i in 0..<40 { paths.append("dir\(i)/inner/Game.exe") }
        let root = try tree(paths); defer { try? FileManager.default.removeItem(at: root) }
        #expect(folderContains(extensions: ["exe"], at: root, maxDepth: 3, maxFolders: 3).isEmpty)
        #expect(folderContains(extensions: ["exe"], at: root, maxDepth: 3, maxFolders: 200) == ["exe"])
    }

    /// And it stops as soon as the question is answered, rather than
    /// finishing the walk.
    @Test func stopsOnceEveryAnswerIsIn() throws {
        let root = try tree(["Game.exe", "Game.app/Contents/MacOS/Game"]); defer { try? FileManager.default.removeItem(at: root) }
        #expect(folderContains(extensions: ["exe", "app"], at: root) == ["exe", "app"])
        #expect(!getIsNative(fromURL: root), "an .exe beside a bundle is a Windows game")
    }

    @Test func aFolderThatIsNotThereIsNotAGame() {
        let gone = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gone-\(UUID().uuidString)")
        #expect(folderContains(extensions: ["exe"], at: gone).isEmpty)
        #expect(!getIsNative(fromURL: gone))
    }

    @Test func theOldSingleExtensionCallStillWorks() throws {
        let root = try tree(["Game.exe"]); defer { try? FileManager.default.removeItem(at: root) }
        #expect(folderContainsFile(withExtension: "exe", at: root))
        #expect(!folderContainsFile(withExtension: "app", at: root))
    }

    /// The defect that cost 192 seconds on one game: the executable was
    /// found in the folder's own listing, and the pass kept going anyway
    /// because it had also been asked for a bundle that was not there.
    @Test func anExecutableSettlesItWithoutLookingForABundle() throws {
        var paths = ["Game.exe"]
        for i in 0..<200 { paths.append("data/deep/file\(i).pak") }
        let root = try tree(paths); defer { try? FileManager.default.removeItem(at: root) }
        #expect(!getIsNative(fromURL: root))
        // One folder opened: the game's own. Nothing below it was read.
        #expect(folderContains(extensions: ["exe"], at: root, maxFolders: 1) == ["exe"])
    }
}

/// The answer, remembered between refreshes.
struct NativeKindTests {
    /// Its own store per test: these run in parallel, and the map is read,
    /// changed and written back whole.
    private let store = UserDefaults(suiteName: "NativeKindTests-\(UUID().uuidString)")!

    private func folder(_ name: String) throws -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("native-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test func theSecondAskDoesNotMeasureAgain() throws {
        let f = try folder("cache"); defer { try? FileManager.default.removeItem(at: f) }
        var measured = 0
        let count: (URL) -> Bool = { _ in measured += 1; return true }
        #expect(NativeKind.isNative(folder: f, measure: count, store: store))
        #expect(NativeKind.isNative(folder: f, measure: count, store: store))
        #expect(NativeKind.isNative(folder: f, measure: count, store: store))
        #expect(measured == 1, "worked out once, read back twice")
    }

    @Test func aChangedFolderIsAskedAboutAgain() throws {
        let f = try folder("changed"); defer { try? FileManager.default.removeItem(at: f) }
        var measured = 0
        let count: (URL) -> Bool = { _ in measured += 1; return false }
        _ = NativeKind.isNative(folder: f, measure: count, store: store)
        // Something lands in the folder: its modification date moves.
        FileManager.default.createFile(atPath: f.appendingPathComponent("Game.app").path, contents: Data())
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: f.path)
        _ = NativeKind.isNative(folder: f, measure: count, store: store)
        #expect(measured == 2)
    }

    @Test func twoFoldersAreRememberedApart() throws {
        let a = try folder("a"), b = try folder("b")
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(NativeKind.isNative(folder: a, measure: { _ in true }, store: store))
        #expect(!NativeKind.isNative(folder: b, measure: { _ in false }, store: store))
        #expect(NativeKind.isNative(folder: a, measure: { _ in false }, store: store), "a's own answer, not b's")
    }
}
