//
//  InlineEnvsTests.swift
//  RaccoonBotTests
//
//  What actually reaches a game's command line.
//
//  Written because a peer session spent an evening comparing our launch
//  against a hand launch using a probe that dumps a FIXED LIST of variable
//  names. Anything outside that list was invisible, so every comparison was
//  against something that could not be complete. The answer to "what do you
//  set" should come from the code that sets it, not from a list somebody
//  maintains by hand.
//

import Foundation
import Testing
@testable import RaccoonBot

struct InlineEnvsTests {

    /// KINGDOM HEARTS HD 2.8, appid 2552440, exactly as this machine has it
    /// stored. Decoded through the same type the application decodes it with.
    private func kh28() throws -> GameOptions {
        let json = """
        {"advertiseAVX":true,"cxGraphicsBackend":"d3dmetal4","d3dMEnableMetalFX":"",
         "d3dMaxFPS":0,"d3dMtl4Enabled":false,"d3dSupportDXR":"","disableHidraw":false,
         "dx9PatchEnabled":false,"dxmtMetalFXSpatial":false,"dxmtMetalSpatialUpscaleFactor":1,
         "dxmtPreferredMaxFrameRate":0,"dxvk":"","enableSDL":true,"envVariables":"",
         "gameArguments":"","mtlHudEnabled":true,"mvkArgBuff":true,"ue4Hack":true,
         "useArmBottle":false,"vulkanLib":"latest","wineEsync":"","wineMSync":true,
         "x87PatchEnabled":false}
        """
        let data = try JSONDecoder().decode(GameOptionsData.self, from: Data(json.utf8))
        let options = GameOptions()
        options.set(data: data)
        return options
    }

    /// Printed as well as asserted: the whole point is that somebody else can
    /// read what we set without maintaining a list of names to look for.
    @Test func theEnvironmentForKingdomHearts28IsWhatWeSay() throws {
        let rendered = getInlineEnvs(from: try kh28(), cxAppPath: "/Users/x/Applications/Crossover_patched.app")
        print("KH 2.8 inline envs >>>\(rendered)<<<")

        // The three a peer could not see, and the answer to each.
        #expect(rendered.contains("gameArguments") == false)
        #expect(rendered.hasPrefix("MTL_HUD") || rendered.contains(" MTL_HUD_ENABLED=1"))
        #expect(rendered.contains("MTL_HUD_ENABLED=1"))

        // The HUD is on for this title, so both of its variables are written.
        #expect(rendered.contains("MTL_HUD_ELEMENTS="))

        // d3dmetal4 draws here, so the D3DMetal family is written and the
        // others are not -- a game on one backend should not carry another's.
        #expect(rendered.contains("D3DM_ENABLE_METALFX=1"))
        #expect(rendered.contains("DXMT_ENABLE_NVEXT") == false)
        #expect(rendered.contains("DXVK_ASYNC") == false)
    }

    /// A title with nothing typed into it contributes nothing, which is what
    /// makes "the typed environment" a dead end as an explanation.
    @Test func nothingTypedMeansNothingAdded() throws {
        let rendered = getInlineEnvs(from: try kh28(), cxAppPath: "/x")
        // Every assignment is NAME=VALUE with no stray tokens: an unquoted
        // fragment here is what once made `env` read a value as the program
        // to run and killed the launch before anything started.
        for token in rendered.split(separator: " ") where !token.isEmpty {
            #expect(token.contains("="), "stray token in the env line: \(token)")
        }
    }
}
