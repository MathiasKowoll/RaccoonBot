//
//  GamepadInput.swift
//  RaccoonBot
//
//  Reading a game controller, and knowing when not to.
//
//  macOS pairs a DualSense or an Xbox pad itself and GameController reports it,
//  so there is no driver here and no per-pad handling: what this needs is the
//  extended gamepad profile, which both provide.
//
//  THE PART THAT IS NOT ABOUT READING. The controller belongs to the game the
//  moment one starts. A launcher that keeps reading it moves its own selection
//  behind the game somebody is playing, and the next press lands on whatever
//  ended up under it. So this suspends, and the signal it suspends on is the
//  one this application already trusts for tearing a bottle down: `playingID`,
//  set from the tracker's onLoad and cleared by its onTerminate. That tracker
//  is the piece that knows a launcher exiting is not a game finishing, which is
//  a distinction no window-focus check makes.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import GameController
import Combine

@MainActor
final class GamepadInput: ObservableObject {

    enum Press { case select, back, options }

    /// A pad is connected. The interface uses it to show its hints only when
    /// they mean something.
    @Published private(set) var connected = false

    /// Nothing is read while this is true.
    var suspended = false {
        didSet { if suspended { held = nil; repeatTask?.cancel(); repeatTask = nil } }
    }

    var onMove: ((GridFocus.Direction) -> Void)?
    var onPress: ((Press) -> Void)?

    /// How far a stick must go before it counts. Sticks rest off centre and a
    /// worn one rests further, so a small reading is not a direction.
    private let deadZone: Float = 0.55

    /// Held-down repeat, in the shape every menu uses: a pause before the
    /// second step so a single press cannot become two, then steady.
    private let firstRepeat = Duration.milliseconds(400)
    private let nextRepeat = Duration.milliseconds(110)

    private var held: GridFocus.Direction?
    private var repeatTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        // Explicit rather than default: the whole point is that this stops
        // reading when the game takes over, and a background-monitoring pad
        // would defeat the suspension above by delivering anyway.
        GCController.shouldMonitorBackgroundEvents = false
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) {
            [weak self] note in
            MainActor.assumeIsolated { self?.attach(note.object as? GCController) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnected() }
        })
        GCController.controllers().forEach(attach)
        refreshConnected()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func refreshConnected() {
        connected = GCController.controllers().contains { $0.extendedGamepad != nil }
        if !connected { held = nil; repeatTask?.cancel(); repeatTask = nil }
    }

    private func attach(_ controller: GCController?) {
        guard let pad = controller?.extendedGamepad else { return }
        pad.valueChangedHandler = { [weak self] pad, _ in
            MainActor.assumeIsolated { self?.read(pad) }
        }
        refreshConnected()
    }

    /// One reading of the whole pad.
    ///
    /// Direction comes from the d-pad or the left stick, whichever is pushed;
    /// they are the same answer to a person and keeping them separate only
    /// produces two ways for the same press to behave differently.
    private func read(_ pad: GCExtendedGamepad) {
        guard !suspended else { return }

        if pad.buttonA.isPressed { press(.select) }
        if pad.buttonB.isPressed { press(.back) }
        if pad.buttonY.isPressed { press(.options) }

        let direction = self.direction(from: pad)
        guard direction != held else { return }
        held = direction
        repeatTask?.cancel()
        repeatTask = nil
        guard let direction else { return }
        onMove?(direction)
        repeatTask = Task { [weak self, firstRepeat, nextRepeat] in
            try? await Task.sleep(for: firstRepeat)
            while !Task.isCancelled {
                guard let self, self.held == direction, !self.suspended else { return }
                self.onMove?(direction)
                try? await Task.sleep(for: nextRepeat)
            }
        }
    }

    private func direction(from pad: GCExtendedGamepad) -> GridFocus.Direction? {
        if pad.dpad.left.isPressed { return .left }
        if pad.dpad.right.isPressed { return .right }
        if pad.dpad.up.isPressed { return .up }
        if pad.dpad.down.isPressed { return .down }
        let stick = pad.leftThumbstick
        // Whichever axis is further out wins, so a diagonal push is one
        // direction rather than two fighting.
        if abs(stick.xAxis.value) > abs(stick.yAxis.value) {
            if stick.xAxis.value <= -deadZone { return .left }
            if stick.xAxis.value >= deadZone { return .right }
        } else {
            if stick.yAxis.value >= deadZone { return .up }
            if stick.yAxis.value <= -deadZone { return .down }
        }
        return nil
    }

    /// A button reports pressed on every reading while it is down, so this
    /// fires once per press and waits for the release.
    private var down: Set<String> = []
    private func press(_ press: Press) {
        let key = "\(press)"
        guard !down.contains(key) else { return }
        down.insert(key)
        onPress?(press)
        Task { [weak self] in
            while let self, self.isStillDown(press) { try? await Task.sleep(for: .milliseconds(40)) }
            self?.down.remove(key)
        }
    }

    private func isStillDown(_ press: Press) -> Bool {
        guard let pad = GCController.controllers().compactMap({ $0.extendedGamepad }).first else { return false }
        switch press {
        case .select:  return pad.buttonA.isPressed
        case .back:    return pad.buttonB.isPressed
        case .options: return pad.buttonY.isPressed
        }
    }
}
