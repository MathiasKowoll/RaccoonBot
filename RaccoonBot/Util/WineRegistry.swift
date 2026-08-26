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
    /// The marker lines wine writes between a section's header and its first
    /// value, in the order it wrote them.
    ///
    /// Not just #time. Wine also writes #link, which is how a registry key is
    /// marked as a symbolic link -- 324 of them across the bottles on this
    /// machine. Treated as a comment it was moved below the values, and wine
    /// no longer read the key as a link. The bottle games launch from has
    /// none left; the one beside it still has 54.
    ///
    /// Kept as a list rather than named fields so a marker nobody here has
    /// heard of survives too.
    var preamble: [String] = []
    var timeLine: String? {
        get { preamble.first { $0.hasPrefix("#time=") } }
        set {
            preamble.removeAll { $0.hasPrefix("#time=") }
            if let newValue { preamble.insert(newValue, at: 0) }
        }
    }
    var values: [(key: String, value: WineRegValue)] = []
    var trailingLines: [String] = [] // blank lines or comments after last value

    init(header: String, timestamp: String? = nil, timeLine: String? = nil) {
        if let timeLine { self.preamble = [timeLine] }
        self.header = header
        self.timestamp = timestamp

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
    
    /// Returns whether anything actually changed.
    ///
    /// The caller uses it to decide whether to write the file at all. Rewriting
    /// 160,000 lines to set a value that already holds that value is all risk
    /// and no work, and after the first launch of a bottle it is every launch.
    @discardableResult
    func addOrSetDword(forKey key: String, value: UInt32) -> Bool {
        if let index = values.firstIndex(where: { $0.key == key }) {
            let line = "\"\(key)\"=dword:\(String(format: "%08x", value))"
            if values[index].value.rawLine == line { return false }
            values[index].value.type = .dword(value)
            values[index].value.rawLine = line
            return true
        } else {
            // dword:, not a quoted string. Written as a string, wine stores a
            // REG_SZ where it expects a REG_DWORD and the setting has no
            // effect -- and the value looks right in a registry editor.
            let val = WineRegValue(type: .dword(value), rawLine: "\"\(key)\"=dword:\(String(format: "%08x", value))")
            values.append((key: key, value: val))
            return true
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

    /// Whether this file can be written back at all.
    ///
    /// Decided at load time by rebuilding the file from what was parsed and
    /// comparing it to what was read. If the two differ, the parser did not
    /// understand something, and writing would put that misunderstanding on
    /// disk. Refusing is the only safe answer: a bottle registry has one copy
    /// and the things it holds -- what can decode a video, what a game
    /// installed -- are not reconstructible from anywhere else.
    private(set) var isFaithful = false
    private(set) var infidelity: String?
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
        parse(content)
        checkFidelity(against: content)
    }

    fileprivate func parse(_ content: String) {
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

            // A marker line, before any value: #time=, #link, or whatever
            // else wine decides to write there. Position is meaning -- these
            // describe the section, and below the values they describe
            // nothing.
            if trimmed.hasPrefix("#") && section.values.isEmpty {
                section.preamble.append(trimmed)
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
        //
        // Split at the quote that closes the name, not at the first "=".
        // A name can contain both: wine writes SxS assembly identities like
        // "Microsoft.VC90.ATL,version=\"9.0.30729.6161\",...,type=\"win32\"",
        // and cutting at the first "=" gave two different assemblies the same
        // truncated name.
        guard line.hasPrefix("\"") else { return nil }
        var index = line.index(after: line.startIndex)
        var escaped = false
        var closing: String.Index? = nil
        while index < line.endIndex {
            let c = line[index]
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { closing = index; break }
            index = line.index(after: index)
        }
        guard let closing,
              line.index(after: closing) < line.endIndex,
              line[line.index(after: closing)] == "=" else { return nil }

        let key = String(line[line.index(after: line.startIndex)..<closing])
        let rawValue = String(line[line.index(closing, offsetBy: 2)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

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

    /// The file as this model would write it.
    private func serialise() -> String {
        var output = ""
        for line in headerLines { output += line + "\n" }
        for section in sections {
            output += section.header + "\n"
            for marker in section.preamble { output += marker + "\n" }
            for entry in section.values { output += entry.value.rawLine + "\n" }
            for trailing in section.trailingLines { output += trailing + "\n" }
        }
        return output
    }

    /// Can what was just read be written back unchanged?
    ///
    /// Asked before any edit, so the answer is about the parser rather than
    /// about the change. Everything this reader does not model -- a value
    /// shape it does not know, a line it puts in the wrong place, a line
    /// ending it normalises -- shows up here as a difference, whether or not
    /// anyone thought of that shape in advance. That generality is the point:
    /// the multi-line binary values this once destroyed were not on anybody's
    /// list either.
    private func checkFidelity(against original: String) {
        let rebuilt = serialise()
        if rebuilt == original || rebuilt == original + "\n" {
            isFaithful = true
            infidelity = nil
            return
        }
        isFaithful = false
        let a = original.components(separatedBy: "\n")
        let b = rebuilt.components(separatedBy: "\n")
        let at = zip(a, b).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        if let at {
            infidelity = "line \(at + 1): read \"\(a[at].prefix(60))\" but would write \"\(b[at].prefix(60))\""
        } else {
            infidelity = "\(a.count) lines read, \(b.count) would be written"
        }
        console.error("Refusing to write \(fileURL.lastPathComponent): \(infidelity ?? "")")
    }

    func save() throws {
        guard isFaithful else {
            throw WineRegistryError.wouldNotSurviveRewriting(file: fileURL.lastPathComponent,
                                                             detail: infidelity ?? "load() was never called")
        }
        let output = serialise()

        // And the edits have to survive too. Reading the text back and
        // comparing it to the model catches a change that produced something
        // this parser cannot read -- the same failure, arriving by the other
        // door.
        let check = WineRegistryFile(fileURL: fileURL)
        check.parse(output)
        if let lost = check.firstValueMissing(comparedTo: self) {
            throw WineRegistryError.wouldNotSurviveRewriting(file: fileURL.lastPathComponent,
                                                             detail: "the edit made \(lost) unreadable")
        }

        try createBackup()
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
        console.log("Registry file saved to \(fileURL.lastPathComponent)")
    }

    /// The first value the other model has that this one does not, in order.
    /// Nil when nothing was lost.
    ///
    /// Compared position by position rather than through a dictionary keyed on
    /// the parsed key name. Keying on the name assumed the name was read
    /// correctly, and this file has 120 keys where it is not: wine's SxS
    /// assembly identities carry an unescaped "=" inside the quoted name --
    /// `"Microsoft.VC90.ATL,version=\"9.0.30729.6161\",...,type=\"win32\""` --
    /// so the amd64 and x86 rows collapsed onto one entry and the check
    /// reported a loss that had not happened. A guard that refuses a file it
    /// could have written correctly is a feature that quietly stops working.
    fileprivate func firstValueMissing(comparedTo other: WineRegistryFile) -> String? {
        if sections.count != other.sections.count {
            return "\(other.sections.count) sections read, \(sections.count) written"
        }
        for (mine, theirs) in zip(sections, other.sections) {
            if mine.header != theirs.header { return "section \(theirs.header)" }
            if mine.values.count != theirs.values.count {
                return "\(theirs.values.count) values in \(theirs.path), \(mine.values.count) written"
            }
            for (a, b) in zip(mine.values, theirs.values) where a.value.rawLine != b.value.rawLine {
                return "\(b.key) in \(theirs.path)"
            }
        }
        return nil
    }
}

enum WineRegistryError: LocalizedError {
    case wouldNotSurviveRewriting(file: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .wouldNotSurviveRewriting(let file, let detail):
            return "\(file) holds something this build cannot rewrite without losing it (\(detail)). Nothing was written."
        }
    }
}
