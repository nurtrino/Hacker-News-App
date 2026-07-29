import Foundation

/// A renderable piece of a comment body.
enum RichBlock: Hashable {
    case paragraph(AttributedString)
    case code(String)
}

/// A small, targeted parser for the HTML subset Hacker News actually emits.
///
/// HN bodies only ever contain unclosed `<p>`, `<i>`/`<b>`, `<a href>`,
/// `<pre><code>` and character entities. Handing that to
/// `NSAttributedString(data:options:)` would drag in WebKit, block the main
/// thread and lose the code blocks, so this walks the string directly instead.
enum HNHTML {

    // MARK: - Public entry points

    static func parse(_ html: String) -> [RichBlock] {
        guard !html.isEmpty else { return [] }

        var blocks: [RichBlock] = []
        var current = AttributedString()
        var pending = ""
        var codeBuffer = ""

        var italicDepth = 0
        var boldDepth = 0
        var linkStack: [URL?] = []
        var inPre = false

        func flushRun() {
            guard !pending.isEmpty else { return }
            var run = AttributedString(decodeEntities(pending))
            pending = ""

            var intent: InlinePresentationIntent = []
            if italicDepth > 0 { intent.insert(.emphasized) }
            if boldDepth > 0 { intent.insert(.stronglyEmphasized) }
            if !intent.isEmpty { run.inlinePresentationIntent = intent }

            if let url = linkStack.last ?? nil { run.link = url }
            current.append(run)
        }

        func flushParagraph() {
            flushRun()
            let text = trimming(current)
            if !text.characters.isEmpty { blocks.append(.paragraph(text)) }
            current = AttributedString()
        }

        func flushCode() {
            let text = decodeEntities(codeBuffer)
            codeBuffer = ""
            let trimmed = text.trimmingCharacters(in: .newlines)
            if !trimmed.isEmpty { blocks.append(.code(trimmed)) }
        }

        var index = html.startIndex
        while index < html.endIndex {
            let character = html[index]
            guard character == "<" else {
                if inPre { codeBuffer.append(character) } else { pending.append(character) }
                index = html.index(after: index)
                continue
            }

            guard let close = html[index...].firstIndex(of: ">") else {
                // Stray '<' with no closing bracket: treat the rest as text.
                pending.append(contentsOf: html[index...])
                break
            }

            let tag = Tag(html[html.index(after: index)..<close])
            index = html.index(after: close)

            switch tag.name {
            case "p":
                if inPre {
                    codeBuffer.append("\n")
                } else {
                    flushParagraph()
                }
            case "br":
                if inPre {
                    codeBuffer.append("\n")
                } else {
                    flushRun()
                    current.append(AttributedString("\n"))
                }
            case "i", "em":
                flushRun()
                italicDepth = max(0, italicDepth + (tag.isClosing ? -1 : 1))
            case "b", "strong":
                flushRun()
                boldDepth = max(0, boldDepth + (tag.isClosing ? -1 : 1))
            case "a":
                flushRun()
                if tag.isClosing {
                    if !linkStack.isEmpty { linkStack.removeLast() }
                } else if !tag.isSelfClosing {
                    linkStack.append(tag.attribute("href").flatMap(sanitizedURL))
                }
            case "pre":
                if tag.isClosing {
                    inPre = false
                    flushCode()
                } else {
                    flushParagraph()
                    inPre = true
                }
            default:
                // Structural tags only in HN's output — the contents still
                // count, so there's nothing to do but keep reading.
                break
            }
        }

        if inPre { flushCode() }
        flushParagraph()
        return blocks
    }

