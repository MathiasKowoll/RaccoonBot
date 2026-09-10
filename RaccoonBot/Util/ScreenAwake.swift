import Foundation
import IOKit.pwr_mgt

/// Keep the screen awake while a game is being played.
///
/// macOS decides you are away by watching for input it can see, and while a
/// game runs under wine it sees none: the pad is opened exclusively by the
/// bottle, so not one of its reports reaches the system, and a game asks for no
/// keyboard and no mouse. Half an hour into a boss fight the idle timer runs
/// out and the screen saver comes up over the game.
///
/// The fix is to say so. A power assertion is macOS's own way for a process to
/// state that something is happening the system cannot see -- it is what
/// `caffeinate -d` holds, and what a video player holds while it plays -- and
/// it lasts exactly as long as it is held. Nothing is disabled and no setting
/// is changed: when the assertion goes, the system's own timers pick up where
/// they were, so a crash or a force quit cannot leave a Mac that never sleeps.
///
/// Everything here runs on the main actor, which is this project's default and
/// is also what makes the bookkeeping below need no lock of its own.
enum ScreenAwake {
    /// What the assertion is called in `pmset -g assertions`, so somebody
    /// looking at a Mac that will not sleep can see who is asking, and why.
    static let reason = "RaccoonBot: a game is running"

    private static var held: IOPMAssertionID?
    private static var watching: Set<String> = []

    /// Whether the assertion should be held, given what is running.
    ///
    /// Separated from the holding so the decision can be tested without a power
    /// assertion. The rule is only "some game is running", and naming it is the
    /// point: `gamesRunning` already excludes wine's own furniture, Steam's and
    /// a launcher's, so this adds no second opinion.
    nonisolated static func shouldHold(playing: [String]) -> Bool { !playing.isEmpty }

    /// Take or release the assertion to match what is running. Safe to call as
    /// often as a poll likes: it acts only on a change.
    static func match(playing: [String]) { set(shouldHold(playing: playing)) }

    static func set(_ wanted: Bool) {
        if wanted, held == nil {
            var id = IOPMAssertionID(0)
            let status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     reason as CFString, &id)
            if status == kIOReturnSuccess {
                held = id
                console.log("the screen will stay awake while the game runs")
            } else {
                // Not fatal and not worth a warning: the game plays either way,
                // and the worst of it is a screen saver.
                console.log("could not ask macOS to keep the screen awake (\(status))")
            }
        } else if !wanted, let id = held {
            IOPMAssertionRelease(id)
            held = nil
            console.log("the screen may sleep again")
        }
    }

    /// For a shutdown path that wants to be sure nothing is left held.
    static func release() { set(false) }

    /// Watch a bottle and hold the assertion for as long as a game runs in it.
    ///
    /// Driven from here rather than from each launcher's own loop, for one
    /// reason: an assertion taken in one place and released in another is one
    /// that will be left held one day, and a Mac that never sleeps again is a
    /// worse bug than a screen saver. This takes it, releases it and stops
    /// watching, all within the same few lines.
    ///
    /// A gap is not an ending. A title with a launcher chain of its own exits
    /// and comes back a second later, and the screen must not be allowed to
    /// sleep in between, so the watch ends only once the bottle has been quiet
    /// for a while -- the same reasoning the launchers' own idle graces use.
    static func watch(bottleAt directory: URL, quiet: TimeInterval = 90,
                      poll: TimeInterval = 5) {
        let key = directory.path
        guard !watching.contains(key) else { return }
        watching.insert(key)

        Task {
            var idleSince: Date?
            while !Task.isCancelled {
                let playing = BottleProcesses.gamesRunning(inBottleAt: directory)
                match(playing: playing)
                if playing.isEmpty {
                    if idleSince == nil { idleSince = Date() }
                    if let since = idleSince, Date().timeIntervalSince(since) >= quiet { break }
                } else {
                    idleSince = nil
                }
                try? await Task.sleep(for: .seconds(poll))
            }
            set(false)
            watching.remove(key)
        }
    }
}
