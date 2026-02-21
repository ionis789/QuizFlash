import Foundation

// =============================================================================
// MARK: - AIZoneParser
//
// Parsează textul generat de AI în ZoneModel-uri structurate.
//
// Suportă:
//   - Text simplu și paragrafe
//   - Liste cu bullet (- item sau * item)
//   - Blocuri matematice ($$...$$)
//   - CODE BLOCKS (```lang\ncode\n```) → zone cu fontFamily = .monospaced
//
// Convenție pentru blocuri de cod:
//   zone.fontFamily = .monospaced
//   zone.text      = "[LANG:java]\ncodul aici..." (dacă limba e specificată)
//               SAU = "codul aici..." (dacă nu e specificată)
//   zone.textStyle = .caption (font mai mic — standard pentru cod)
//
// =============================================================================

struct AIZoneParser {

    // =========================================================================
    // MARK: - Public Entry Point
    // =========================================================================

    static func parse(text: String) -> ZoneModel {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Scoate wrapper-ul de $ care înconjoară întreg textul (eroare GPT)
        cleaned = stripOuterDollarWrapper(cleaned)

        // Extrage blocurile în ordine (text + code fences amestecate)
        let segments = extractSegments(from: cleaned)

        if segments.isEmpty { return .empty() }

        // Un singur segment → returnat direct fără container
        if segments.count == 1 {
            return parseSegment(segments[0])
        }

        // Segmente multiple → container vertical
        let children = segments.map { parseSegment($0) }.filter { $0.hasContent || !$0.isLeaf }
        if children.isEmpty { return .empty() }
        if children.count == 1 { return children[0] }
        return ZoneModel.container(direction: .vertical, children: children)
    }

    // =========================================================================
    // MARK: - Segment Extraction
    //
    // Împarte textul în segmente alternante de:
    //   • CodeSegment  — tot ce e între ``` ``` (inclusiv tag-ul de limbă)
    //   • TextSegment  — tot restul textului
    // =========================================================================

    private enum Segment {
        case text(String)
        case code(language: String, body: String)
    }

    private static func extractSegments(from input: String) -> [Segment] {
        var segments: [Segment] = []
        var remaining = input

        // Pattern: ```optionalLang\n...code...\n```
        // Suportă backtick-uri normale și variante cu spații
        let fencePattern = #"```([a-zA-Z0-9+#\-]*)\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: fencePattern) else {
            return [.text(input)]
        }

