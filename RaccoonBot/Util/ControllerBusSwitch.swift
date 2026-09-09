//
//  ControllerBusSwitch.swift
//  RaccoonBot
//
//  The switch for the controller-bus set, and the sentence under it.
//
//  Two things that look like one. The switch is what the person wants: kept
//  in the defaults, on by default, and applied to whatever engine is
//  configured. The sentence is what the engine actually holds, read from the
//  engine each time and never from the switch -- because the script refuses
//  while a bottle is up, an engine made before the switch existed has nothing
//  in it, and somebody can run install-engine-controller.sh by hand. When the
//  two disagree the row says so and offers the one action that makes them
//  agree, instead of the switch quietly showing a state the engine is not in.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Combine
import Foundation

/// What the engine holds, and whether the set can be offered for it.
///
/// Nonisolated on purpose: reading it runs the installer's --status and scans
/// ntdll.so for the wine tag, so OptionsView reads it in Task.detached, once,
/// and remembers it. Never computed in a body -- see GStreamerStatus for the
/// crash that rule comes from.
nonisolated struct ControllerBusStatus: Sendable, Equatable {

    /// Whether the set is on offer for the configured engine, and if not, why.
    enum Offer: Equatable, Sendable {
        /// No engine is configured yet; there is nothing to install into.
        case noEngine
        /// This build does not carry the set, or not all of it. Names what.
        case notBundled(String)
        /// The set was built for another engine. Both are named.
        case wrongEngine(wanted: String, found: String)
        case offered
    }

    /// What the row asks for when the switch and the engine disagree.
    enum Action: Equatable, Sendable {
        case install
        case remove
    }

    /// The three colours the row can show, decided here so a test can see them.
    enum Light: Equatable, Sendable {
        /// The engine holds what the switch says.
        case good
        /// It does not, or the set is in a state the script calls broken.
        case warning
        /// Nothing to say about this engine: none configured, or not one of ours.
        case quiet
    }

    let offer: Offer
    /// The script's word: installed, broken or absent. Nil when it could not
    /// be asked -- no engine, or no script in this build to ask.
    let state: FixState?
    /// The binary's own word: the winebus.sys in the engine names the bus.
    /// Read independently of the script, the way DualSenseRoute reads it at
    /// launch, so the two can be seen to agree.
    let tellsTheBus: Bool

    /// The set travels in this build. When it does not, the switch is a
    /// promise nothing can keep, and it is disabled rather than kept.
    var isBundled: Bool {
        if case .notBundled = offer { return false }
        return true
    }

    /// What would make the engine agree with the switch, or nil when it does.
    ///
    /// Broken asks for a removal first: the four only work together -- the
    /// three PE files were written for each other, and winebus's two halves
    /// come from one source tree and share a struct -- and --restore returns
    /// whichever originals are there, after which install puts all four in.
    /// Installed-but-silent -- the script's record says
    /// installed and the winebus does not name the bus -- asks for an install,
    /// which replaces the file and keeps the original already set aside.
    func wantsAction(enabled: Bool) -> Action? {
        guard offer == .offered, let state else { return nil }
        switch (enabled, state) {
        case (true, .absent): return .install
        case (true, .installed): return tellsTheBus ? nil : .install
        case (true, .broken), (true, .half): return .remove
        case (false, .absent): return nil
        case (false, .installed), (false, .broken), (false, .half): return .remove
        }
    }

    func light(enabled: Bool) -> Light {
        switch offer {
        case .noEngine, .wrongEngine:
            return .quiet
        case .notBundled:
            return .warning
        case .offered:
            guard state != nil else { return .warning }
            return wantsAction(enabled: enabled) == nil ? .good : .warning
        }
    }

    /// What the row says: what the engine has, and what that means for a pad.
    func summary(enabled: Bool) -> String {
        switch offer {
        case .noEngine:
            return "No engine yet. The controller-bus set is offered once a CrossOver is made."
        case .notBundled(let what):
            return "This build does not carry the controller-bus set: \(what)."
        case .wrongEngine(let wanted, let found):
            return "The controller-bus set was built for \(wanted) and this is \(found), so it is not offered here."
        case .offered:
            break
        }
        guard let state else {
            return "The controller-bus set could not be asked about this CrossOver."
        }
        switch state {
        case .installed where tellsTheBus:
            return enabled
                ? "This CrossOver tells games which bus a controller is on — a DualSense on Bluetooth keeps rumble, the touchpad and the PS button."
                : "This CrossOver still carries the controller-bus set. Remove puts CrossOver's own four files back."
        case .installed:
            return "The controller-bus set is recorded as installed, but this CrossOver's winebus does not name the bus. Install puts the four files in again."
        case .broken, .half:
            return "The controller-bus set is half in this CrossOver, and the four files only work together. Remove it, then install it again."
        case .absent:
            return enabled
                ? "This CrossOver has the stock controller bus — a DualSense on Bluetooth goes through SDL. Install puts the set in."
                : "This CrossOver has the stock controller bus — a DualSense on Bluetooth goes through SDL."
        }
    }

    // MARK: - Reading it

    /// Everything the row needs, in one reading of one engine.
    ///
    /// The status is asked before the stamp is compared, so an engine the set
    /// was not built for still reports what it holds: somebody may have put
    /// the set there by hand, and the row should say so rather than nothing.
    static func read(engineAppPath: String?,
                     payload root: URL? = MGVFBundle.embeddedDirectory) -> ControllerBusStatus {
        guard let engineAppPath, !engineAppPath.isEmpty else {
            return ControllerBusStatus(offer: .noEngine, state: nil, tellsTheBus: false)
        }
        let tells = DualSenseRoute.engineTellsTheBus(cxAppPath: engineAppPath)
        let payload: BundledControllerBus.Payload
        do {
            payload = try BundledControllerBus.verified(in: root)
        } catch {
            return ControllerBusStatus(offer: .notBundled(error.localizedDescription), state: nil, tellsTheBus: tells)
        }
        let state = (try? BundledControllerBus.run(.status, onEngineAt: engineAppPath, script: payload.script))?.state
        let identity = EngineIdentity(ofEngineAt: URL(fileURLWithPath: engineAppPath))
        guard payload.stamp.matches(identity) else {
            return ControllerBusStatus(offer: .wrongEngine(wanted: payload.stamp.described,
                                                           found: identity.described),
                                       state: state, tellsTheBus: tells)
        }
        return ControllerBusStatus(offer: .offered, state: state, tellsTheBus: tells)
    }
}

