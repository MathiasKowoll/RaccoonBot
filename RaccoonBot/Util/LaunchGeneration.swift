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
final class LaunchGeneration: @unchecked Sendable {
    static let shared = LaunchGeneration()

    private let lock = NSLock()
    private var value = 0

    /// Records a launch and returns the generation it belongs to.
    @discardableResult
    func launched() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }

    var current: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    /// Has anything been launched since `generation` was taken?
    func supersedes(_ generation: Int) -> Bool { current != generation }
}
