//
//  BundledControllerBusTests.swift
//  RaccoonBotTests
//
//  The controller-bus set: that it travels, that it is checked before it
//  runs, that it is offered to the right engine and refused the wrong one,
//  and that the row says what the engine holds. Nothing here installs into
//  anything: the script is only ever asked --status, of engines made in a
//  temporary directory, and never of one under ~/Applications.
//
//  Four files now, not three: winebus's unix half joined the set, it is a
//  Mach-O rather than a PE, and it lands in a directory of its own. Every
//  count and every list here says four, because a test that still says three
//  passes while the file nobody checked is the one that is missing.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import RaccoonBot

struct BundledControllerBusTests {

    /// The payload as it sits in the source tree, which is what the build
    /// copies into Resources -- the embedded MacGameVideoFix's own Resources,
    /// where the set travels flat beside the media set.
    private var payload: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RaccoonBot/Libs/mgvf/MacGameVideoFix.app/Contents/Resources")
    }

    /// The engine the set says it is for, read from the embedded stamp.
    private var stamp: BundledControllerBus.Stamp {
        get throws { try BundledControllerBus.verified(inDirectory: payload).stamp }
    }

    /// An engine shaped like a real one for the purposes of identity: a
    /// CFBundleVersion, a wine tag inside an ntdll.so, and -- when asked --
    /// the marker MacGameVideoFix leaves in a copy it made. Removed by the
    /// caller.
    private func engine(named name: String? = nil,
                        version: String? = "26.3.0.39832",
                        wine: String? = "wine-11.0-8726-g2e2f5fca349",
                        copiedFrom: String? = nil) throws -> URL {
        let f = FileManager.default
        // Its own directory, so an engine named literally as the stamp names
        // it cannot collide with another test's.
        let app = f.temporaryDirectory.appendingPathComponent("bus-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name ?? "Eng-\(UUID().uuidString).app", isDirectory: true)
        let cx = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT)
        try f.createDirectory(at: cx.appendingPathComponent("lib/wine/x86_64-windows"), withIntermediateDirectories: true)
        try f.createDirectory(at: cx.appendingPathComponent("lib/wine/x86_64-unix"), withIntermediateDirectories: true)
        if let version {
            try (["CFBundleVersion": version] as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        }
        if let wine {
            try Data("some bytes \(wine)\u{0}more bytes".utf8)
                .write(to: cx.appendingPathComponent("lib/wine/x86_64-unix/ntdll.so"))
        }
        if let copiedFrom {
            try Data(#"{"made_by": "MacGameVideoFix", "copied_from": "\#(copiedFrom)"}"#.utf8)
                .write(to: cx.appendingPathComponent("mgvf-origin.json"))
        }
        return app
    }

    /// The four destinations in an engine, so a test can leave the backups
    /// the script's --status reads. Three in x86_64-windows and one in
    /// x86_64-unix: the directory is the half of this set that cannot be
    /// guessed from the other three, so it is spelled out here rather than
    /// derived.
    private func destinations(in app: URL) -> [URL] {
        let lib = app.appendingPathComponent(SHARED_SUPPORT_COMPONENT).appendingPathComponent("lib/wine")
        let windows = lib.appendingPathComponent("x86_64-windows")
        return ["winebus.sys", "setupapi.dll", "ntoskrnl.exe", "hidclass.sys",
                "xinput1_1.dll", "xinput1_2.dll", "xinput1_3.dll", "xinput1_4.dll", "xinputuap.dll"]
            .map { windows.appendingPathComponent($0) }
            + [lib.appendingPathComponent("x86_64-unix/winebus.so")]
    }

    private func emptyDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nothing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: what travels

    /// The installer, the three files and the stamp are in the embedded
    /// application by name. This is what fails when the embedded copy is
    /// refreshed from a MacGameVideoFix build that left the set out.
    @Test func theSetTravelsInTheEmbeddedApplication() {
        for name in [BundledControllerBus.script, BundledControllerBus.stampFile] + BundledControllerBus.files {
            #expect(FileManager.default.fileExists(atPath: payload.appendingPathComponent(name).path(percentEncoded: false)),
                    "\(name) is not in the embedded application")
        }
    }

    /// Each of the three begins as a PE does, the unix half begins as a
    /// 64-bit Mach-O does, and the whole set reads. Checked apart rather than
    /// together: a .so that began with MZ would be a PE on its way into the
    /// engine's x86_64-unix directory, and the script copies what it is given.
    @Test func everyFileWeCarryIsTheKindOfBinaryItShouldBe() throws {
        let checked = try BundledControllerBus.verified(inDirectory: payload)
        #expect(checked.files.count == 10)
        for url in checked.files where url.lastPathComponent != BundledControllerBus.unixFile {
            #expect(BundledControllerBus.magic(of: url) == BundledControllerBus.peMagic,
                    "\(url.lastPathComponent) does not begin with MZ")
        }
        let unix = payload.appendingPathComponent(BundledControllerBus.unixFile)
        #expect(BundledControllerBus.magic(of: unix, count: 4) == BundledControllerBus.machOMagic)
        #expect(BundledControllerBus.magic(of: unix) != BundledControllerBus.peMagic,
                "the unix half is not a PE, and must not be checked as one")
    }

    /// The stamp names the ORIGIN, not the copy: a set for CrossOver.app
    /// serves every copy MacGameVideoFix made of it, through mgvf-origin.json.
    /// And it names the same engine the media set's stock stamp names --
    /// two copies of one fact, kept one fact, as the codec table and its
    /// licence file are.
    @Test func theStampNamesTheEngineTheMediaSetNames() throws {
        let ours = try stamp
        #expect(ours.app == "CrossOver.app")
        // Twenty now, and the whole list is named rather than a count, so a
        // build made from a shorter series fails here and not in a bottle.
        // That is not hypothetical: this application shipped a payload built
        // from mgvf-0009 for as long as it took somebody to read the stamp by
        // hand, and every per-title option added after it did nothing at all
        // in a bottle the application itself had installed.
        //
        // So when this fails after a payload refresh, the question to ask is
        // which of the two is behind -- and it is usually this line, because
        // the payload is the thing that just moved.
        #expect(ours.patches == "mgvf-0002 mgvf-0003 mgvf-0004 mgvf-0005 mgvf-0006 mgvf-0007 mgvf-0008"
                + " mgvf-0009 mgvf-0010 mgvf-0011 mgvf-0012 mgvf-0014 mgvf-0016 mgvf-0017 mgvf-0018"
                + " mgvf-0019 mgvf-0020 mgvf-0021 mgvf-0022 mgvf-0023 mgvf-0024 mgvf-0025")
        let media = try JSONDecoder().decode(BundledControllerBus.Stamp.self,
                                             from: Data(contentsOf: payload.appendingPathComponent("engine-built-for-stock.json")))
        #expect(ours.version == media.version)
        #expect(ours.wine == media.wine)
        #expect(ours.version != nil && ours.wine != nil)
    }

    /// The fourth file by name, and the fact about it this application cannot
    /// derive: the installer puts it in x86_64-unix, not beside the three PE
    /// files. Read from the script rather than asserted from memory -- the
    /// script is the one that writes into the engine.
    /// The PE list here against the PE list in the script that installs them.
    ///
    /// Not a count and not a remembered list: the script's own PE_NAMES is the
    /// thing that writes into an engine, so it is the thing to agree with. The
    /// set has grown three times -- mgvf-0011 added hidclass, mgvf-0012 added
    /// five xinput DLLs -- and each time the list here could have stayed as it
    /// was without a single test noticing, because everything else this file
    /// asks is asked about the files the list already names.
    @Test func theListAgreesWithTheScriptThatInstallsThem() throws {
        let script = try String(contentsOf: payload.appendingPathComponent(BundledControllerBus.script), encoding: .utf8)
        guard let range = script.range(of: #"PE_NAMES="[^"]*""#, options: .regularExpression) else {
            Issue.record("the installer no longer sets PE_NAMES; this test is reading for something that is gone")
            return
        }
        let separators: Set<Character> = [" ", "\n", "\t", "\\", "\""]
        let named = Set(script[range].split(whereSeparator: { separators.contains($0) })
                            .dropFirst()
                            .map { "engine-controller-" + $0 })
        #expect(named == Set(BundledControllerBus.peFiles))
    }

    @Test func theUnixHalfTravelsAndGoesToItsOwnDirectory() throws {
        #expect(BundledControllerBus.files.count == 10)
        #expect(BundledControllerBus.files.contains(BundledControllerBus.unixFile))
        #expect(BundledControllerBus.peFiles.contains(BundledControllerBus.unixFile) == false)
        let script = try String(contentsOf: payload.appendingPathComponent(BundledControllerBus.script), encoding: .utf8)
        #expect(script.contains(BundledControllerBus.unixFile))
        #expect(script.contains("lib/wine/x86_64-unix/winebus.so"))
    }

    // MARK: checked before it runs

    @Test func aFileThatIsNotThereIsNamedInTheFailure() throws {
        let empty = try emptyDirectory()
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(throws: BundledControllerBus.Failure.notBundled(BundledControllerBus.script)) {
            try BundledControllerBus.verified(inDirectory: empty)
        }
    }

    /// A file that is present but is not a PE is refused by name. The script
    /// would copy it into the engine without looking.
    @Test func aFileThatIsNotAWindowsBinaryIsRefusedByName() throws {
        let f = FileManager.default
        let mine = f.temporaryDirectory.appendingPathComponent("bus-\(UUID().uuidString)", isDirectory: true)
        try f.copyItem(at: payload, to: mine)
        defer { try? f.removeItem(at: mine) }
        try Data("not a PE at all".utf8).write(to: mine.appendingPathComponent("engine-controller-setupapi.dll"))
        #expect(throws: BundledControllerBus.Failure.notAPE("engine-controller-setupapi.dll")) {
            try BundledControllerBus.verified(inDirectory: mine)
        }
    }

    /// And the unix half is refused by its own name when it is not a Mach-O.
    /// It would otherwise pass the loop above by not being in it, and the
    /// script would copy whatever it is into the engine.
    @Test func aUnixHalfThatIsNotAMachOIsRefusedByName() throws {
        let f = FileManager.default
        let mine = f.temporaryDirectory.appendingPathComponent("bus-\(UUID().uuidString)", isDirectory: true)
        try f.copyItem(at: payload, to: mine)
        defer { try? f.removeItem(at: mine) }
        // MZ on purpose: a PE in the place of the unix half is exactly the
        // mistake a shared magic check would let through.
        try Data("MZ, which is the wrong kind of binary here".utf8)
            .write(to: mine.appendingPathComponent(BundledControllerBus.unixFile))
        #expect(throws: BundledControllerBus.Failure.notAMachO(BundledControllerBus.unixFile)) {
            try BundledControllerBus.verified(inDirectory: mine)
        }
    }

    /// A stamp that will not decode is a set that says nothing about its
    /// engine, and that is refused before the engine is even looked at.
    @Test func anUnreadableStampIsRefused() throws {
        let f = FileManager.default
        let mine = f.temporaryDirectory.appendingPathComponent("bus-\(UUID().uuidString)", isDirectory: true)
        try f.copyItem(at: payload, to: mine)
        defer { try? f.removeItem(at: mine) }
        try Data("{ this is not json".utf8).write(to: mine.appendingPathComponent(BundledControllerBus.stampFile))
        #expect(throws: BundledControllerBus.Failure.self) {
            try BundledControllerBus.verified(inDirectory: mine)
        }
    }

    // MARK: which engine

    /// Named as the stamp names it, at that version, on that wine.
    @Test func theEngineItWasBuiltForMatches() throws {
        let app = try engine(named: "CrossOver.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let identity = EngineIdentity(ofEngineAt: app)
        #expect(identity.app == "CrossOver.app")
        #expect(identity.copiedFrom == nil)
        #expect(try stamp.matches(identity))
    }

    /// Any other name, recording no origin, is some other engine -- even at
    /// the same version on the same wine.
    @Test func anEngineThatRecordsNoOriginIsMatchedByNameOnly() throws {
        let app = try engine()
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let identity = EngineIdentity(ofEngineAt: app)
        #expect(identity.copiedFrom == nil)
        #expect(try stamp.matches(identity) == false)
    }

    /// A copy MacGameVideoFix made records where it came from, and the stamp
    /// naming the original serves it -- the way both engine installers do.
    @Test func aCopyIsMatchedThroughWhatItWasCopiedFrom() throws {
        let app = try engine(copiedFrom: "CrossOver.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let identity = EngineIdentity(ofEngineAt: app)
        #expect(identity.copiedFrom == "CrossOver.app")
        #expect(identity.version == "26.3.0.39832")
        #expect(identity.wine == "wine-11.0-8726-g2e2f5fca349")
        #expect(try stamp.matches(identity))
    }

    /// The version alone does not identify an engine: a patched fork and
    /// stock CrossOver report the same one. A copy of something else, at the
    /// same version, is not served.
    @Test func aCopyOfAnotherApplicationWithTheSameVersionIsNotAMatch() throws {
        let app = try engine(copiedFrom: "Crossover_patched.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        #expect(try stamp.matches(EngineIdentity(ofEngineAt: app)) == false)
    }

    /// Onto a different wine the three do not degrade; they fail somewhere
    /// nobody would trace back here.
    @Test func aDifferentWineIsNotAMatch() throws {
        let app = try engine(wine: "wine-11.0-9000-gdeadbeef", copiedFrom: "CrossOver.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        #expect(try stamp.matches(EngineIdentity(ofEngineAt: app)) == false)
    }

    /// Unknown is not yes. An engine that will not say its version or its
    /// wine gets nothing.
    @Test func anEngineThatCannotSayIsNotAMatch() throws {
        let mute = try engine(version: nil, wine: nil, copiedFrom: "CrossOver.app")
        defer { try? FileManager.default.removeItem(at: mute.deletingLastPathComponent()) }
        #expect(try stamp.matches(EngineIdentity(ofEngineAt: mute)) == false)
        let noWine = try engine(wine: nil, copiedFrom: "CrossOver.app")
        defer { try? FileManager.default.removeItem(at: noWine.deletingLastPathComponent()) }
        #expect(try stamp.matches(EngineIdentity(ofEngineAt: noWine)) == false)
    }

    /// And a stamp that names nothing is never applied.
    @Test func aStampThatSaysNothingIsNeverApplied() throws {
        let vague = try JSONDecoder().decode(BundledControllerBus.Stamp.self, from: Data(#"{"patches":"x"}"#.utf8))
        let app = try engine(copiedFrom: "CrossOver.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        #expect(vague.matches(EngineIdentity(ofEngineAt: app)) == false)
    }

    /// An engine that is not there records no origin, as it says nothing else.
    @Test func anEngineThatIsNotThereRecordsNoOrigin() {
        #expect(EngineIdentity.origin(ofEngineAt: URL(fileURLWithPath: "/nowhere/None.app")) == nil)
    }

    // MARK: the verb, always

    /// The script's default verb is `install`, so a missing verb writes.
    /// Every call names one.
    @Test func theVerbIsAlwaysPassed() {
        let script = URL(fileURLWithPath: "/x/install-engine-controller.sh")
        #expect(BundledControllerBus.arguments(script: script, engine: "/e/A.app", verb: .install)
                == ["/x/install-engine-controller.sh", "/e/A.app", "install"])
        #expect(BundledControllerBus.arguments(script: script, engine: "/e/A.app", verb: .status)
                == ["/x/install-engine-controller.sh", "/e/A.app", "--status"])
        #expect(BundledControllerBus.arguments(script: script, engine: "/e/A.app", verb: .restore)
                == ["/x/install-engine-controller.sh", "/e/A.app", "--restore"])
    }

    /// A read declares itself read-only structurally, not only by its verb,
    /// and a write must not -- exercised with a stub that echoes its
    /// environment, the way MGVFRunnerTests does.
    @Test func aReadSetsTheValveAndAWriteDoesNot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bus-stub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let stub = dir.appendingPathComponent("install-fake.sh")
        try """
        #!/bin/bash
        echo "only=[${MGVF_STATUS_ONLY:-unset}] verb=[${2:-none}] frontend=[${MGVF_FRONTEND:-unset}]"
        echo absent
        """.write(to: stub, atomically: true, encoding: .utf8)

        let read = try BundledControllerBus.run(.status, onEngineAt: "/e/A.app", script: stub)
        #expect(read.stdout.contains("only=[1] verb=[--status] frontend=[RaccoonBot]"))
        #expect(read.state == .absent)
        #expect(read.exitCode == 0)

        for verb in [MGVFRunner.Verb.install, .restore] {
            let write = try BundledControllerBus.run(verb, onEngineAt: "/e/A.app", script: stub)
            #expect(write.stdout.contains("only=[unset] verb=[\(verb.argument ?? "install")]"), "for \(verb)")
        }
    }

    // MARK: reading the answer

    /// The words the real script prints, and what each one means. Its two
    /// success lines for a write happen to contain a state word or none, and
    /// the reader must not mistake "restored 3 of 3" for a state.
    @Test func theScriptsOwnWordsAreRead() {
        #expect(MGVFRunner.stateWord(in: "installed\n") == .installed)
        #expect(MGVFRunner.stateWord(in: "broken\n") == .broken)
        #expect(MGVFRunner.stateWord(in: "absent\n") == .absent)
        #expect(MGVFRunner.stateWord(in: "restored 3 of 3\n") == nil)
        #expect(MGVFRunner.stateWord(in: "nothing to restore\n") == nil)
        #expect(MGVFRunner.stateWord(in: "note: winebus.sys is already this build; no backup taken\n") == nil)
    }

    /// The real script, asked --status of engines in a temporary directory.
    /// The script decides by the presence of the three backups, and only
    /// all three together are "installed".
    @Test func theRealScriptReportsWhatAnEngineHolds() throws {
        let app = try engine(copiedFrom: "CrossOver.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let path = app.path(percentEncoded: false)
        #expect(BundledControllerBus.status(ofEngineAt: path, from: payload) == .absent)

        let backups = destinations(in: app).map { $0.appendingPathExtension("mgvf-stock") }
        try Data("the original".utf8).write(to: backups[0])
        #expect(BundledControllerBus.status(ofEngineAt: path, from: payload) == .broken)

        for backup in backups.dropFirst() { try Data("the original".utf8).write(to: backup) }
        #expect(BundledControllerBus.status(ofEngineAt: path, from: payload) == .installed)
    }

    /// Something that is not a CrossOver at all is not "absent"; it is an
    /// engine that cannot be asked, and the answer is nil.
    @Test func somethingThatIsNotAnEngineCannotBeAsked() throws {
        let dir = try emptyDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(BundledControllerBus.status(ofEngineAt: dir.path(percentEncoded: false), from: payload) == nil)
    }

    // MARK: the row

    @Test func withoutAnEngineThereIsNothingToOffer() {
        let status = ControllerBusStatus.read(engineAppPath: nil, payload: payload)
        #expect(status.offer == .noEngine)
        #expect(status.state == nil)
        #expect(status.wantsAction(enabled: true) == nil)
        #expect(status.light(enabled: true) == .quiet)
        #expect(status.summary(enabled: true).contains("No engine yet"))
    }

    /// A build without the set says so, names what is missing, and the
    /// switch is not offered as a promise nothing can keep.
    @Test func aBuildWithoutTheSetSaysSo() throws {
        let app = try engine(copiedFrom: "CrossOver.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let empty = try emptyDirectory()
        defer { try? FileManager.default.removeItem(at: empty) }
        let status = ControllerBusStatus.read(engineAppPath: app.path(percentEncoded: false), payload: empty)
        #expect(status.isBundled == false)
        #expect(status.summary(enabled: true).contains(BundledControllerBus.script))
        #expect(status.light(enabled: true) == .warning)
    }

    /// A copy of the engine the set was built for is offered it, and with
    /// nothing in it yet the row asks to install when the switch is on and
    /// asks nothing when it is off.
    @Test func aMatchingEngineWithNothingInItIsOffered() throws {
        let app = try engine(copiedFrom: "CrossOver.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let status = ControllerBusStatus.read(engineAppPath: app.path(percentEncoded: false), payload: payload)
        #expect(status.offer == .offered)
        #expect(status.state == .absent)
        #expect(status.tellsTheBus == false)
        #expect(status.wantsAction(enabled: true) == .install)
        #expect(status.light(enabled: true) == .warning)
        #expect(status.wantsAction(enabled: false) == nil)
        #expect(status.light(enabled: false) == .good)
        #expect(status.summary(enabled: false).contains("stock controller bus"))
    }

    /// Another engine is refused with both names in the sentence, and what
    /// it holds is still read -- somebody may have put the set there by hand.
    @Test func anotherEngineIsNotOfferedButIsStillRead() throws {
        let app = try engine(version: "27.0.0.40921", copiedFrom: "CrossOver.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let status = ControllerBusStatus.read(engineAppPath: app.path(percentEncoded: false), payload: payload)
        guard case .wrongEngine(let wanted, let found) = status.offer else {
            Issue.record("offered to \(status.offer)")
            return
        }
        #expect(wanted == "CrossOver.app 26.3.0.39832")
        #expect(found.contains("27.0.0.40921"))
        #expect(status.state == .absent)
        #expect(status.wantsAction(enabled: true) == nil)
        #expect(status.light(enabled: true) == .quiet)
        #expect(status.summary(enabled: true).contains("not offered"))
    }

    /// The decisions for an engine that holds the set, without an engine to
    /// hold it: the script's record and the binary's own word, together.
    @Test func whatTheRowSaysAboutAnInstalledSet() {
        let whole = ControllerBusStatus(offer: .offered, state: .installed, tellsTheBus: true)
        #expect(whole.wantsAction(enabled: true) == nil)
        #expect(whole.light(enabled: true) == .good)
        #expect(whole.summary(enabled: true).contains("keeps rumble"))
        #expect(whole.wantsAction(enabled: false) == .remove)
        #expect(whole.light(enabled: false) == .warning)

        // Recorded as installed, and the winebus in place does not say so:
        // the two disagree, and the row asks for the files to go in again.
        let silent = ControllerBusStatus(offer: .offered, state: .installed, tellsTheBus: false)
        #expect(silent.wantsAction(enabled: true) == .install)
        #expect(silent.light(enabled: true) == .warning)
        #expect(silent.summary(enabled: true).contains("does not name the bus"))

        // Half of it: removed first, whatever the switch says.
        let half = ControllerBusStatus(offer: .offered, state: .broken, tellsTheBus: false)
        #expect(half.wantsAction(enabled: true) == .remove)
        #expect(half.wantsAction(enabled: false) == .remove)
        #expect(half.light(enabled: true) == .warning)

        // Could not be asked: never good.
        let unasked = ControllerBusStatus(offer: .offered, state: nil, tellsTheBus: false)
        #expect(unasked.wantsAction(enabled: true) == nil)
        #expect(unasked.light(enabled: true) == .warning)
        #expect(unasked.summary(enabled: true).contains("could not be asked"))
    }

    // MARK: what a failure says

    @Test func theFailuresNameWhatWentWrong() {
        #expect(BundledControllerBus.Failure.notBundled("engine-controller-winebus.sys").errorDescription?
                    .contains("engine-controller-winebus.sys") == true)
        #expect(BundledControllerBus.Failure.notAPE("engine-controller-ntoskrnl.exe").errorDescription?
                    .contains("MZ") == true)
        #expect(BundledControllerBus.Failure.notAMachO(BundledControllerBus.unixFile).errorDescription?
                    .contains(BundledControllerBus.unixFile) == true)
        #expect(BundledControllerBus.Failure.notAMachO(BundledControllerBus.unixFile).errorDescription?
                    .contains("Mach-O") == true)
        let wrong = BundledControllerBus.Failure.wrongEngine(wanted: "CrossOver.app 26.3.0.39832",
                                                             found: "Other.app 27.0.0.1")
        #expect(wrong.errorDescription?.contains("CrossOver.app 26.3.0.39832") == true)
        #expect(wrong.errorDescription?.contains("Other.app 27.0.0.1") == true)
        #expect(BundledControllerBus.Failure.refused("a wine bottle is running").errorDescription
                == "a wine bottle is running")
    }

    /// Installing into the wrong engine is refused here, before the script is
    /// asked, with both engines named -- and nothing is written.
    @Test func installingIntoTheWrongEngineIsRefusedBeforeTheScriptRuns() throws {
        let app = try engine(copiedFrom: "Crossover_patched.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        #expect(throws: BundledControllerBus.Failure.self) {
            try BundledControllerBus.install(intoEngineAt: app.path(percentEncoded: false), from: payload)
        }
        for backup in destinations(in: app).map({ $0.appendingPathExtension("mgvf-stock") }) {
            #expect(!FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)))
        }
    }
}
