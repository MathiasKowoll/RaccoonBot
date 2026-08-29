//
//  BundledCodecsTests.swift
//  RaccoonBotTests
//

import Foundation
import Testing
@testable import RaccoonBot

struct BundledCodecsTests {

    /// The payload as it sits in the source tree, which is what the build
    /// copies into Resources. Reading it here rather than out of a built
    /// bundle means these tests check the files that will ship, not a copy
    /// of them made by the same step under test.
    private var payload: URL {
        URL(fileURLWithPath: #filePath)          // .../RaccoonBotTests/BundledCodecsTests.swift
            .deletingLastPathComponent()          // .../RaccoonBotTests
            .deletingLastPathComponent()          // .../RaccoonBot (repo)
            .appendingPathComponent("RaccoonBot/Libs/codecs")
    }

    /// An engine shaped like a real one, with only the directory that
    /// generation actually has.
    private func engine(version: String, dir: String) throws -> URL {
        let f = FileManager.default
        let app = f.temporaryDirectory.appendingPathComponent("Eng-\(UUID().uuidString).app", isDirectory: true)
        try f.createDirectory(at: app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
                                .appendingPathComponent(dir).appendingPathComponent("gstreamer-1.0"),
                              withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleVersion": version]
        try (plist as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    private func copyOfPayload() throws -> URL {
        let to = FileManager.default.temporaryDirectory
            .appendingPathComponent("codecs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: payload, to: to)
        return to
    }

    // MARK: the table and the notices have to agree

    /// The hashes compiled into the application and the hashes in the file we
    /// redistribute beside the binaries are two copies of one fact. This is
    /// the check that keeps them one fact.
    @Test func theTableAgreesWithTheLicenceFile() throws {
        let text = try String(contentsOf: payload.appendingPathComponent(BundledCodecs.licenceFile),
                              encoding: .utf8)
        var recorded: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("| `") {
            let cells = line.split(separator: "|").map {
                $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "`", with: "")
            }
            guard cells.count == 3, cells[0].contains(".dylib") else { continue }
            recorded[URL(fileURLWithPath: cells[0]).lastPathComponent] = cells[2]
        }
        #expect(recorded.count == BundledCodecs.items.count)
        for item in BundledCodecs.items {
            #expect(recorded[item.name] == item.sha256, "\(item.name) disagrees with the licence table")
        }
    }

    /// Redistributing these is what obliges us to carry the notices, so their
    /// absence is a defect and not an untidiness.
    @Test func theNoticesTravelWithTheBinaries() throws {
        let licences = payload.appendingPathComponent(BundledCodecs.licenceFile)
        #expect(FileManager.default.fileExists(atPath: licences.path(percentEncoded: false)))
        let text = try String(contentsOf: licences, encoding: .utf8)
        #expect(text.contains("LGPL"))
    }

    // MARK: what we carry

    @Test func everyFileWeCarryIsTheFileTheTableNames() throws {
        let checked = try BundledCodecs.verified(inDirectory: payload)
        #expect(checked.count == 12)
    }

    @Test func aFileThatIsNotThereIsNamedInTheFailure() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("nothing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(throws: BundledCodecs.Failure.notBundled("libgstlibav.dylib")) {
            try BundledCodecs.verified(inDirectory: empty)
        }
    }

    // MARK: installing

    @Test func a26EngineGetsThePluginsAndTheLibrariesInTheirOwnPlaces() throws {
        let app = try engine(version: "26.3.0.39832", dir: "lib64")
        defer { try? FileManager.default.removeItem(at: app) }
        let installed = try BundledCodecs.install(intoEngineAt: app.path(percentEncoded: false), from: payload)
        #expect(installed.copied.count == 12)

        let lib64 = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT).appendingPathComponent("lib64")
        let f = FileManager.default
        for item in BundledCodecs.items {
            let where_ = item.isPlugin ? lib64.appendingPathComponent("gstreamer-1.0") : lib64
            #expect(f.fileExists(atPath: where_.appendingPathComponent(item.name).path(percentEncoded: false)),
                    "\(item.name) is not where it belongs")
        }
    }

    /// The whole reason the destination is asked of the engine. A lib64 we
    /// invented on a 27 would not merely be unused: its own `wine` points
    /// GST_PLUGIN_SYSTEM_PATH at whichever directory exists and replaces the
    /// value, so three plugins in a lib64 would hide the twenty it ships.
    @Test func a27EngineNeverReceivesALib64() throws {
        let app = try engine(version: "27.0.0.40921", dir: "lib/x86_64")
        defer { try? FileManager.default.removeItem(at: app) }
        try BundledCodecs.install(intoEngineAt: app.path(percentEncoded: false), from: payload)

        let shared = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
        #expect(!FileManager.default.fileExists(atPath: shared.appendingPathComponent("lib64").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: shared
            .appendingPathComponent("lib/x86_64/gstreamer-1.0/libgstlibav.dylib").path(percentEncoded: false)))
    }

    /// A payload wrong in one file is a wrong payload, and half of it inside
    /// an engine is worse than none: the engine's own plugins would then be
    /// loaded beside libraries from somewhere else.
    @Test func oneChangedFileStopsTheInstallBeforeAnythingIsWritten() throws {
        let mine = try copyOfPayload()
        defer { try? FileManager.default.removeItem(at: mine) }
        let victim = mine.appendingPathComponent("libz.1.dylib")
        let handle = try FileHandle(forWritingTo: victim)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x00]))
        try handle.close()

        let app = try engine(version: "26.3.0.39832", dir: "lib64")
        defer { try? FileManager.default.removeItem(at: app) }
        #expect(throws: BundledCodecs.Failure.self) {
            try BundledCodecs.install(intoEngineAt: app.path(percentEncoded: false), from: mine)
        }

        // libgstlibav sorts first in the table and would have been copied by
        // now if the payload were checked file by file as it was written.
        let plugins = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
            .appendingPathComponent("lib64/gstreamer-1.0")
        let left = try FileManager.default.contentsOfDirectory(atPath: plugins.path(percentEncoded: false))
        #expect(left.isEmpty, "the engine was written into before the payload had been checked: \(left)")
    }

    @Test func whatWasThereIsKeptAsOrigExactlyOnce() throws {
        let app = try engine(version: "26.3.0.39832", dir: "lib64")
        defer { try? FileManager.default.removeItem(at: app) }
        let plugins = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
            .appendingPathComponent("lib64/gstreamer-1.0")
        let theirs = plugins.appendingPathComponent("libgstlibav.dylib")
        try Data("the engine's own".utf8).write(to: theirs)

        try BundledCodecs.install(intoEngineAt: app.path(percentEncoded: false), from: payload)
        let orig = try String(contentsOf: theirs.appendingPathExtension("orig"), encoding: .utf8)
        #expect(orig == "the engine's own")

        // Twice must not bury it under a copy of ours.
        try BundledCodecs.install(intoEngineAt: app.path(percentEncoded: false), from: payload)
        let stillTheirs = try String(contentsOf: theirs.appendingPathExtension("orig"), encoding: .utf8)
        #expect(stillTheirs == "the engine's own")
    }

    @Test func anEngineWithNoPluginDirectoryIsRefusedRatherThanGivenOne() throws {
        let f = FileManager.default
        let app = f.temporaryDirectory.appendingPathComponent("Eng-\(UUID().uuidString).app", isDirectory: true)
        try f.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try (["CFBundleVersion": "26.3.0.39832"] as NSDictionary)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        defer { try? f.removeItem(at: app) }
        #expect(throws: BundledCodecs.Failure.self) {
            try BundledCodecs.install(intoEngineAt: app.path(percentEncoded: false), from: payload)
        }
    }
}
