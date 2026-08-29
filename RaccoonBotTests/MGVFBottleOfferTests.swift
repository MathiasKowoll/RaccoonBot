//
//  MGVFBottleOfferTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

private final class Store: MGVFDecisionStore {
    var titles: [String: String] = [:]
    var dismissed: Set<String> = []
    var fingerprints: [String: String] = [:]

    func pairedTitle(for folder: String) -> String? { titles[folder] }
    func setPairedTitle(_ title: String?, for folder: String) { titles[folder] = title }
    func isDismissed(_ folder: String) -> Bool { dismissed.contains(folder) }
    func setDismissed(_ v: Bool, for folder: String) {
        if v { dismissed.insert(folder) } else { dismissed.remove(folder) }
    }
    func appliedFingerprint(for folder: String) -> String? { fingerprints[folder] }
    func setAppliedFingerprint(_ f: String?, for folder: String) { fingerprints[folder] = f }
}

/// A fix that goes into the bottle leaves nothing beside the game, so what this
/// application knows about it is what it did: a successful install records a
/// fingerprint and a restore clears it. The alternative -- asking the installer
/// -- is a process spawn, and a library of fifty-eight titles redraws often.
@Suite("Knowing whether a bottle fix is on")
struct MGVFBottleOfferTests {

    private let folder = "/Volumes/X8/steamapps/common/[NINJA GAIDEN] NINJA GAIDEN 3"

    @Test func neverInstalledMeansItIsStillNeeded() {
        let store = Store()
        #expect(store.appliedFingerprint(for: folder) == nil)
    }

    @Test func installingRecordsIt() {
        let store = Store()
        store.setAppliedFingerprint("abc123", for: folder)
        #expect(store.appliedFingerprint(for: folder) == "abc123")
    }

    @Test func restoringForgetsIt() {
        let store = Store()
        store.setAppliedFingerprint("abc123", for: folder)
        store.setAppliedFingerprint(nil, for: folder)
        #expect(store.appliedFingerprint(for: folder) == nil)
    }

    /// One folder's record says nothing about another's -- four scripts serve
    /// more than one title.
    @Test func oneFoldersRecordIsNotAnothers() {
        let store = Store()
        let other = "/Volumes/X8/steamapps/common/Nioh"
        store.setAppliedFingerprint("abc123", for: folder)
        #expect(store.appliedFingerprint(for: other) == nil)
    }

    /// The record is a memory, not the fact: the bottle can be changed by other
    /// means. That is why --status is asked before acting, where being wrong
    /// matters, and not while drawing a row, where it does not.
    @Test func theRecordIsNotTheBottle() {
        let store = Store()
        store.setAppliedFingerprint("abc123", for: folder)
        // Somebody restores the fix outside this application. The record still
        // says installed, and nothing here can tell -- which is the cost being
        // accepted, and the reason the installer is asked before acting.
        #expect(store.appliedFingerprint(for: folder) != nil)
    }
}
