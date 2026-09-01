//
//  BlockedGenerationTests.swift
//  RaccoonBotTests
//

import Foundation
import Testing
@testable import RaccoonBot

struct BlockedGenerationTests {

    private func engine(version: String) throws -> URL {
        let f = FileManager.default
        let app = f.temporaryDirectory.appendingPathComponent("Eng-\(UUID().uuidString).app")
        try f.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try (["CFBundleVersion": version] as NSDictionary)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    @Test func twentySevenIsRefusedAndSaysWhy() throws {
        let app = try engine(version: "27.0.0.40921")
        defer { try? FileManager.default.removeItem(at: app) }
        let refusal = try #require(EngineLayout.refusal(for: app))
        #expect(refusal.contains("27"))
        #expect(refusal.contains("26"), "the refusal should say what to use instead")
    }

    @Test func twentySixIsAllowed() throws {
        let app = try engine(version: "26.3.0.39832")
        defer { try? FileManager.default.removeItem(at: app) }
        #expect(EngineLayout.refusal(for: app) == nil)
    }

    /// Not knowing is not permission. The version is how the layout, the codec
    /// directory and the toolkit destination are all decided; proceeding
    /// without it means guessing three things at once.
    @Test func anEngineThatWillNotSayIsRefusedToo() throws {
        let f = FileManager.default
        let app = f.temporaryDirectory.appendingPathComponent("Eng-\(UUID().uuidString).app")
        try f.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? f.removeItem(at: app) }
        #expect(EngineLayout.refusal(for: app) != nil)
    }

    /// The block is a judgement, not a capability gap: the layout for 27 is
    /// known and correct, and lifting the block must not require rediscovering
    /// it. If this ever fails, somebody has confused the two.
    @Test func theLayoutForTwentySevenIsStillKnown() throws {
        let app = try engine(version: "27.0.0.40921")
        defer { try? FileManager.default.removeItem(at: app) }
        #expect(EngineLayout.of(app) == .cx27)
        #expect(EngineLayout.cx27.moltenVKRoot(arch: "x86_64") == "lib/x86_64")
        #expect(EngineLayout.cx26.moltenVKRoot(arch: "x86_64") == "lib64")
    }
}
