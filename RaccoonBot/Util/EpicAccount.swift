//
//  EpicAccount.swift
//  RaccoonBot
//
//  The Epic account's own session, and where it is kept.
//
//  RaccoonBot never sees the password. The user signs in on Epic's own page,
//  which hands back a one-time authorization code; that code is exchanged for
//  a pair of tokens, and it is the tokens that live here. This is the same
//  route Legendary and Heroic take, and the reason for it is that every
//  anonymous route into an account is shut: Epic's catalogue API answers 401
//  and the store's GraphQL 403 (measured 2026-09-02).
//
//  The alternative that was considered and rejected, with the user, on
//  2026-09-03: the desktop launcher keeps its own session in
//  `GameUserSettings.ini` under `[RememberMe]`, 1312 bytes encrypted with
//  Epic's own scheme rather than with Windows' DPAPI. Reading it would mean
//  decrypting a vendor's credential store with a key taken out of their
//  client, which puts the account at risk for a convenience. Signing in on
//  Epic's page costs one paste and risks nothing that the user has not chosen.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Security

/// What Epic hands back for an authorization code, kept only in the keychain.
nonisolated struct EpicTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    /// When the access token stops working. Epic sends both a lifetime in
    /// seconds and an absolute time; the absolute one is kept, because a
    /// lifetime is only meaningful at the moment it was issued.
    var expiresAt: Date
    var refreshExpiresAt: Date?
    var accountID: String
    var displayName: String?

    /// A token about to expire is treated as expired: a request that takes
    /// two seconds must not be sent with one second of life left.
    func isFresh(at now: Date = Date(), margin: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) > margin
    }

    /// Whether signing in again is the only way forward.
    func canRefresh(at now: Date = Date()) -> Bool {
        guard let refreshExpiresAt else { return !refreshToken.isEmpty }
        return !refreshToken.isEmpty && refreshExpiresAt > now
    }
}

/// Where a session is kept between launches.
///
/// A protocol so the logic above it can be tested without touching the real
/// keychain, which prompts and is shared with every other build of this app.
nonisolated protocol EpicSessionStore: Sendable {
    func save(_ tokens: EpicTokens) throws
    func load() throws -> EpicTokens?
    func clear() throws
}

/// The login keychain.
///
/// This application is not sandboxed, so it reaches the keychain without a
/// keychain-access-group entitlement. One wrinkle worth knowing while
/// developing: a locally built copy is ad-hoc signed and its signature
/// changes on every build, so macOS treats each build as a different
/// application and asks again before handing the item over. A release copy,
/// signed once, asks once.
nonisolated struct EpicKeychain: EpicSessionStore {
    let service: String
    let account: String

    init(service: String = "io.github.mathiaskowoll.raccoonbot.epic", account: String = "session") {
        self.service = service
        self.account = account
    }

    enum Failure: Error, Equatable {
        case keychain(OSStatus)
        case notReadable
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func save(_ tokens: EpicTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        // Replaced rather than updated: one session, and an update that finds
        // nothing to update is a second code path for no gain.
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    func load() throws -> EpicTokens? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let data = item as? Data else { throw Failure.notReadable }
        return try JSONDecoder().decode(EpicTokens.self, from: data)
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }
}

/// A store that keeps the session in memory, for tests and for a run where
/// the keychain is not available.
nonisolated final class EpicMemorySession: EpicSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: EpicTokens?
    init(_ tokens: EpicTokens? = nil) { self.tokens = tokens }
    func save(_ t: EpicTokens) throws { lock.lock(); defer { lock.unlock() }; tokens = t }
    func load() throws -> EpicTokens? { lock.lock(); defer { lock.unlock() }; return tokens }
    func clear() throws { lock.lock(); defer { lock.unlock() }; tokens = nil }
}
