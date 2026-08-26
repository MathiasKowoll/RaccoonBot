//
//  WineRegistry.swift
//  RaccoonBot
//
//  Wine .reg file parser and editor with backup support.
//

import Foundation

enum WineRegValueType {
    case string(String)
    case dword(UInt32)
    case hex(Data)
    case expandString(String)
    case defaultValue(String)
}

struct WineRegValue {
    var type: WineRegValueType
    var rawLine: String // preserves original formatting for untouched values
}

class WineRegSection {
    var header: String       // e.g. "[Software\\\\Wine\\\\Explorer]"
    var timestamp: String?   // e.g. "1772562888"
    var timeLine: String?    // e.g. "#time=1dcab3c6a58a0ea"
    var values: [(key: String, value: WineRegValue)] = []
    var trailingLines: [String] = [] // blank lines or comments after last value

    init(header: String, timestamp: String? = nil, timeLine: String? = nil) {
        self.header = header
        self.timestamp = timestamp
        self.timeLine = timeLine
    }

    var path: String {
        // Strip brackets and timestamp: "[Software\\\\Wine\\\\Explorer] 12345" -> "Software\\\\Wine\\\\Explorer"
        let stripped = header.trimmingCharacters(in: .whitespaces)
        guard stripped.hasPrefix("[") else { return stripped }
        let inner = stripped.dropFirst()
        guard let closeBracket = inner.firstIndex(of: "]") else { return String(inner) }
        return String(inner[inner.startIndex..<closeBracket])
    }

    func getValue(forKey key: String) -> String? {
        guard let entry = values.first(where: { $0.key == key }) else { return nil }
        switch entry.value.type {
        case .string(let v): return v
        case .dword(let v): return String(v)
        case .expandString(let v): return v
        case .defaultValue(let v): return v
        case .hex: return nil
        }
    }

    func setValue(forKey key: String, stringValue: String) {
        guard let index = values.firstIndex(where: { $0.key == key }) else { return }
        values[index].value.type = .string(stringValue)
        values[index].value.rawLine = "\"\(key)\"=\"\(stringValue)\""
    }

    func addOrSetValue(forKey key: String, stringValue: String) {
        if let index = values.firstIndex(where: { $0.key == key }) {
            values[index].value.type = .string(stringValue)
            values[index].value.rawLine = "\"\(key)\"=\"\(stringValue)\""
        } else {
            let val = WineRegValue(type: .string(stringValue), rawLine: "\"\(key)\"=\"\(stringValue)\"")
            values.append((key: key, value: val))
        }
    }
    
    func setDword(forKey key: String, value: UInt32) {
        guard let index = values.firstIndex(where: { $0.key == key }) else {
            console.error("Couldn't find key \(key) when setting dword value")
            console.log(String(reflecting: values))
            return
        }
        values[index].value.type = .dword(value)
        values[index].value.rawLine = "\"\(key)\"=dword:\(String(format: "%08x", value))"
    }
    
    func addOrSetDword(forKey key: String, value: UInt32) {
        if let index = values.firstIndex(where: { $0.key == key }) {
            values[index].value.type = .dword(value)
            values[index].value.rawLine = "\"\(key)\"=dword:\(String(format: "%08x", value))"
        } else {
            // dword:, not a quoted string. Written as a string, wine stores a
            // REG_SZ where it expects a REG_DWORD and the setting has no
            // effect -- and the value looks right in a registry editor.
            let val = WineRegValue(type: .dword(value), rawLine: "\"\(key)\"=dword:\(String(format: "%08x", value))")
            values.append((key: key, value: val))
        }
    }
}

class WineRegistryFile {
    /**
     Loads the registry file from the URL when instanced, can save the files, and each section accessible in the sections array can be modified with the methods offered by the WineRegSection
     Usage:
     registryFile = WineRegistryFile(fileURL: regURL) -> set the URL of the registry file
     registryFile.load() -> load the file into the registryfile object
     section = registryFile.section(forPath: "Some\\\\Wine\\\\Path") -> get your section example: System\\\\CurrentControlSet\\\\Services\\\\winebus (startying from System as root and without the trailing \\, remember to escape the \)
     section?.getValue(forKey: "SomeKey") -> get value for the property "SomeKey"
     section?.addOrSetValue(forKey: "SomeOtherKey", stringValue: "SomeValue") -> set value for the property "SomeOtherKey", if the key doesn't exist it will add the key and set the value
     registryFile.save() -> Saves the file (this will also create a bacup named {{fileName}}.orig)
     */
    var headerLines: [String] = [] // "WINE REGISTRY Version 2", comments, #arch line
    var sections: [WineRegSection] = []
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Backup

    /// Creates a backup before writing.
    /// First call creates ".orig" backup. Subsequent calls create ".procyon-backup".
    func createBackup() throws {
        let f = FileManager.default
        let origPath = fileURL.appendingPathExtension("orig")
        let procyonPath = fileURL.appendingPathExtension("procyon-backup")

        if !f.fileExists(atPath: origPath.path(percentEncoded: false)) {
            try f.copyItem(at: fileURL, to: origPath)
            console.log("Created orig backup at \(origPath.lastPathComponent)")
        } else {
            // orig already exists, create/overwrite procyon backup
            if f.fileExists(atPath: procyonPath.path(percentEncoded: false)) {
                try f.removeItem(at: procyonPath)
            }
            try f.copyItem(at: fileURL, to: procyonPath)
            console.log("Created procyon backup at \(procyonPath.lastPathComponent)")
        }
    }

