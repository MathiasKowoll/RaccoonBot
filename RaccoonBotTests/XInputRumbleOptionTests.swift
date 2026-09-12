import Testing
@testable import RaccoonBot

/// The switch that offers a pad's motors to XInput, per title.
///
/// What is worth pinning down is not that a checkbox writes a 1 -- it is the
/// three conditions under which it must write a 0 anyway, because each of them
/// was learned the hard way.
struct XInputRumbleOptionTests {
    private let pads = [SonyPads.Pad(productID: SonyPads.models[0], transport: "Bluetooth")]

    private func overrides(asking: Bool, engineCan: Bool = true, sdl: Bool = false,
                           tellsTheBus: Bool = true) -> [DualSenseRoute.Override] {
        DualSenseRoute.overrides(for: pads, sdlEnabled: sdl, engineTellsTheBus: tellsTheBus,
                                 xinputRumble: asking, engineCanXInputRumble: engineCan)
    }

    @Test func aTitleThatDoesNotAskGetsZero() {
        #expect(overrides(asking: false).allSatisfy { $0.xinputRumble == 0 })
    }

    @Test func aTitleThatAsksGetsOne() {
        #expect(overrides(asking: true).allSatisfy { $0.xinputRumble == 1 })
    }

    /// An engine without mgvf-0010 would read the value and do nothing with it,
    /// so writing a 1 there would put the bottle in a state the console says is
    /// on and the pad says is off.
    @Test func anEngineThatCannotDoItIsNotAsked() {
        #expect(overrides(asking: true, engineCan: false).allSatisfy { $0.xinputRumble == 0 })
    }

    /// On the SDL route the pad's own descriptor is thrown away for a synthetic
    /// one, so there is nothing for the haptics collection to be added to.
    ///
    /// And only for the model that is actually there. A route is a fact about
    /// an attached pad, not about a product id: the model that is not plugged
    /// in is not on the SDL route, so its key is written for the pad that may
    /// arrive later rather than for the one that did not.
    @Test func theModelOnTheSDLRouteGetsZeroWhateverTheTitleAsks() {
        let written = overrides(asking: true, sdl: true, tellsTheBus: false)
        let attached = DualSenseRoute.sectionPath(productID: SonyPads.models[0])
        let onSDL = written.first { $0.path == attached }
        let absent = written.first { $0.path != attached }
        #expect(onSDL?.xinputRumble == 0)
        #expect(absent?.xinputRumble == 1)
    }

    /// Both models, every launch, asked for or not. That is what makes the
    /// setting per title: the next game clears what this one set.
    @Test func bothModelsAreWrittenEveryTime() {
        #expect(overrides(asking: true).count == SonyPads.models.count)
    }
}
