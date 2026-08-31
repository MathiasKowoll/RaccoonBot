import Foundation

/// What somebody typed into the environment-variables box, made safe to hand
/// to `env`.
///
/// `env` takes `NAME=VALUE` and nothing else. Anything before the first `=`
/// that is not a name it treats as the program to run, so one stray space
/// turns the whole launch into:
///
///     env: GST_PLUGIN_PATH: No such file or directory
///
/// and the game never starts. Nothing else goes wrong -- no crash, no dialog,
/// just a spinner that never stops. It took an evening to find, from
///
///     "GST_PLUGIN_PATH" = "/Users/…/gstreamer-1.0"
///
/// which is exactly what a person pastes out of a README.
///
/// So what is typed is repaired where it can be and dropped where it cannot,
/// and either way the log says which.
enum EnvAssignments {

    /// The names somebody asked to have REMOVED rather than set.
    ///
    /// Written as a bare name with a leading `-`:
    ///
    ///     -MVK_CONFIG_UE4_HACK_ENABLED
    ///
    /// Absence is not a value, and until this existed there was no way to say
    /// it. A toggle that is off does not remove its variable, it writes the
    /// opposite -- `MVK_CONFIG_UE4_HACK_ENABLED=0` rather than nothing -- so
    /// "we set it to 0 and it still failed" says nothing about whether setting
    /// it at all is the problem. Comparing against a launch that names neither
    /// needs a way to name neither.
    static func removals(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isNewline || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("-") && !$0.contains("=") }
            .map { String($0.dropFirst()).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } }
    }

    /// The same removals as `env` arguments: `-u NAME` for each.
    static func removalArguments(_ text: String) -> String {
        let names = removals(text)
        return names.isEmpty ? "" : names.map { "-u \($0)" }.joined(separator: " ") + " "
    }

    /// Repairs `text` into assignments `env` will accept.
    static func normalised(_ text: String) -> String {
        let cleaned = assignments(in: text).map { "\($0.name)=\(quoted($0.value))" }
        return cleaned.joined(separator: " ")
    }

    struct Assignment: Equatable {
        let name: String
        let value: String
    }

    /// Splits on whitespace that is not inside quotes, then on the first `=`
    /// that is not inside quotes.
    static func assignments(in text: String) -> [Assignment] {
        var found: [Assignment] = []
        for token in tokens(in: text) {
            guard let split = token.firstIndex(of: "=") else {
                console.warn("ignoring \(token): an environment variable needs a NAME=VALUE")
                continue
            }
            let name = unquoted(String(token[token.startIndex..<split]))
                .trimmingCharacters(in: .whitespaces)
            let value = unquoted(String(token[token.index(after: split)...]))
            guard isAName(name) else {
                console.warn("ignoring \(token): \(name.isEmpty ? "no name" : "\(name) is not a variable name")")
                continue
            }
            found.append(Assignment(name: name, value: value))
        }
        return found
    }

    /// Whitespace-separated, except inside quotes, and joining `NAME = VALUE`
    /// back together -- a space either side of the `=` is the commonest way to
    /// write this and the least deserving of silent failure.
    private static func tokens(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character.isWhitespace {
                if !current.isEmpty { out.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { out.append(current) }

        // Rejoin "NAME", "=", "VALUE" and "NAME=", "VALUE" and "NAME", "=VALUE".
        var joined: [String] = []
        var index = 0
        while index < out.count {
            var piece = out[index]
            while (piece == "=" || piece.hasSuffix("=") || (index + 1 < out.count && out[index + 1].hasPrefix("=")))
                    && index + 1 < out.count {
                piece += out[index + 1]
                index += 1
                if piece.contains("=") && !piece.hasSuffix("=") { break }
            }
            joined.append(piece)
            index += 1
        }
        return joined
    }

    private static func unquoted(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        for quote in ["\"", "'"] where trimmed.count >= 2
            && trimmed.hasPrefix(quote) && trimmed.hasSuffix(quote) {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    /// A name `env` will accept: letters, digits and underscores, not starting
    /// with a digit.
    private static func isAName(_ name: String) -> Bool {
        guard let first = name.first, !first.isNumber else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Quoted only when it needs to be, so a launch line stays readable.
    private static func quoted(_ value: String) -> String {
        let needsQuotes = value.isEmpty || value.contains(where: { $0.isWhitespace })
        return needsQuotes ? "\"\(value)\"" : value
    }
}
