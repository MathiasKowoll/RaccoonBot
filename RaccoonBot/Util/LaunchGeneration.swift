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
}
