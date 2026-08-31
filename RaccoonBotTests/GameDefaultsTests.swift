//
//  GameDefaultsTests.swift
//  RaccoonBotTests
//

import Foundation
import Testing
@testable import RaccoonBot

@Suite(.serialized)
struct GameDefaultsTests {

    private func scratchKey() -> String {
        namespacedKey("GameOptionsTest", UUID().uuidString)
    }

    private func clean(_ key: String) { deleteUsrDefOption(key: key) }

    /// What the owner asked a new title to start with.
    @Test func aFreshTitleGetsTheHudAndTheFourthToolkit() {
        let data = GameDefaults.freshOptions()
        #expect(data.mtlHudEnabled == true)
        #expect(data.mtlHudDetail == MetalHudDetail.fpsOnly.rawValue)
        #expect(data.cxGraphicsBackend == "d3dmetal4")
    }

    /// The backend string has to be the one the launcher switches on, or the
    /// engine gets generation 3 while the interface says 4 -- which is the
    /// whole defect this exists to close.
    @Test func theBackendIsSpelledTheWayTheLauncherReadsIt() {
        #expect(GameDefaults.freshOptions().cxGraphicsBackend == newestD3DMetalBackend)
    }

    /// A field added later must arrive with its own default rather than nil,
    /// which is why this is built from GameOptions instead of a hand-written
    /// list of fields.
    @Test func everythingElseCarriesItsOwnDefault() {
        let data = GameDefaults.freshOptions()
        #expect(data.wineMSync != nil)
        #expect(data.advertiseAVX != nil)
        #expect(data.enableSDL != nil)
        #expect(data.vulkanLib != nil)
    }

    /// Every field the struct declares has to survive the round trip through
    /// GameOptions and back. Three did not: mtlHudDetail, mtlHudOpacity and
    /// mtlHudAlignment were declared, read on the way in, and dropped on the
    /// way out -- so the HUD's detail level, opacity and alignment were reset
    /// by every save. This is the test that would have caught it.
    @Test func everyFieldSurvivesTheRoundTrip() {
        let mine = GameOptions()
        mine.mtlHudEnabled = true
        mine.mtlHudDetail = MetalHudDetail.extended.rawValue
        mine.mtlHudOpacity = 0.42
        mine.mtlHudAlignment = MetalHudAlignment.allCases.first(where: { $0 != .byDefault })!.rawValue

        let saved = GameOptionsData(data: mine)
        let restored = GameOptions()
        restored.set(data: saved)

        #expect(restored.mtlHudDetail == MetalHudDetail.extended.rawValue)
        #expect(restored.mtlHudOpacity == 0.42)
        #expect(restored.mtlHudAlignment == mine.mtlHudAlignment)
    }

    /// No construction may produce a backend the picker cannot show.
    ///
    /// `"d3dmetal"` was the default and is not one of the six options, so a
    /// title carrying it displayed as D3Dmetal4 in the panel, was read as
    /// generation 3 by the launcher, and had its saved Metal 4 choice dropped
    /// because the environment only writes D3DM_MTL4 for `"d3dmetal4"`. Panel,
    /// disk and launch gave three different answers to one question.
    @Test func nothingProducesABackendThePickerCannotShow() {
        let offered = Set(cxGraphicsBackend.map(\.id))
        #expect(offered.contains(GameOptions().cxGraphicsBackend))
        // and the Reset button, which rebuilds from a bare GameOptions
        let reset = GameOptions()
        reset.set(data: GameOptionsData(data: GameOptions()))
        #expect(offered.contains(reset.cxGraphicsBackend))
        #expect(offered.contains(GameDefaults.freshOptions().cxGraphicsBackend ?? ""))
    }

    /// A seeded title must not run D3DMetal 4 with Metal 4 switched off, which
    /// is the opposite of what the panel produces for the same choice.
    @Test func aSeededTitleIsInternallyConsistent() {
        let data = GameDefaults.freshOptions()
        #expect(data.cxGraphicsBackend == newestD3DMetalBackend)
        #expect(data.d3dMtl4Enabled == (newestD3DMetalBackend == "d3dmetal4" && OSVersion >= 27))
        let options = GameOptions()
        options.set(data: data)
        let rendered = getInlineEnvs(from: options)
        #expect(rendered.contains("D3DM_MTL4=\(OSVersion >= 27 ? "1" : "0")"))
    }

    // MARK: the legacy backend

    /// The twenty migrated records. `"d3dmetal"` is not one of the six the
    /// picker offers, and it was reaching the launcher as generation 3 while
    /// the panel displayed D3Dmetal4.
    @Test func aLegacyBackendBecomesTheFourthToolkit() {
        #expect(pickableBackend("d3dmetal") == newestD3DMetalBackend)
        #expect(pickableBackend(nil) == "auto")
        #expect(pickableBackend("") == "auto")
    }

    /// A real choice is never rewritten. Somebody who picked DXVK keeps DXVK.
    @Test func aBackendThePickerOffersIsLeftAlone() {
        for offered in cxGraphicsBackend.map(\.id) {
            #expect(pickableBackend(offered) == offered, "rewrote \(offered)")
        }
    }

