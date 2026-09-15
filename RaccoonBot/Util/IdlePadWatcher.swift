//
//  IdlePadWatcher.swift
//  RaccoonBot
//
//  Turns off a DualSense on Bluetooth that nobody is using, while RaccoonBot is
//  open and no game it launched is running.
//
//  The case it exists for is the one the engine cannot see: a pad that
//  connected while wine held it gets no macOS gamepad driver, and once the game
//  and Steam have exited nothing ever turns it off (measured overnight on
//  2026-09-12/13; see IdlePadPowerOff). While a game runs, the engine holds the
//  pad and looks after it itself, so this stands aside.
//
//  How it stays out of the way:
//  - Off means no manager, no open device and no timer at all.
//  - Each pad is opened shared (kIOHIDOptionsTypeNone), never seized. An open
//    or a request refused with kIOReturnExclusiveAccess means somebody else
//    holds the pad, and the clock starts again.
//  - A pad that sends RaccoonBot no readable report for IdlePadPowerOff.reportGap
//    is not being watched, and silence is never idleness: a seized pad sends
//    nobody but its holder anything. Such a pad is opened again after 30 s,
//    then less and less often, at most every 10 minutes.
//  - When Play is pressed, and for as long as a game is running, every pad is
//    closed and every clock reset, so the engine is the only one opening it.
//  - One timer a minute with generous tolerance, so App Nap can coalesce it.
//    Every input report still wakes the main thread, about 64 a second per
//    pad; reading one allocates nothing. What that costs is not measured yet.
//
//  All decisions are IdlePadPowerOff.PadState's; this file only carries them
//  out against IOKit.
//
//  Seen once, 2026-09-14, on a DualSense Edge with the 10-minute setting: the
//  request went out when WindowServer's own idle clock for the pad read 630 s,
//  the pad turned off, and the user saw no Input Monitoring prompt. Not
//  measured: what the watcher costs, and anything about the engine's side
//  inside a game.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import IOKit.hid

/// The C callbacks, outside the main actor so they can be C function pointers.
/// Each one hops straight onto the main actor: the manager and every device are
/// scheduled on the main run loop, so that is where they are called.
nonisolated private enum IdlePadCallbacks {

    static let matched: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let watcher = UInt(bitPattern: context)
        MainActor.assumeIsolated {
            IdlePadWatcher.from(watcher)?.arrived(device)
        }
    }

    static let removed: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let watcher = UInt(bitPattern: context)
        MainActor.assumeIsolated {
            IdlePadWatcher.from(watcher)?.left(device)
        }
    }

    /// Read in place: the snapshot is taken from IOKit's buffer before the
    /// callback returns, and nothing is copied or allocated.
    static let report: IOHIDReportCallback = { context, result, _, _, _, bytes, length in
        guard let context, result == kIOReturnSuccess, length > 0 else { return }
        let pad = UInt(bitPattern: context)
        let snapshot = IdlePadPowerOff.snapshot(of: UnsafeBufferPointer(start: bytes, count: length))
        MainActor.assumeIsolated {
            IdlePadWatcher.shared.report(snapshot, fromPadAt: pad)
        }
    }
}

final class IdlePadWatcher {
    static let shared = IdlePadWatcher()

    /// Whether a game RaccoonBot launched is running. ScreenAwake's answer is
    /// the machine's (a game process in a watched bottle), not a log's.
    var gameIsRunning: () -> Bool = { ScreenAwake.gameRunning }
    /// Seconds that do not advance while the Mac sleeps.
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    private final class Pad {
        let device: IOHIDDevice
        let productID: Int
        let serial: String
        let buffer: UnsafeMutablePointer<UInt8>
        var state = IdlePadPowerOff.PadState()

        init(device: IOHIDDevice, productID: Int, serial: String) {
            self.device = device
            self.productID = productID
            self.serial = serial
            buffer = .allocate(capacity: IdlePadWatcher.bufferLength)
            buffer.initialize(repeating: 0, count: IdlePadWatcher.bufferLength)
        }

        deinit { buffer.deallocate() }

        var name: String {
            (productID == SonyPads.dualSenseEdge ? "DualSense Edge" : "DualSense") + " (\(serial))"
        }
    }

    /// A 0x31 is 78 bytes; room to spare.
    nonisolated static let bufferLength = 128

    private var manager: IOHIDManager?
    private var timer: Timer?
    private var pads: [Pad] = []
    private var minutes = 0

    /// Whether anything is set up: a manager and a timer. False after Off.
    var isWatching: Bool { manager != nil || timer != nil }

    static func from(_ address: UInt) -> IdlePadWatcher? {
        guard let raw = UnsafeRawPointer(bitPattern: address) else { return nil }
        return Unmanaged<IdlePadWatcher>.fromOpaque(raw).takeUnretainedValue()
    }

    /// Follow the setting. Off tears everything down; any other value starts
    /// watching if it was not already.
    func apply(minutes raw: Int) {
        let chosen = IdlePadPowerOff.pickable(raw)
        let was = minutes
        minutes = chosen
        if chosen == 0 {
            guard isWatching else { return }
            stop()
            console.log("controller: turning off an idle DualSense is off; no pad is watched")
            return
        }
        if manager == nil { start() }
        if was != chosen {
            console.log("controller: a DualSense on Bluetooth with no stick, trigger or button input for \(chosen) minutes "
                        + "is asked to turn off while no game is running")
        }
    }

