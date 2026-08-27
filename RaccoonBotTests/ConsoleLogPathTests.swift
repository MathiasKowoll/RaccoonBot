//
//  ConsoleLogPathTests.swift
//  RaccoonBotTests
//
//  Where the debug log goes.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

struct ConsoleLogPathTests {

    @Test func theFileIsNamedForTheApplication() {
        #expect(Console.logFileName == "RaccoonBot.log.txt")
        #expect(Console.logPathVariable == "RaccoonBotLogPath")
    }

    /// Beside the application while developing, which is where you look.
    /// From /Applications it goes to Application Support instead: that folder
    /// is not a place to leave a text file, and writing there needs an
    /// administrator.
    @Test func anInstalledCopyDoesNotWriteIntoApplications() {
        let dir = Console.defaultLogDirectory.path(percentEncoded: false)
        #expect(dir != "/Applications")
        #expect(!dir.hasPrefix("/Applications/"))
        // And wherever it landed, it is somewhere that can be written.
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir, isDirectory: &isDirectory) {
            #expect(isDirectory.boolValue)
        }
    }

    @Test func theDefaultIsAFileInsideThatDirectory() {
        #expect(Console.logURL.deletingLastPathComponent().path(percentEncoded: false)
                == Console.defaultLogDirectory.path(percentEncoded: false))
        #expect(Console.logURL.lastPathComponent == Console.logFileName)
    }

    /// Writing the log has to make its directory. Application Support does not
    /// come with a RaccoonBot folder on a machine that has never had one.
    @Test func savingCreatesTheDirectoryItNeeds() throws {
        let f = FileManager.default
        let deep = f.temporaryDirectory
            .appendingPathComponent("log-\(UUID().uuidString)/one/two", isDirectory: true)
            .appendingPathComponent(Console.logFileName)
        defer {
            try? f.removeItem(at: deep.deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent())
        }
        let c = Console()
        c.enableLogFile = true
        c.log("something worth keeping")
        c.saveLogs(to: deep)
        #expect(f.fileExists(atPath: deep.path(percentEncoded: false)))
        #expect(try String(contentsOf: deep, encoding: .utf8).contains("something worth keeping"))
    }

    /// The same run twice replaces the file rather than appending, which is
    /// the existing behaviour and worth pinning: two captures in a row do not
    /// silently merge.
    @Test func aSecondSaveReplacesTheFirst() throws {
        let f = FileManager.default
        let url = f.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString).txt")
        defer { try? f.removeItem(at: url) }
        let c = Console()
        c.enableLogFile = true
        c.log("first")
        c.saveLogs(to: url)
        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after.contains("first"))
        #expect(after.components(separatedBy: "first").count == 2, "it appended instead of replacing")
    }
}