    // MARK: - Parse

    func load() throws {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var lines: [String] = []
        content.enumerateLines { line, _ in lines.append(line) }

        headerLines = []
        sections = []

        var currentSection: WineRegSection? = nil
        var inHeader = true

        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect section header: [Path\\Key] optional_timestamp
            if trimmed.hasPrefix("[") && !trimmed.hasPrefix("#") {
                // Finish previous section
                if let sec = currentSection {
                    sections.append(sec)
                }
                inHeader = false

                // Parse timestamp from header line
                var timestamp: String? = nil
                if let closeBracket = trimmed.firstIndex(of: "]") {
                    let afterBracket = trimmed[trimmed.index(after: closeBracket)...].trimmingCharacters(in: .whitespaces)
                    if !afterBracket.isEmpty {
                        timestamp = afterBracket
                    }
                }

                currentSection = WineRegSection(header: trimmed, timestamp: timestamp)
                continue
            }

            if inHeader {
                headerLines.append(line)
                continue
            }

            guard let section = currentSection else {
                headerLines.append(line)
                continue
            }

            // #time= line
            if trimmed.hasPrefix("#time=") {
                section.timeLine = trimmed
                continue
            }

            // Empty or comment line
            if trimmed.isEmpty || trimmed.hasPrefix(";;") || trimmed.hasPrefix("#") {
                section.trailingLines.append(line)
                continue
            }

            // Parse key=value
            if let parsed = parseRegValue(line: trimmed) {
                // A value too long for one line is written with a trailing
                // backslash and continued on the next. Those continuations
                // belong to this value: read line by line they match nothing,
                // fall through to trailingLines, and save() then writes them
                // after every value in the section -- so the backslash on the
                // first line swallows the next value's declaration and the
                // real bytes pile up at the end, attached to nothing.
                //
                // That is not a hypothetical. It is what emptied the H.264
                // decoder's InputTypes in a bottle on this machine and left
                // its OutputTypes carrying a format from the input list. The
                // bottle games launch from has 739 values of this shape, and
                // every launch rewrote the file.
                var whole = line
                while whole.hasSuffix("\\"), index < lines.count {
                    whole += "\n" + lines[index]
                    index += 1
                }
                let value = WineRegValue(type: parsed.value.type, rawLine: whole)
                section.values.append((key: parsed.key, value: value))
            } else {
                section.trailingLines.append(line)
            }
        }

        // Don't forget last section
        if let sec = currentSection {
            sections.append(sec)
        }
    }

    private func parseRegValue(line: String) -> (key: String, value: WineRegValue)? {
        // Default value: @="something"
        if line.hasPrefix("@=") {
            let val = String(line.dropFirst(2))
            let unquoted = unquote(val)
            return (key: "@", value: WineRegValue(type: .defaultValue(unquoted), rawLine: line))
        }

        // "Key"=value
        guard line.hasPrefix("\"") else { return nil }
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let key = unquote(String(parts[0]))
        let rawValue = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

        if rawValue.hasPrefix("dword:") {
            let hexStr = String(rawValue.dropFirst(6))
            let intVal = UInt32(hexStr, radix: 16) ?? 0
            return (key: key, value: WineRegValue(type: .dword(intVal), rawLine: line))
        } else if rawValue.hasPrefix("hex:") {
            return (key: key, value: WineRegValue(type: .hex(Data()), rawLine: line))
        } else if rawValue.hasPrefix("str(2):") {
            let inner = unquote(String(rawValue.dropFirst(7)))
            return (key: key, value: WineRegValue(type: .expandString(inner), rawLine: line))
        } else {
            let unquoted = unquote(rawValue)
            return (key: key, value: WineRegValue(type: .string(unquoted), rawLine: line))
        }
    }

    private func unquote(_ s: String) -> String {
        var str = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("\"") && str.hasSuffix("\"") && str.count >= 2 {
            str = String(str.dropFirst().dropLast())
        }
        return str
    }

    // MARK: - Lookup

    func section(forPath path: String) -> WineRegSection? {
        return sections.first { $0.path == path }
    }

    // MARK: - Write

    func save() throws {
        try createBackup()

        var output = ""

        // Header
        for line in headerLines {
            output += line + "\n"
        }

        // Sections
        for section in sections {
            output += section.header + "\n"
            if let timeLine = section.timeLine {
                output += timeLine + "\n"
            }
            for entry in section.values {
                output += entry.value.rawLine + "\n"
            }
            for trailing in section.trailingLines {
                output += trailing + "\n"
            }
        }

        do {
            try output.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            console.error("Coulnd't write registry file: \(error)")
        }
        console.log("Registry file saved to \(fileURL.lastPathComponent)")
    }
}
