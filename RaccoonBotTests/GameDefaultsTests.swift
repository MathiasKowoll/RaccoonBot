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
        #expect(GameDefaults.freshOptions().cxGraphicsBackend == "d3dmetal4")
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

    // MARK: seeding

    @Test func aTitleWithNothingSavedIsGivenAConfiguration() throws {
        let key = scratchKey()
        defer { clean(key) }
        #expect(GameDefaults.seedIfAbsent(key: key) == true)
        let read: GameOptionsData? = readUsrDefData(key: key)
        #expect(read?.cxGraphicsBackend == "d3dmetal4")
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
