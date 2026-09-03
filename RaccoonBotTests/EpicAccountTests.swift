//
//  EpicAccountTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// The session: when it is still good, when it can be renewed, and how it
/// survives a relaunch.
struct EpicAccountTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func tokens(expiresIn: TimeInterval, refreshIn: TimeInterval? = 86_400) -> EpicTokens {
        EpicTokens(accessToken: "a", refreshToken: "r",
                   expiresAt: t0.addingTimeInterval(expiresIn),
                   refreshExpiresAt: refreshIn.map { t0.addingTimeInterval($0) },
                   accountID: "acc", displayName: "someone")
    }

    @Test func aTokenAboutToExpireIsNotFresh() {
        #expect(tokens(expiresIn: 3600).isFresh(at: t0))
        #expect(!tokens(expiresIn: 30).isFresh(at: t0), "thirty seconds is not enough to send a request with")
        #expect(!tokens(expiresIn: -1).isFresh(at: t0))
        #expect(tokens(expiresIn: 61).isFresh(at: t0))
    }

    @Test func renewalNeedsARefreshTokenThatIsItselfAlive() {
        #expect(tokens(expiresIn: -1).canRefresh(at: t0))
        #expect(!tokens(expiresIn: -1, refreshIn: -1).canRefresh(at: t0), "an expired refresh token means signing in again")
        var noRefresh = tokens(expiresIn: -1)
        noRefresh.refreshToken = ""
        #expect(!noRefresh.canRefresh(at: t0))
    }

    /// No expiry given for the refresh token: Epic does not always send one,
    /// and refusing to try would strand a session that would have worked.
    @Test func anUnknownRefreshExpiryIsTried() {
        #expect(tokens(expiresIn: -1, refreshIn: nil).canRefresh(at: t0))
    }

    @Test func aSessionSurvivesBeingPutAwayAndTakenOut() throws {
        let store = EpicMemorySession()
        #expect(try store.load() == nil)
        let t = tokens(expiresIn: 3600)
        try store.save(t)
        #expect(try store.load() == t)
        try store.clear()
        #expect(try store.load() == nil)
    }

    /// The shape has to survive the round trip through JSON, since that is
    /// what the keychain holds.
    @Test func theSessionRoundTripsThroughJSON() throws {
        let t = tokens(expiresIn: 3600)
        let back = try JSONDecoder().decode(EpicTokens.self, from: try JSONEncoder().encode(t))
        #expect(back == t)
    }
}
