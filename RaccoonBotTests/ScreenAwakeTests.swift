import Testing
@testable import RaccoonBot

/// The decision, not the assertion.
///
/// Taking a power assertion needs macOS and releasing it needs the same process
/// to still be alive, so what is worth pinning down here is the rule that says
/// when to hold one -- and the rule is deliberately small.
struct ScreenAwakeTests {
    @Test func nothingRunningMeansTheScreenMaySleep() {
        #expect(ScreenAwake.shouldHold(playing: []) == false)
    }

    @Test func aGameRunningKeepsItAwake() {
        #expect(ScreenAwake.shouldHold(playing: ["Beast.exe"]))
    }

    /// gamesRunning already excludes wine's own furniture, Steam's and a
    /// launcher's, so anything it returns is somebody playing. This is here to
    /// state that this type adds no second opinion of its own.
    @Test func severalAreNoDifferentFromOne() {
        #expect(ScreenAwake.shouldHold(playing: ["Beast.exe", "AnotherGame.exe"]))
    }
}
