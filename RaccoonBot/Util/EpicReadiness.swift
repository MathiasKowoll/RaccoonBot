//
//  EpicReadiness.swift
//  RaccoonBot
//
//  When the Epic launcher can be asked to install, and when it cannot.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// The Epic launcher will not take an install on its own command line.
///
/// Measured on 2026-09-03 across every launcher log in the bottle: three cold
/// starts that carried `?action=install` as their argument produced three
/// `II-E1003`, each of them the launcher answering itself --
///
///     LogUriHandler: AppInstallUriHandler: Catalog item resolved; dispatching install
///     LogPortal: Warning: FAppViewModel::FetchBuildInfoAndInstall: AppManager
///                not ready, reporting InstallFailed (II-E1003)
///
/// -- the URI handler doing its job and the portal behind it not being up yet.
/// The same URI handed to a launcher already running reached the
/// install-location selector. There is no counter-example either way.
///
/// It is only install: `action=launch`, `action=download` and `store/library`
/// all cold-start through a URI without tripping this, because none of them
/// calls `FetchBuildInfoAndInstall`. So this is not a rule about starting the
/// launcher, and nothing else in the application needs to wait.
///
/// A fixed sleep cannot do it. The moment of readiness is bounded only to
/// somewhere in (5.4s, 18.8s] after the log opens -- closed at 5.4, open at
/// 18.8, with nothing measured in between -- and startup phases on this machine
/// already vary by a factor of 1.7 between runs. So we wait for the launcher to
/// say so rather than for a clock.
nonisolated enum EpicReadiness {

    /// The launcher own line, the only one in its log present before both
    /// measured successes and after all three failures. Across the nine
    /// sessions that emit it: earliest 9.9s, median 12.0s, latest 14.6s -- all
    /// of them comfortably after the 6.1s by which every failure had happened.
    ///
    /// Qualified deliberately. Bare `AddSocialApplicationViewModel` fires about
    /// eight times at 3.7s for other namespaces (`poodle`, `ue`, and a null
    /// one); only the `EpicGamesLauncher` variant is late, and it occurs
    /// exactly once per session.
    static let marker = "AddSocialApplicationViewModel called for product with namespace EpicGamesLauncher"

    /// Two of eleven sessions never emitted the marker at all, so the wait
    /// cannot be unbounded. A URI that arrives late costs nothing -- deliveries
    /// at 18s and at 317s both worked -- while one that arrives early costs the
    /// user an error dialog, so the deadline delivers rather than gives up.
    static let deadline: TimeInterval = 90

    enum Verdict: Equatable {
        /// The launcher has said it is up; deliver the install.
        case ready
        /// Not yet -- either no log for this session yet, or nothing in it.
        case notYet
    }

    /// The launcher opens a fresh log on every start and renames the old one
    /// out of the way, so the file carries a new first line each session.
    ///
    /// This is load-bearing: the previous session very probably ended with the
    /// marker in it, and reading that as readiness would deliver the install to
    /// a launcher one second old -- exactly the failure being fixed. So a log
    /// whose first line has not changed is treated as having said nothing.
    static func header(of text: String) -> String? {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(String.init)
    }

    static func verdict(logText: String?, previousHeader: String?) -> Verdict {
        guard let logText, let head = header(of: logText) else { return .notYet }
        if let previousHeader, head == previousHeader { return .notYet }
        return logText.contains(marker) ? .ready : .notYet
    }

    /// Is the launcher up in this bottle? Asked of the wineserver rather than
    /// of the log, because a log says what happened, not what is still there.
    static func isRunning(inBottleAt bottle: URL) -> Bool {
        BottleProcesses.running(inBottleAt: bottle)
            .contains { $0.name.lowercased().hasPrefix("epicgameslauncher") }
    }

    /// Poll the launcher log until it says it is ready. True when the marker
    /// was seen, false when the deadline ran out first -- and the caller
    /// delivers either way.
    ///
    /// `nonisolated` and `async`, so the reading happens off the main actor:
    /// this runs for ten to fifteen seconds and must not hold the drawing
    /// thread.
    static func waitUntilInstallable(log: URL, after previousHeader: String?,
                                     deadline seconds: TimeInterval = deadline,
                                     poll: TimeInterval = 0.5,
                                     started: Date = Date()) async -> Bool {
        while Date().timeIntervalSince(started) < seconds {
            let text = try? String(contentsOf: log, encoding: .utf8)
            if verdict(logText: text, previousHeader: previousHeader) == .ready { return true }
            try? await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
        }
        return false
    }
}
