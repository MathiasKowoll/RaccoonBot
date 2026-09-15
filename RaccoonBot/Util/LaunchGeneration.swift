import Foundation

/// Which launch we are on.
///
/// Every destructive step this application takes was decided some time
/// earlier, and the gap has been the source of every serious fault here: a
/// teardown decided for one session arriving in the middle of the next one.
/// Checking again at the moment of the kill helps, but there is always another
/// gap between the check and the act.
///
/// A counter closes it. A launch bumps it; a teardown remembers what it was
/// when it started and gives up the moment it differs. Nothing has to be
/// guessed about processes or names or timing: if somebody has pressed Play
/// since this decision was made, the decision is about a session that no
/// longer exists.
///
/// Measured on the fault that prompted it: Ninja Gaiden 3 ended at 22:21:57
/// and its teardown was due at 22:23:57. Ninja Gaiden Sigma was launched in
/// between, its Steam started at 22:24:11, and the teardown -- still working
/// through its own thirty-second wait -- killed it fourteen seconds later.
/// Counted per bottle, since 2026-09-03.
///
/// It was one counter for the whole application, and a launch anywhere bumped
/// it. That is right about the fault above -- both those sessions were in the
/// same prefix -- and wrong about every other pair: playing an Epic title and
/// then starting a Steam one in a different bottle cancelled the Epic
/// teardown permanently, so that bottle was never closed and its cloud save
/// never waited for. A session in one bottle says nothing about a session in
/// another.
final class LaunchGeneration: @unchecked Sendable {
    static let shared = LaunchGeneration()

    private let lock = NSLock()
    private var values: [String: Int] = [:]
    /// Bumped by every launch, whatever the bottle. Only ever compared
    /// against a teardown whose own bottle could not be identified -- see
    /// `key(for:)`.
    private var anywhere = 0
    /// The generation each bottle was on when Stop was last pressed for it --
    /// see `stopped(bottle:)`.
    private var stops: [String: Int] = [:]

    /// What a bottle is counted under.
    ///
    /// Derived through `BottleReference` so a launch and the teardown that
    /// follows it cannot disagree about which bottle they mean: the same
    /// prefix is written as a `file://` URL in one place and a plain path in
    /// another, with or without a trailing slash. A spelling that did not
    /// match would leave the teardown comparing a counter nobody had bumped,
    /// which answers "nothing has been launched since" -- and that is the
    /// answer that kills a running game. One derivation, used by both sides,
    /// is the whole safety argument for counting per bottle at all.
    static func key(for bottle: String) -> String {
        guard let ref = BottleReference(bottle) else { return "" }
        return ref.root + "/" + ref.name
    }

    /// Records a launch in this bottle and returns the generation it belongs
    /// to.
    @discardableResult
    func launched(bottle: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        anywhere += 1
        let key = Self.key(for: bottle)
        guard !key.isEmpty else { return anywhere }
        let next = (values[key] ?? 0) + 1
        values[key] = next
        return next
    }

    /// The generation this bottle is on now.
    func current(for bottle: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        let key = Self.key(for: bottle)
        // A bottle that cannot be identified is answered from the counter
        // every launch bumps, so any launch at all supersedes it. That is the
        // conservative direction: it leaves a bottle standing rather than
        // tearing one down on a guess about which bottle it was.
        return key.isEmpty ? anywhere : (values[key] ?? 0)
    }

    /// Has anything been launched IN THIS BOTTLE since `generation` was taken?
    func supersedes(_ generation: Int, for bottle: String) -> Bool {
        current(for: bottle) != generation
    }

    /// Records that the user asked to stop what runs in this bottle, against
    /// the generation the bottle is on at that moment.
    ///
    /// A launch takes its generation before it waits for its bottle, and that
    /// wait can last as long as BottleProcesses' bound. A Stop pressed inside
    /// it closes the bottle with the launch's own generation -- nothing has
    /// been launched since, so nothing stands that teardown down -- but the
    /// launch has not run anything yet for the teardown to end, and once its
    /// wait is over it would start the title into the bottle the user had just
    /// stopped. So the launch asks `wasStopped` before it does anything to the
    /// bottle.
    ///
    /// Marked, never bumped. A bump would tell the running session's tracker
    /// that a game had been launched since, and it would stand down -- and
    /// the Epic stop leaves the whole teardown to that tracker.
    ///
    /// Keyed like the counter, so a stop and a launch that spell the same
    /// bottle differently still meet, and a bottle that cannot be identified
    /// is answered from the counter every launch bumps.
    func stopped(bottle: String) {
        lock.lock(); defer { lock.unlock() }
        // Not through `current(for:)`: it takes this same lock, and NSLock is
        // not recursive.
        let key = Self.key(for: bottle)
        stops[key] = key.isEmpty ? anywhere : (values[key] ?? 0)
    }

    /// Was Stop pressed for this bottle while it was on `generation`?
    ///
    /// Only the generation the bottle was on when Stop was pressed answers
    /// yes. A launch started after that has a newer one, and the Stop was not
    /// about it.
    func wasStopped(_ generation: Int, for bottle: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stops[Self.key(for: bottle)] == generation
    }
}

/// What became of one press of Play, told by the launch to the tracker armed
/// for it.
///
/// The tracker is armed before the launch is called, and it needs three things
/// the counter cannot give it. Which generation its launch took: reading the
/// counter instead was right only while nothing in the launch awaited before
/// the bump, and a wait moved above it once made every teardown of the session
/// stand down. Whether the launch ran anything at all: a launch that stands
/// down because Stop was pressed, or because a newer Play took the bottle, used
/// to leave its tracker to time out after a minute and a half or more and then
/// call onTerminate, which cleared the playing title and the loader of whatever
/// session was live by then. And when the title's command ran: the tracker's
/// ninety seconds to find the game in Steam's log began when it was armed, so
/// the wait for the bottle came out of them.
///
/// So the tracker waits for this before it watches anything, and a tracker
/// cannot read a generation its launch has not decided.
nonisolated final class PendingLaunch: @unchecked Sendable {
    enum Outcome: Equatable, Sendable {
        /// The title's command has run, as this generation of its bottle.
        case started(generation: Int)
        /// A newer launch into the same bottle took over while this one
        /// waited. That launch has a tracker and a loader of its own.
        case superseded
        /// Nothing was started and nothing takes its place: Stop was pressed
        /// during the wait, a guard or the engine refused, or the launch threw.
        case abandoned
    }

    private let lock = NSLock()
    private var result: Outcome?
    private var waiting: [CheckedContinuation<Outcome, Never>] = []

    /// Records what became of the launch. Only the first answer counts, so a
    /// launch can say "abandoned" on its way out whatever happened before it,
    /// without undoing a start or a stand-down it has already reported.
    func decide(_ outcome: Outcome) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = outcome
        let resumed = waiting
        waiting = []
        lock.unlock()
        resumed.forEach { $0.resume(returning: outcome) }
    }

    /// The answer, if the launch has given one yet.
    var decided: Outcome? {
        lock.lock(); defer { lock.unlock() }
        return result
    }

    /// Waits until the launch has decided.
    func outcome() async -> Outcome {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
                return
            }
            waiting.append(continuation)
            lock.unlock()
        }
    }
}

/// Thrown by a tracker whose launch started nothing. Both callers arm the
/// tracker in a task nobody reads the error of, and the launch has already
/// written why it stood down.
nonisolated struct LaunchStoodDown: Error {}
