//
//  MachineIdentity.swift
//  RaccoonBot
//
//  What machine a saved configuration was written on.
//
//  WHY A RECORD NEEDS THIS AT ALL. A configuration that makes a game playable
//  here is a claim, and a claim without the machine it was made on is the
//  mistake ProtonDB never recovered from: thousands of reports that contradict
//  each other because none of them says what it ran on. The community catalog
//  this feeds into keys everything on `applies_to`, and the hardware half of
//  that has to come from somewhere.
//
//  WHAT IT IS NOT FOR, and this is worth writing down because the scope moved
//  once already. These records are about whether a game RUNS -- codecs, wine
//  overrides, a backend, a frame cap a title needs to not break, the controller
//  switches. They are not graphics presets and not a performance target;
//  in-game quality and frame rate are the player's own business. So the machine
//  is a DIAGNOSTIC dimension, not a partitioning key: most records will apply
//  to every Mac, and this exists for the minority that do not and for the
//  moment when a fix works for one person and not another.
//
//  THE VARIANT IS THE UNIT, not the generation. An M4 base has ten GPU cores
//  and an M4 Max has forty; they are not the same machine and "M4" cannot mean
//  both. `machdep.cpu.brand_string` gives the variant exactly -- "Apple M4 Max"
//  -- so there is nothing to infer.
//
//  AND THE ORDER IS A GRID, NOT A LINE, which matters to whoever reads these
//  later. Base < Pro < Max < Ultra holds inside a generation, and M1 < M2 < M3
//  < M4 holds inside a tier, but an M1 Max and an M4 base are not ordered by
//  either: 32 GPU cores against 10. So "it ran on an M1" is a safe floor
//  because the base M1 is the weakest Apple Silicon there is, while "it ran on
//  an M1 Pro" implies nothing about an M4 base. Nothing here draws that
//  conclusion; the fields are recorded and the comparing is somebody else's
//  job, on purpose.
//
//  Memory is its own axis. An 8 GB M1 and a 16 GB M1 are the same chip and not
//  the same machine for a game that stretches, and the chip's name does not say
//  which you have.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import IOKit

/// The machine, as much of it as matters and no more.
nonisolated struct MachineIdentity: Codable, Equatable {
    /// The whole brand string, e.g. "Apple M4 Max". Kept raw as well as split,
    /// because a chip this build has never heard of still has to be recorded
    /// faithfully rather than parsed into whatever the parser happens to know.
    let chip: String
    /// "M4" from "Apple M4 Max", or the raw string when it does not parse.
    let family: String
    /// "Max", "Pro", "Ultra", or "" for a base part.
    let tier: String
    /// `hw.model`, e.g. "Mac16,5" -- the exact machine, where the chip is the
    /// exact silicon. Two models can share a chip and differ in cooling.
    let model: String
    /// GPU cores, read from IOKit. 0 when it could not be read, which is a
    /// value and not a failure: nothing here refuses to record a machine for
    /// want of one number.
    let gpuCores: Int
    /// Physical memory in whole gigabytes.
    let memoryGB: Int
    /// e.g. "27.0".
    let macOS: String

    /// One line, for a log or a record that wants a string rather than a
    /// struct. Stable enough to compare, loose enough to read.
    var described: String {
        let cores = gpuCores > 0 ? ", \(gpuCores) GPU cores" : ""
        return "\(chip) (\(model))\(cores), \(memoryGB) GB, macOS \(macOS)"
    }

    /// Read once. Nothing here changes while the application is running, and
    /// `system_profiler` is not involved -- every value is a sysctl or one
    /// IOKit property, so this costs microseconds rather than a subprocess.
    static let current: MachineIdentity = detect()

    static func detect() -> MachineIdentity {
        let brand = sysctlString("machdep.cpu.brand_string") ?? ""
        let (family, tier) = split(brand: brand)
        return MachineIdentity(chip: brand.isEmpty ? "unknown" : brand,
                               family: family,
                               tier: tier,
                               model: sysctlString("hw.model") ?? "unknown",
                               gpuCores: gpuCoreCount(),
                               memoryGB: Int((sysctlUInt64("hw.memsize") ?? 0) / 1_073_741_824),
                               macOS: ProcessInfo.processInfo.operatingSystemVersionString.components(separatedBy: " ").dropFirst().first ?? "unknown")
    }

    /// "Apple M4 Max" -> ("M4", "Max"). "Apple M2" -> ("M2", ""). Anything that
    /// does not look like an Apple part keeps the whole string as the family
    /// and takes no tier, because guessing a tier for silicon this build has
    /// never seen would be inventing the one field a reader would trust.
    static func split(brand: String) -> (String, String) {
        let words = brand.split(separator: " ").map(String.init)
        guard let i = words.firstIndex(where: { $0.count >= 2 && $0.first == "M" && $0.dropFirst().allSatisfy(\.isNumber) })
        else { return (brand.isEmpty ? "unknown" : brand, "") }
        let known = ["Pro", "Max", "Ultra"]
        let next = i + 1 < words.count ? words[i + 1] : ""
        return (words[i], known.contains(next) ? next : "")
    }

    // MARK: reading the machine

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let s = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// The GPU's own `gpu-core-count`, off the accelerator in the IO registry.
    /// It is the number that separates an M4 from an M4 Max far better than the
    /// name does, and it is one property read rather than a `system_profiler`
    /// that takes seconds.
    private static func gpuCoreCount() -> Int {
        let match = IOServiceMatching("AGXAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if let value = IORegistryEntryCreateCFProperty(entry, "gpu-core-count" as CFString,
                                                           kCFAllocatorDefault, 0)?.takeRetainedValue(),
               let number = value as? NSNumber {
                return number.intValue
            }
        }
        return 0
    }
}