    /// Ten of the twenty carry Metal 4 saved true. Folding the backend is what
    /// finally lets that saved choice reach the command line.
    @Test func aFoldedRecordWithMetalFourSavedReachesTheCommandLine() throws {
        let json = #"{"cxGraphicsBackend":"d3dmetal","d3dMtl4Enabled":true}"#
        let data = try JSONDecoder().decode(GameOptionsData.self, from: Data(json.utf8))
        let options = GameOptions()
        options.set(data: data)
        #expect(options.cxGraphicsBackend == newestD3DMetalBackend)
        let rendered = getInlineEnvs(from: options)
        #expect(rendered.contains("D3DM_MTL4=\(OSVersion >= 27 ? "1" : "0")"))
        #expect(rendered.contains("D3DM_ENABLE_METALFX=1"))
    }

    /// Folding repairs the backend and nothing else. Six records carry Metal 4
    /// off; once a title has a configuration file, that file is respected, and
    /// a switch somebody could have set is not overruled by a repair to a value
    /// they never could.
    @Test func foldingRepairsTheBackendAndLeavesTheRestAlone() throws {
        let json = #"{"cxGraphicsBackend":"d3dmetal","d3dMtl4Enabled":false}"#
        let data = try JSONDecoder().decode(GameOptionsData.self, from: Data(json.utf8))
        let options = GameOptions()
        options.set(data: data)
        #expect(options.cxGraphicsBackend == newestD3DMetalBackend)
        #expect(options.d3dMtl4Enabled == false, "a saved switch was overruled")
    }

    /// And where the file says nothing, the computed default still applies.
    @Test func anAbsentMetalFourStillGetsTheComputedDefault() throws {
        let json = #"{"cxGraphicsBackend":"d3dmetal"}"#
        let data = try JSONDecoder().decode(GameOptionsData.self, from: Data(json.utf8))
        let options = GameOptions()
        options.set(data: data)
        #expect(options.d3dMtl4Enabled == (newestD3DMetalBackend == "d3dmetal4" && OSVersion >= 27))
    }

    /// But a record that really did say d3dmetal4 with Metal 4 off keeps it --
    /// that is an answer, and folding did not happen.
    @Test func anUnfoldedRecordKeepsItsMetalFourAnswer() throws {
        let json = #"{"cxGraphicsBackend":"d3dmetal4","d3dMtl4Enabled":false}"#
        let data = try JSONDecoder().decode(GameOptionsData.self, from: Data(json.utf8))
        let options = GameOptions()
        options.set(data: data)
        #expect(options.d3dMtl4Enabled == false)
    }

    /// The default follows the newest toolkit the build carries, rather than a
    /// string somebody has to remember to change when a d3dMetal5 ships.
    @Test func theDefaultIsTheNewestToolkitAndTheParkerCanShowIt() {
        #expect(cxGraphicsBackend.contains(where: { $0.id == newestD3DMetalBackend }))
        #expect(GameOptions().cxGraphicsBackend == newestD3DMetalBackend)
    }

    // MARK: seeding

    @Test func aTitleWithNothingSavedIsGivenAConfiguration() throws {
        let key = scratchKey()
        defer { clean(key) }
        #expect(GameDefaults.seedIfAbsent(key: key) == true)
        let read: GameOptionsData? = readUsrDefData(key: key)
        #expect(read?.cxGraphicsBackend == newestD3DMetalBackend)
        #expect(read?.mtlHudEnabled == true)
    }

    /// Never over a configuration somebody made, including choices that happen
    /// to equal a default.
    @Test func aTitleThatWasConfiguredKeepsEveryChoice() throws {
        let key = scratchKey()
        defer { clean(key) }
        let mine = GameOptions()
        mine.cxGraphicsBackend = "dxvk"
        mine.mtlHudEnabled = false
        mine.envVariables = "MINE=1"
        persistUsrDefData(key: key, data: GameOptionsData(data: mine))

        #expect(GameDefaults.seedIfAbsent(key: key) == false)
        let read: GameOptionsData? = readUsrDefData(key: key)
        #expect(read?.cxGraphicsBackend == "dxvk")
        #expect(read?.mtlHudEnabled == false)
        #expect(read?.envVariables == "MINE=1")
    }

    @Test func seedingTwiceWritesOnce() throws {
        let key = scratchKey()
        defer { clean(key) }
        #expect(GameDefaults.seedIfAbsent(key: key) == true)
        #expect(GameDefaults.seedIfAbsent(key: key) == false)
    }

    // MARK: the key

    /// Steam's appid where there is one, the library's own id where there is
    /// not. Configured under one name and launched under another is the same
    /// bug wearing different clothes.
    @Test func theKeyIsTheAppIDWhenThereIsOne() {
        #expect(GameDefaults.key(forAppID: 2552440, id: "ignored")
                == namespacedKey("GameOptions", "2552440"))
        #expect(GameDefaults.key(forAppID: 0, id: "5F9644CA-947E")
                == namespacedKey("GameOptions", "5F9644CA-947E"))
    }
}
