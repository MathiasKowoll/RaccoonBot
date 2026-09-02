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
import AppKit
import GameController
import Combine

@MainActor
final class GamepadInput: ObservableObject {

    enum Press { case select, back, options }

    /// A pad is connected. The interface uses it to show its hints only when
    /// they mean something.
    @Published private(set) var connected = false

    /// The arrow keys have been used to move the selection. Drawn the same
    /// way as a pad from then on: a ring that appears on the first press and
    /// not before, so somebody who never touches the arrows never sees it.
    @Published private(set) var keyboardUsed = false

    /// Whether to draw the selection at all.
    var showsFocus: Bool { connected || keyboardUsed }

    private var keyMonitor: Any?

    /// Nothing is read while this is true.
    var suspended = false {
        didSet { if suspended { held = nil; repeatTask?.cancel(); repeatTask = nil } }
    }

    /// Who is listening. A stack, because two things can be on screen at
    /// once -- the grid and a sheet over it -- and the one on top is the one
    /// a press means. The grid takes the pad when the library appears; a
    /// sheet takes it on top while it is up and gives it back when it goes.
    ///
    /// A stack rather than a single pair of handlers because of what a single
    /// pair did: the grid re-wired itself the moment the sheet's title was
    /// cleared, and the sheet's onDisappear -- which runs after the dismissal
    /// animation -- then set both handlers to nil, taking the grid's with
    /// them. From then on nothing was listening and the pad was dead until
    /// the window was reopened. With a stack, the sheet's release removes its
    /// own entry and whatever was underneath is what is left, in whichever
    /// order SwiftUI chooses to run the two.
    struct Handlers {
        let onMove: (GridFocus.Direction) -> Void
        let onPress: (Press) -> Void
    }
    private var owners: [(id: UUID, handlers: Handlers)] = []

    /// Listen, on top of whoever is listening now. Keep the token.
    @discardableResult
    func take(onMove: @escaping (GridFocus.Direction) -> Void,
              onPress: @escaping (Press) -> Void) -> UUID {
        let id = UUID()
        owners.append((id, Handlers(onMove: onMove, onPress: onPress)))
        return id
    }

    /// Stop listening. Removes that owner wherever it sits, so releasing out
    /// of order -- which SwiftUI's appear and disappear ordering can produce
    /// -- never removes somebody else's handlers. Releasing twice is nothing.
    func release(_ id: UUID) {
        owners.removeAll { $0.id == id }
    }

    /// How many are listening; the tests read it, nothing else should.
    var listeners: Int { owners.count }

    func deliver(move direction: GridFocus.Direction) { owners.last?.handlers.onMove(direction) }
    func deliver(press: Press) { owners.last?.handlers.onPress(press) }

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

        // The keyboard, into the same stack. Arrows move, Return selects,
        // Escape goes back -- the same three things a pad does, delivered to
        // the same listener, so what is fixed for one is fixed for the other.
        //
        // A local monitor rather than onKeyPress, because onKeyPress needs the
        // view to hold keyboard focus and a grid of buttons does not reliably
        // have it. The monitor sees the key before any view does, which is
        // also why it has to step aside for text: an arrow while typing in a
        // field moves the caret, and taking it would make every field in the
        // options panel unusable from the keyboard.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.suspended else { return event }
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView { return event }
            guard let action = Self.action(for: event) else { return event }
            self.keyboardUsed = true
            switch action {
            case .move(let direction): self.deliver(move: direction)
            case .press(let press):    self.deliver(press: press)
            }
            return nil
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    enum KeyAction: Equatable {
        case move(GridFocus.Direction)
        case press(Press)
    }

    /// Which of ours a key is, or nil for one that is not ours. Kept apart
    /// from the monitor so the mapping can be stated in a test without an
    /// NSEvent.
    nonisolated static func action(forKeyCode keyCode: UInt16) -> KeyAction? {
        switch keyCode {
        case 126: return .move(.up)
        case 125: return .move(.down)
        case 123: return .move(.left)
        case 124: return .move(.right)
        case 36:  return .press(.select)   // Return
        case 76:  return .press(.select)   // Enter on the keypad
        case 49:  return .press(.select)   // Space, which is what opens a popup on macOS
        case 53:  return .press(.back)     // Escape
        default:  return nil
        }
    }

    private static func action(for event: NSEvent) -> KeyAction? {
        // Not with a modifier: Cmd-arrow and the like belong to the system.
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return nil }
        return action(forKeyCode: event.keyCode)
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
        deliver(move: direction)
        repeatTask = Task { [weak self, firstRepeat, nextRepeat] in
            try? await Task.sleep(for: firstRepeat)
            while !Task.isCancelled {
                guard let self, self.held == direction, !self.suspended else { return }
                self.deliver(move: direction)
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
        deliver(press: press)
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