    /// A launch is starting: every pad is let go and whatever was idle before
    /// it starts again once the game is over.
    func launchStarted() {
        pads.forEach { carryOut($0.state.standAside(), for: $0) }
    }

    // MARK: - Manager

    private func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = SonyPads.models.map {
            [kIOHIDVendorIDKey: SonyPads.vendorID, kIOHIDProductIDKey: $0, kIOHIDTransportKey: "Bluetooth"] as [String: Any]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, IdlePadCallbacks.matched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, IdlePadCallbacks.removed, context)
        // The manager itself is not opened: each pad is opened on its own, so a
        // refusal is seen per pad rather than folded into one result.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.manager = manager

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 20
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        pads.forEach(close)
        pads.removeAll()
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        manager = nil
    }

    fileprivate func arrived(_ device: IOHIDDevice) {
        guard manager != nil, !pads.contains(where: { $0.device === device }) else { return }
        guard let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
              SonyPads.models.contains(pid),
              IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String == "Bluetooth"
        else { return }
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? "no serial"
        let pad = Pad(device: device, productID: pid, serial: serial)
        pads.append(pad)
        // Not while a game runs: the engine is about to hold it, or already does.
        carryOut(pad.state.arrived(gameRunning: gameIsRunning(), at: now()), for: pad)
    }

    fileprivate func left(_ device: IOHIDDevice) {
        guard let index = pads.firstIndex(where: { $0.device === device }) else { return }
        let pad = pads.remove(at: index)
        if let askedAt = pad.state.askedAt {
            console.log("controller: the \(pad.name) disconnected \(Int(now() - askedAt)) s after it was asked to turn off")
        }
        close(pad)
    }

    // MARK: - One pad

    private static func answer(_ result: IOReturn) -> IdlePadPowerOff.Answer {
        switch result {
        case kIOReturnSuccess: return .success
        case kIOReturnExclusiveAccess: return .exclusiveAccess
        default: return .other(result)
        }
    }

    private static func hex(_ code: Int32) -> String {
        String(format: "%08x", UInt32(bitPattern: code))
    }

    private func carryOut(_ action: IdlePadPowerOff.PadState.Action, for pad: Pad) {
        switch action {
        case .none: break
        case .open: open(pad)
        case .close: close(pad)
        case .reopen: close(pad); open(pad)
        case .powerOff: powerOff(pad)
        }
    }

    private func open(_ pad: Pad) {
        let result = IOHIDDeviceOpen(pad.device, IOOptionBits(kIOHIDOptionsTypeNone))
        if let refusal = pad.state.opened(Self.answer(result), at: now()) {
            console.log("controller: the \(pad.name) could not be opened to watch for input "
                        + (refusal == .exclusiveAccess ? "because another process holds it " : "")
                        + "(IOReturn 0x\(Self.hex(result))); it is not counted as idle")
        }
        guard pad.state.isOpen else { return }
        let context = Unmanaged.passUnretained(pad).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(pad.device, pad.buffer, Self.bufferLength, IdlePadCallbacks.report, context)
        IOHIDDeviceScheduleWithRunLoop(pad.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func close(_ pad: Pad) {
        guard pad.state.isOpen else { return }
        IOHIDDeviceRegisterInputReportCallback(pad.device, pad.buffer, Self.bufferLength, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(pad.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(pad.device, IOOptionBits(kIOHIDOptionsTypeNone))
        pad.state.closed()
    }

    fileprivate func report(_ snapshot: IdlePadPowerOff.Snapshot?, fromPadAt address: UInt) {
        guard let pad = pads.first(where: { UInt(bitPattern: Unmanaged.passUnretained($0).toOpaque()) == address })
        else { return }
        if case .stillUp(let seconds) = pad.state.heard(snapshot, at: now()) {
            console.warn("controller: the \(pad.name) is still sending input \(seconds) s after it was asked "
                         + "to turn off: it did not turn off")
        }
    }

    private func tick() {
        let t = now()
        let running = gameIsRunning()
        for pad in pads {
            carryOut(pad.state.tick(minutes: minutes, gameRunning: running, at: t), for: pad)
        }
    }

    private func powerOff(_ pad: Pad) {
        let report = IdlePadPowerOff.powerOffReport()
        let result = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(pad.device, kIOHIDReportTypeFeature, CFIndex(IdlePadPowerOff.featureReportID),
                                 $0.baseAddress!, $0.count)
        }
        switch pad.state.requested(Self.answer(result), at: now()) {
        case .heldElsewhere:
            console.log("controller: the \(pad.name) was not asked to turn off: another process holds it")
        case .asked:
            console.warn("controller: the \(pad.name) had no stick, trigger or button input for \(minutes) minutes "
                         + "and no game is running: asked it to turn off (feature report 0x08)")
        case .failed(let code):
            console.warn("controller: asking the \(pad.name) to turn off after \(minutes) minutes without input "
                         + "failed (IOReturn 0x\(Self.hex(code))); not asked again until it is used")
        }
    }
}