    /// Tag-free, entity-decoded text — used for sharing, copying and snippets.
    static func plainText(_ html: String) -> String {
        var output = ""
        var index = html.startIndex

        while index < html.endIndex {
            let character = html[index]
            if character == "<", let close = html[index...].firstIndex(of: ">") {
                let tag = Tag(html[html.index(after: index)..<close])
                if tag.name == "p" || tag.name == "br" { output.append("\n") }
                index = html.index(after: close)
                continue
            }
            output.append(character)
            index = html.index(after: index)
        }

        return decodeEntities(output)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One-line preview of a comment, for search results and saved rows.
    static func snippet(_ html: String, limit: Int = 220) -> String {
        let text = plainText(html)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Tags

    private struct Tag {
        let raw: String
        let name: String
        let isClosing: Bool
        let isSelfClosing: Bool

        init(_ slice: Substring) {
            var body = slice.trimmingCharacters(in: .whitespacesAndNewlines)
            isClosing = body.hasPrefix("/")
            if isClosing { body.removeFirst() }
            isSelfClosing = body.hasSuffix("/")
            raw = body
            name = body.prefix { !$0.isWhitespace && $0 != "/" }.lowercased()
        }

        /// Value of an attribute, handling quoted and bare forms.
        func attribute(_ key: String) -> String? {
            guard let marker = raw.range(of: key + "=", options: [.caseInsensitive]) else {
                return nil
            }
            var rest = raw[marker.upperBound...]
            guard let quote = rest.first else { return nil }
            if quote == "\"" || quote == "'" {
                rest = rest.dropFirst()
                guard let end = rest.firstIndex(of: quote) else { return nil }
                return String(rest[..<end])
            }
            return String(rest.prefix { !$0.isWhitespace && $0 != ">" })
        }
    }

    /// Only http(s) links are followed — anything else in a comment body is
    /// either broken or trying to be clever.
    private static func sanitizedURL(_ string: String) -> URL? {
        let decoded = decodeEntities(string).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: decoded), let scheme = url.scheme?.lowercased() else {
            return nil
        }
        return (scheme == "http" || scheme == "https") ? url : nil
    }

    // MARK: - Entities

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}",
        "rdquo": "\u{201D}", "times": "×", "middot": "·", "deg": "°",
        "laquo": "«", "raquo": "»", "bull": "•", "dagger": "†", "copy": "©",
        "reg": "®", "trade": "™", "frac12": "½", "frac14": "¼", "sup2": "²",
        "sup3": "³", "micro": "µ", "plusmn": "±", "ne": "≠", "le": "≤",
        "ge": "≥", "rarr": "→", "larr": "←", "harr": "↔", "infin": "∞",
        "sect": "§", "para": "¶", "euro": "€", "pound": "£", "yen": "¥",
        "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç",
        "uuml": "ü", "ouml": "ö", "auml": "ä", "szlig": "ß", "ntilde": "ñ",
    ]

    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }

        var output = ""
        output.reserveCapacity(input.count)
        var index = input.startIndex

        while index < input.endIndex {
            let character = input[index]
            guard character == "&" else {
                output.append(character)
                index = input.index(after: index)
                continue
            }

            // Entities are short; anything longer is a literal ampersand.
            let horizon = input.index(index, offsetBy: 12, limitedBy: input.endIndex) ?? input.endIndex
            guard let semicolon = input[index..<horizon].firstIndex(of: ";") else {
                output.append(character)
                index = input.index(after: index)
                continue
            }

            let body = String(input[input.index(after: index)..<semicolon])
            if let decoded = replacement(forEntityBody: body) {
                output.append(decoded)
                index = input.index(after: semicolon)
            } else {
                output.append(character)
                index = input.index(after: index)
            }
        }

        return output
    }

    private static func replacement(forEntityBody body: String) -> String? {
        guard !body.isEmpty else { return nil }

        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }

        return namedEntities[body.lowercased()]
    }

    // MARK: - Helpers

    private static func trimming(_ input: AttributedString) -> AttributedString {
        var value = input
        while let first = value.characters.first, first.isWhitespace {
            value.removeSubrange(value.startIndex..<value.characters.index(after: value.startIndex))
        }
        while let last = value.characters.last, last.isWhitespace {
            value.removeSubrange(value.characters.index(before: value.endIndex)..<value.endIndex)
        }
        return value
    }
}
