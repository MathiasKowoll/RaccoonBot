//
//  GamepadOwnersTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// Who a press goes to when more than one thing is on screen.
///
/// The grid listens while the library shows; a sheet listens on top while it
/// is up. What went wrong before this was a stack: the grid re-wired itself
/// when the sheet's title was cleared, and the sheet's onDisappear -- after
/// the dismissal animation -- set the handlers to nil, taking the grid's with
/// them. Nothing listened after that.
@MainActor
struct GamepadOwnersTests {

    private final class Log { var moves: [String] = [] }

    private func listener(_ name: String, _ log: Log) -> ((GridFocus.Direction) -> Void, (GamepadInput.Press) -> Void) {
        ({ _ in log.moves.append(name) }, { _ in log.moves.append(name) })
    }

    @Test func theTopOfTheStackHearsThePress() {
        let pad = GamepadInput(hardware: false), log = Log()
        let (gm, gp) = listener("grid", log)
        let (sm, sp) = listener("sheet", log)
        pad.take(onMove: gm, onPress: gp)
        pad.take(onMove: sm, onPress: sp)
        pad.deliver(move: .down)
        #expect(log.moves == ["sheet"])
    }

    @Test func releasingTheSheetRestoresTheGrid() {
        let pad = GamepadInput(hardware: false), log = Log()
        let (gm, gp) = listener("grid", log)
        let (sm, sp) = listener("sheet", log)
        pad.take(onMove: gm, onPress: gp)
        let sheet = pad.take(onMove: sm, onPress: sp)
        pad.release(sheet)
        pad.deliver(press: .select)
        #expect(log.moves == ["grid"])
    }

    /// The order SwiftUI actually produced: the grid re-took the pad and THEN
    /// the sheet released. The sheet's release must not touch the grid's.
    @Test func releasingOutOfOrderRemovesOnlyYourOwn() {
        let pad = GamepadInput(hardware: false), log = Log()
        let (gm, gp) = listener("grid", log)
        let (sm, sp) = listener("sheet", log)
        let sheet = pad.take(onMove: sm, onPress: sp)
        pad.take(onMove: gm, onPress: gp)     // the grid, re-taking on top
        pad.release(sheet)                    // the sheet, late
        pad.deliver(move: .up)
        #expect(log.moves == ["grid"], "the grid's handlers were removed by somebody else's release")
        #expect(pad.listeners == 1)
    }

    @Test func releasingTwiceIsNothing() {
        let pad = GamepadInput(hardware: false), log = Log()
        let (gm, gp) = listener("grid", log)
        let (sm, sp) = listener("sheet", log)
        pad.take(onMove: gm, onPress: gp)
        let sheet = pad.take(onMove: sm, onPress: sp)
        pad.release(sheet)
        pad.release(sheet)
        #expect(pad.listeners == 1)
        pad.deliver(move: .left)
        #expect(log.moves == ["grid"])
    }

    @Test func nobodyListeningIsNotACrash() {
        let pad = GamepadInput(hardware: false)
        pad.deliver(move: .right)
        pad.deliver(press: .back)
        #expect(pad.listeners == 0)
    }
}

/// The keyboard, mapped onto what a pad does.
struct KeyboardMappingTests {
    @Test func arrowsMoveAndReturnSelectsAndEscapeGoesBack() {
        #expect(GamepadInput.action(forKeyCode: 126) == .move(.up))
        #expect(GamepadInput.action(forKeyCode: 125) == .move(.down))
        #expect(GamepadInput.action(forKeyCode: 123) == .move(.left))
        #expect(GamepadInput.action(forKeyCode: 124) == .move(.right))
        #expect(GamepadInput.action(forKeyCode: 36) == .press(.select))
        #expect(GamepadInput.action(forKeyCode: 76) == .press(.select))
        #expect(GamepadInput.action(forKeyCode: 49) == .press(.select), "Space, as on a native popup")
        #expect(GamepadInput.action(forKeyCode: 53) == .press(.back))
    }

    /// Every other key is somebody else's. A letter in particular: taking
    /// one would break typing in the filter field.
    @Test func otherKeysAreNotOurs() {
        for code: UInt16 in [0, 1, 12, 51, 48] { #expect(GamepadInput.action(forKeyCode: code) == nil) }
    }
}

/// The switch that decides whether we touch a pad at all.
///
/// Each test gets a defaults suite of its own. With these three writing the
/// switch into the standard defaults, a timing-sensitive test in an
/// unrelated file failed every run; with all three removed it passed; with
/// the same three on a private suite it passed twice. Which of the three was
/// the trigger was not isolated -- the attempt to run them one at a time ran
/// nothing, an -only-testing and a -skip-testing on the same group cancelling
/// out -- so the evidence is the shared store, not a particular writer.
@MainActor
struct GamepadEnabledTests {

    private func fresh() -> UserDefaults {
        UserDefaults(suiteName: "test.gamepad.\(UUID().uuidString)")!
    }

    @Test func unsetMeansOn() {
        let pad = GamepadInput(hardware: false, defaults: fresh())
        #expect(pad.enabled == true)
    }

    @Test func offIsRememberedAndReportsNothingConnected() {
        let store = fresh()
        let pad = GamepadInput(hardware: false, defaults: store)
        pad.enabled = false
        #expect(store.bool(forKey: GamepadInput.enabledKey) == false)
        #expect(pad.connected == false, "off never shows a ring, whatever is plugged in")
        let again = GamepadInput(hardware: false, defaults: store)
        #expect(again.enabled == false)
    }

    /// Off does not take the stack away: a listener still hears the keyboard.
    @Test func offKeepsTheKeyboardPath() {
        let pad = GamepadInput(hardware: false, defaults: fresh())
        pad.enabled = false
        var heard = 0
        pad.take(onMove: { _ in heard += 1 }, onPress: { _ in })
        pad.deliver(move: .down)
        #expect(heard == 1)
    }
}

/// While a game runs the pad is the game's. Letting go must not take the
/// listener stack or the switch with it, or nothing would come back after.
@MainActor
struct GamepadSuspensionTests {
    private func fresh() -> UserDefaults { UserDefaults(suiteName: "test.gamepad.\(UUID().uuidString)")! }

    @Test func suspendingKeepsTheStackAndTheSwitch() {
        let pad = GamepadInput(hardware: false, defaults: fresh())
        var heard = 0
        pad.take(onMove: { _ in heard += 1 }, onPress: { _ in })
        pad.suspended = true
        #expect(pad.listeners == 1, "the grid is still listening for when the game ends")
        #expect(pad.enabled == true, "letting go is not turning off")
        #expect(pad.connected == false, "no ring while a game has the pad")
        pad.suspended = false
        pad.deliver(move: .down)
        #expect(heard == 1)
    }

    @Test func settingTheSameValueTwiceIsNothing() {
        let pad = GamepadInput(hardware: false, defaults: fresh())
        pad.suspended = true
        pad.suspended = true
        pad.suspended = false
        #expect(pad.suspended == false)
    }
}