/// The switch as the view drives it: refreshes the reading, applies an
/// action, and keeps the script's refusal where the person can read it.
@MainActor
final class ControllerBusSwitch: ObservableObject {
    @Published private(set) var status: ControllerBusStatus?
    @Published private(set) var busy = false
    /// The script's reason, when it refused. Not an error -- a bottle was up,
    /// or the engine is not the one the set was built for -- and shown as a
    /// sentence in orange, the way PatchAll shows its refusals.
    @Published private(set) var refusedReason: String?

    /// Read what the engine holds. Off the main actor: it runs a script.
    func refresh(engine: String?) async {
        status = await Task.detached { ControllerBusStatus.read(engineAppPath: engine) }.value
    }

    /// Install or remove, then read the engine again. Always run, never
    /// skipped on what the last reading said: that reading may be of another
    /// engine, and both directions are idempotent in the script -- a second
    /// install re-copies and leaves the backups alone, a second restore has
    /// nothing to restore. Nothing is run without an engine; the setting is
    /// kept either way and applied to the next engine made.
    func apply(_ action: ControllerBusStatus.Action, engine: String?) async {
        guard let engine, !engine.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        refusedReason = nil
        let name = URL(fileURLWithPath: engine).lastPathComponent
        let verb = action == .install ? "installed into" : "removed from"
        do {
            let state = try await Task.detached {
                switch action {
                case .install: return try BundledControllerBus.install(intoEngineAt: engine)
                case .remove:  return try BundledControllerBus.restore(fromEngineAt: engine)
                }
            }.value
            console.log("controller bus \(verb) \(name); the engine now reports \(state?.rawValue ?? "nothing")")
        } catch {
            refusedReason = error.localizedDescription
            console.warn("controller bus not \(verb) \(name): \(error.localizedDescription)")
        }
        await refresh(engine: engine)
    }
}