        var lastEnd = input.startIndex

        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))

        for match in matches {
            guard let fullRange = Range(match.range, in: input) else { continue }

            // Text ÎNAINTE de code block
            let textBefore = String(input[lastEnd..<fullRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !textBefore.isEmpty {
                segments.append(.text(textBefore))
            }

            // Langue tag (group 1)
            let lang: String
            if let langRange = Range(match.range(at: 1), in: input) {
                lang = String(input[langRange]).trimmingCharacters(in: .whitespaces)
            } else {
                lang = ""
            }

            // Codul (group 2)
            let code: String
            if let codeRange = Range(match.range(at: 2), in: input) {
                code = String(input[codeRange]).trimmingCharacters(in: .newlines)
            } else {
                code = ""
            }

            if !code.isEmpty {
                segments.append(.code(language: lang, body: code))
            }

            lastEnd = fullRange.upperBound
        }

        // Text DUPĂ ultimul code block
        let textAfter = String(input[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !textAfter.isEmpty {
            segments.append(.text(textAfter))
        }

        // Dacă nu s-a găsit niciun code block → tratăm totul ca text
        if segments.isEmpty {
            segments.append(.text(input))
        }

        return segments
    }

    // =========================================================================
    // MARK: - Segment → ZoneModel
    // =========================================================================

    private static func parseSegment(_ segment: Segment) -> ZoneModel {
        switch segment {
        case .text(let content):
            return parseTextBlock(content)
        case .code(let language, let body):
            return makeCodeZone(language: language, body: body)
        }
    }

    // =========================================================================
    // MARK: - Code Zone
    // =========================================================================

    private static func makeCodeZone(language: String, body: String) -> ZoneModel {
        var zone = ZoneModel(contentType: .text)
        zone.fontFamily = .mono
        zone.textStyle = .caption // 14pt — dimensiune standard pentru cod

        // Prefixăm cu tag-ul de limbă dacă există, pentru a-l putea afișa în header
        if !language.isEmpty {
            zone.text = "[LANG:\(language.lowercased())]\n\(body)"
        } else {
            zone.text = body
        }

        return zone
    }

    // =========================================================================
    // MARK: - Text Block Parser
    //
    // Parsează un bloc de text pur (fără code fences) în zone structurate.
    // Suportă: bullet lists, paragrafe, blocuri matematice centrate.
    // =========================================================================

    private static func parseTextBlock(_ content: String) -> ZoneModel {
        let lines = content.components(separatedBy: "\n")
        var blocks: [String] = []
        var current = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !current.isEmpty {
                    blocks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                }
                blocks.append(trimmed)
            } else if trimmed.isEmpty {
                if !current.isEmpty {
                    blocks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                }
            } else {
                current += (current.isEmpty ? "" : "\n") + line
            }
        }
        if !current.isEmpty {
            blocks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        blocks = blocks.filter { !$0.isEmpty }

        if blocks.isEmpty { return .empty() }
        if blocks.count == 1 { return parseSingleTextBlock(blocks[0]) }

        let children = blocks.map { parseSingleTextBlock($0) }
        return ZoneModel.container(direction: .vertical, children: children)
    }

    private static func parseSingleTextBlock(_ text: String) -> ZoneModel {
        var zone = ZoneModel.text("")
        var content = text.trimmingCharacters(in: .whitespaces)

        // Bullet list item
        if content.hasPrefix("- ") || content.hasPrefix("* ") {
            zone.hasBullet = true
            content = String(content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }

        // Display math block — centrat
        if content.hasPrefix("$$") && content.hasSuffix("$$") {
            zone.textAlignment = .center
        }

        zone.text = content
        return zone
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    private static func stripOuterDollarWrapper(_ input: String) -> String {
        var t = input
        while t.hasPrefix("$") && t.hasSuffix("$") && !t.hasPrefix("$$") {
            let inner = String(t.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard inner.contains(" ") || inner.contains("\n") else { break }
            t = inner
        }
        return t
    }
}

// =============================================================================
// MARK: - CodeZoneHelper
//
// Utilitar pentru a extrage limba și codul dintr-un zone.text cu prefix [LANG:...]
// Folosit în CodeBlockPreviewView.
// =============================================================================

struct CodeZoneHelper {
    let language: String
    let code: String

    /// Parsează zone.text și separă tag-ul de limbă de codul efectiv.
    init(zoneText: String) {
        if zoneText.hasPrefix("[LANG:") {
            // Format: "[LANG:java]\ncodul..."
            let afterPrefix = zoneText.dropFirst(6) // drop "[LANG:"
            if let bracketEnd = afterPrefix.firstIndex(of: "]") {
                language = String(afterPrefix[..<bracketEnd])
                let afterBracket = afterPrefix[bracketEnd...].dropFirst() // drop "]"
                // Sare peste newline-ul imediat următor
                if afterBracket.hasPrefix("\n") {
                    code = String(afterBracket.dropFirst())
                } else {
                    code = String(afterBracket)
                }
            } else {
                language = ""
                code = zoneText
            }
        } else {
            language = ""
            code = zoneText
        }
    }

    /// True dacă textul este un code zone valid
    static func isCodeZone(_ zone: ZoneModel) -> Bool {
        zone.fontFamily == .mono && zone.contentType == .text
    }

    /// Label afișat în header-ul code block-ului
    var displayLanguage: String {
        language.isEmpty ? "CODE" : language.uppercased()
    }
}
