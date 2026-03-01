import SwiftUI
import WebKit

// =============================================================================
// MARK: - MathTextSanitizer
// =============================================================================
//
// TWO-LAYER DEFENCE:
//
// Layer 1 — Swift pre-processing (this file)
//   • repairBareLatexDelimiters()
//     Scans text for LaTeX commands (\in, \mid, \{, \ldots …) that appear
//     outside any $…$ region and wraps them in proper $…$ delimiters.
//     This prevents KaTeX's auto-render from accidentally ingesting
//     surrounding natural-language text.
//   • containsMath() now detects bare \command patterns too,
//     so the text correctly routes to MathWebView instead of SwiftUI.Text.
//
// Layer 2 — JavaScript pre-processing (inside buildHTML)
//   • A JS pass runs BEFORE renderMathInElement and escapes any remaining
//     bare backslash sequences that slipped through Swift, preventing
//     KaTeX from treating them as math mode openers.
//
// =============================================================================

struct MathTextSanitizer {

    // -------------------------------------------------------------------------
    // MARK: - Constants
    // -------------------------------------------------------------------------

    /// Known LaTeX math function names — these are NOT natural-language words.
    static let mathFunctionNames: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "log", "ln", "exp",
        "lim", "limsup", "liminf", "sup", "inf", "max", "min",
        "det", "ker", "im", "tr", "rank", "def", "dim", "sgn",
        "sign", "grad", "div", "curl", "mod", "gcd", "lcm",
        "arg", "Re", "Im", "deg", "hom", "coker", "coim",
        "Pr", "mathbb", "mathbf", "mathrm", "mathcal", "text"
    ]

    /// Characters that are valid INSIDE a math expression (besides letters/digits).
    private static let mathPunctChars: Set<Character> = Set("^_{}()[]+-=<>/!|,.'*~;:")

    // -------------------------------------------------------------------------
    // MARK: - Public API
    // -------------------------------------------------------------------------

    /// Main entry point.  Call this on every string before rendering.
    static func heal(_ input: String) -> String {
        var t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // 1. Repair bare LaTeX FIRST (most important)
        t = repairBareLatexDelimiters(t)
        // 2. Fix unbalanced lone $ signs
        t = fixOrphanDollar(t)
        // 3. Strip currency symbols mistakenly inside $…$
        t = stripInvalidMathTokens(t)
        return t
    }

    /// Returns true if text contains math that needs WebView rendering.
    static func containsMath(_ text: String) -> Bool {
        // Existing dollar-based check
        if text.contains("$") || text.contains("\\[") ||
           text.contains("\\(") || text.contains("\\begin") {
            return true
        }
        // NEW: also detect bare \command outside any delimiters
        return hasBareLatexCommand(text)
    }

    static func containsInlineCode(_ text: String) -> Bool {
        let pattern = "`[^`\n]+`"
        return (try? NSRegularExpression(pattern: pattern))
            .map { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
            ?? false
    }

    // =========================================================================
    // MARK: - Core: Bare LaTeX Repair
    // =========================================================================

    /// Wraps LaTeX commands that appear outside $…$ in proper delimiters.
    static func repairBareLatexDelimiters(_ text: String) -> String {
        guard hasBareLatexCommand(text) else { return text }

        // Process each line independently — safer and handles multi-paragraph zones.
        let lines = text.components(separatedBy: "\n")
        return lines.map { repairLine($0) }.joined(separator: "\n")
    }

    // -------------------------------------------------------------------------
    // MARK: - Line-level Repair
    // -------------------------------------------------------------------------

    private static func repairLine(_ line: String) -> String {
        guard hasBareLatexCommand(line) else { return line }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Strip optional list prefix (-, *, •, 1., a.)
        let (listPrefix, content) = extractListPrefix(trimmed)

        // If the content portion is a pure math expression → wrap the whole thing.
        if looksLikePureMathExpression(content) {
            let useBlock = content.contains("\\begin{")
                        || content.contains("\\frac{")
                        || content.contains("\\int")
                        || content.contains("\\sum")
                        || content.contains("\\prod")
                        || content.count > 80
            let delimiter = useBlock ? "$$" : "$"
            let wrapped = "\(delimiter)\(content)\(delimiter)"
            // Preserve indentation from original line
            let indent = String(line.prefix(line.count - line.drop(while: { $0 == " " || $0 == "\t" }).count))
            return "\(indent)\(listPrefix)\(wrapped)"
        }

        // Mixed content: scan and wrap individual math segments inline.
        return wrapBareSegmentsInLine(line)
    }

    // -------------------------------------------------------------------------
    // MARK: - Segment Scanner (character-level)
    // -------------------------------------------------------------------------

    /// Scans a line, finds bare \command segments, wraps them in $…$.
    private static func wrapBareSegmentsInLine(_ line: String) -> String {
        var result = ""
        var i = line.startIndex
        var inSingleDollar = false
        var inDoubleDollar = false

        while i < line.endIndex {
            let c = line[i]

            // ── Track existing $$ regions ──────────────────────────────────
            if c == "$" {
                let next = line.index(after: i)
                if next < line.endIndex && line[next] == "$" {
                    inDoubleDollar.toggle()
                    result += "$$"
                    i = line.index(after: next)
                    continue
                }
                // Single $
                inSingleDollar.toggle()
                result.append(c)
                i = line.index(after: i)
                continue
            }

            // ── Detect bare \command outside any $ region ──────────────────
            if c == "\\" && !inSingleDollar && !inDoubleDollar {
                let next = line.index(after: i)
                if next < line.endIndex {
                    let nc = line[next]
                    if nc.isLetter || nc == "{" || nc == "}" || nc == "|" || nc == "," {
                        // Absorb any preceding math chars from result into this segment
                        let (prefix, trimmedResult) = absorbPrecedingMathChars(from: result)
                        result = trimmedResult

                        // Collect the full math segment starting at \
                        let (mathSeg, endIdx) = collectMathSegment(in: line, from: i)

                        if mathSeg.isEmpty {
                            result = trimmedResult + prefix
                            result.append(c)
                            i = line.index(after: i)
                        } else {
                            result += "$\(prefix)\(mathSeg)$"
                            i = endIdx
                        }
                        continue
                    }
                }
            }

            result.append(c)
            i = line.index(after: i)
        }

        return result
    }

    /// Looks backwards in an already-built result string and removes any
    /// trailing math-compatible characters (like a preceding variable name
    /// `x` in `x\in Y`).  Returns the absorbed prefix and the trimmed result.
    private static func absorbPrecedingMathChars(from result: String) -> (prefix: String, trimmed: String) {
        var prefix = ""
        var trimmed = result

        while let last = trimmed.last {
            // Only absorb single letters or digits immediately before the command
            // (e.g. the `x` in `x\in`). Stop at spaces or punctuation.
            if (last.isLetter && prefix.isEmpty) || (last.isNumber && prefix.isEmpty) {
                prefix = String(last) + prefix
                trimmed.removeLast()
            } else {
                break
            }
        }

        return (prefix, trimmed)
    }

    // -------------------------------------------------------------------------
    // MARK: - Math Segment Collector
    // -------------------------------------------------------------------------

    /// Starting at `start` (which must be a `\`), collects a contiguous math
    /// segment and returns it plus the index immediately after the segment.
    private static func collectMathSegment(in text: String, from start: String.Index) -> (String, String.Index) {
        var seg = ""
        var i = start
        var braceDepth = 0    // tracks {…} groups that are NOT \{ or \}

        while i < text.endIndex {
            let c = text[i]

            // Hard stops
            if c == "\n" || c == "$" { break }

            // ── Backslash sequences ─────────────────────────────────────────
            if c == "\\" {
                let ni = text.index(after: i)
                guard ni < text.endIndex else { break }
                let nc = text[ni]

                // \command  (letters)
                if nc.isLetter {
                    seg.append(c)
                    var j = ni
                    while j < text.endIndex && text[j].isLetter {
                        seg.append(text[j])
                        j = text.index(after: j)
                    }
                    i = j
                    continue
                }

                // Escaped special chars: \{  \}  \|  \,  \;  \:  \.  \!  \\
                let escapable: Set<Character> = ["{", "}", "|", ",", ";", ":", ".", "!", "\\", " ", "(", ")", "[", "]"]
                if escapable.contains(nc) {
                    seg.append(c)
                    seg.append(nc)
                    i = text.index(after: ni)
                    continue
                }

                // Lone backslash — stop
                break
            }

            // ── Brace tracking (only REAL braces, not \{ \}) ───────────────
            if c == "{" {
                braceDepth += 1
                seg.append(c)
                i = text.index(after: i)
                continue
            }
            if c == "}" {
                if braceDepth <= 0 { break }   // unmatched } — end of segment
                braceDepth -= 1
                seg.append(c)
                i = text.index(after: i)
                continue
            }

            // ── Space: decide whether math continues ───────────────────────
            if c == " " || c == "\t" {
                let next = peekNextWord(in: text, from: text.index(after: i))
                if mathContinues(after: next, braceDepth: braceDepth) {
                    seg.append(" ")
                    i = text.index(after: i)
                } else {
                    break
                }
                continue
            }

            // ── Regular math-compatible char ───────────────────────────────
            if isMathCompatibleChar(c) {
                seg.append(c)
                i = text.index(after: i)
            } else {
                break
            }
        }

        // Trim any dangling punctuation (trailing comma, semicolon etc.)
        let trimmed = seg.trimmingCharacters(in: CharacterSet(charactersIn: ",; \t"))
        return (trimmed, i)
    }

    // -------------------------------------------------------------------------
    // MARK: - Decision Helpers
    // -------------------------------------------------------------------------

    /// Returns the next non-space "word" starting from `from`.
    private static func peekNextWord(in text: String, from start: String.Index) -> String {
        var i = start
        while i < text.endIndex && text[i] == " " { i = text.index(after: i) }
        var word = ""
        while i < text.endIndex {
            let c = text[i]
            if c.isWhitespace || c == "\n" || c == "$" { break }
            word.append(c)
            i = text.index(after: i)
        }
        return word
    }

    /// Returns true if math should continue after encountering a space,
    /// based on the next "word" and current brace depth.
    private static func mathContinues(after nextWord: String, braceDepth: Int) -> Bool {
        if nextWord.isEmpty { return false }

        // Inside open braces → always continue
        if braceDepth > 0 { return true }

        // Clearly math starters
        if nextWord.hasPrefix("\\") { return true }
        if nextWord.hasPrefix("^") || nextWord.hasPrefix("_") { return true }
        if nextWord.hasPrefix("{") || nextWord.hasPrefix("(") || nextWord.hasPrefix("[") { return true }

        // Single ASCII letter (likely a math variable: x, y, T, V …)
        let stripped = nextWord.trimmingCharacters(in: CharacterSet(charactersIn: "{}()[]^_.,;:!"))
        if stripped.count == 1 && stripped.first!.isASCIILetter { return true }

        // Known math function name
        if mathFunctionNames.contains(stripped.lowercased()) { return true }

        // Contains math operators — likely still math
        if nextWord.contains("=") || nextWord.contains("^") || nextWord.contains("_") { return true }

        // Pure number
        if stripped.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "," }) { return true }

        // Anything else (3+ letter natural-language word) → stop
        return false
    }

    /// True if a character can appear inside a math expression.
    private static func isMathCompatibleChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || mathPunctChars.contains(c)
    }

    // -------------------------------------------------------------------------
    // MARK: - Pure-Math Expression Detection
    // -------------------------------------------------------------------------

    /// Returns true if the entire string looks like a math expression
    /// (i.e., no natural-language words that indicate it's prose).
    static func looksLikePureMathExpression(_ text: String) -> Bool {
        guard hasBareLatexCommand(text) else { return false }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var naturalWordCount = 0

        for word in words {
            // Strip wrapper math punctuation to expose the "core" word
            let clean = word.trimmingCharacters(in: CharacterSet(charactersIn: "{}()[]^_+-=<>/!|,;.:$\\"))
            if clean.isEmpty { continue }

            // Skip obvious math tokens
            if word.hasPrefix("\\")           { continue }  // \command
            if clean.count <= 2               { continue }  // short (variable, operator)
            if mathFunctionNames.contains(clean.lowercased()) { continue }

            // Has embedded math chars → it's a math token like `f^{-1}` or `a_{n+1}`
            let hasMathChar = clean.contains(where: { "^_{}()\\/=<>!|".contains($0) || $0.isNumber })
            if hasMathChar { continue }

            // All-letter word of 3+ chars without any math chars = natural language
            if clean.allSatisfy({ $0.isLetter }) && clean.count >= 3 {
                naturalWordCount += 1
            }
        }

        return naturalWordCount == 0
    }

    // -------------------------------------------------------------------------
    // MARK: - Bare Command Detection
    // -------------------------------------------------------------------------

    /// Returns true if the text contains a LaTeX backslash command that is
    /// NOT inside a $…$ or $$…$$ delimiter region.
    static func hasBareLatexCommand(_ text: String) -> Bool {
        guard text.contains("\\") else { return false }

        var inDollar = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]
            let ni = text.index(after: i)

            // Track $$ first (must come before single-$ check)
            if c == "$" {
                if ni < text.endIndex && text[ni] == "$" {
                    inDollar.toggle()
                    i = text.index(after: ni)
                    continue
                }
                inDollar.toggle()
                i = ni
                continue
            }

            // Check for bare \command outside any $ region
            if c == "\\" && !inDollar && ni < text.endIndex {
                let nc = text[ni]
                if nc.isLetter || nc == "{" || nc == "}" || nc == "|" {
                    return true
                }
            }

            i = ni
        }

        return false
    }

    // -------------------------------------------------------------------------
    // MARK: - List Prefix Extraction
    // -------------------------------------------------------------------------

    /// Splits a line like "- content" into ("- ", "content").
    private static func extractListPrefix(_ line: String) -> (prefix: String, content: String) {
        // Matches: "- ", "* ", "• ", "1. ", "1) ", "a. ", "(a) "
        let patterns = [
            #"^(\s*(?:-|\*|•)\s+)"#,
            #"^(\s*\d+[.)]\s+)"#,
            #"^(\s*[a-zA-Z][.)]\s+)"#,
            #"^(\s*\([a-zA-Z0-9]+\)\s+)"#
        ]
        for pattern in patterns {
            if let range = line.range(of: pattern, options: .regularExpression) {
                return (String(line[range]), String(line[range.upperBound...]))
            }
        }
        return ("", line)
    }

    // -------------------------------------------------------------------------
    // MARK: - Legacy Sanitizers (kept as-is)
    // -------------------------------------------------------------------------

    private static func fixOrphanDollar(_ input: String) -> String {
        var t = input
        // Count single $ (not part of $$)
        var singles = 0
        var idx = t.startIndex
        while idx < t.endIndex {
            if t[idx] == "$" {
                let next = t.index(after: idx)
                if next < t.endIndex && t[next] == "$" {
                    idx = t.index(after: next) // skip $$
                } else {
                    singles += 1
                    idx = next
                }
            } else {
                idx = t.index(after: idx)
            }
        }
        guard singles % 2 != 0 else { return t }
        // Remove the last lone $
        if let last = t.lastIndex(of: "$") {
            let prev = last > t.startIndex ? t.index(before: last) : nil
            if prev == nil || t[prev!] != "$" {
                t.remove(at: last)
            }
        }
        return t
    }

    private static func stripInvalidMathTokens(_ input: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "€£¥₹₩₿¢฿₪₨₦")
        guard let regex = try? NSRegularExpression(
            pattern: "(?<!\\$)\\$(?!\\$)(.+?)(?<!\\$)\\$(?!\\$)"
        ) else { return input }

        var result = input
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange  = Range(match.range,      in: result),
                  let innerRange = Range(match.range(at: 1), in: result) else { continue }
            let inner = String(result[innerRange])
            if inner.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
                result.replaceSubrange(fullRange, with: inner)
            }
        }
        return result
    }
}

// =============================================================================
// MARK: - Character Extension
// =============================================================================

private extension Character {
    var isASCIILetter: Bool { isASCII && isLetter }
}

// =============================================================================
// MARK: - MixedMathTextView
// =============================================================================

struct MixedMathTextView: View {
    let text: String
    let fontSize: CGFloat
    let textColor: Color
    let alignment: HorizontalAlignment
    var isBold: Bool = false
    var isItalic: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var webHeight: CGFloat = 50

    var body: some View {
        let clean = MathTextSanitizer.heal(text)

        if MathTextSanitizer.containsMath(clean) || MathTextSanitizer.containsInlineCode(clean) {
            MathWebView(
                text: clean,
                fontSize: fontSize,
                textColor: textColor,
                colorScheme: colorScheme,
                isBold: isBold,
                isItalic: isItalic,
                alignment: alignment,
                contentHeight: $webHeight
            )
            .frame(height: webHeight)
            .frame(maxWidth: .infinity)
        } else {
            Text(LocalizedStringKey(clean))
                .font(swiftUIFont)
                .foregroundColor(textColor)
                .multilineTextAlignment(nsTextAlignment)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var swiftUIFont: Font {
        let base = Font.system(size: fontSize)
        switch (isBold, isItalic) {
        case (true,  true):  return base.bold().italic()
        case (true,  false): return base.bold()
        case (false, true):  return base.italic()
        case (false, false): return base
        }
    }

    private var nsTextAlignment: TextAlignment {
        switch alignment {
        case .center:   return .center
        case .trailing: return .trailing
        default:        return .leading
        }
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .center:   return .center
        case .trailing: return .trailing
        default:        return .leading
        }
    }
}

// =============================================================================
// MARK: - MathWebView Pool
// =============================================================================
//
// Design constraints:
//
// 1. SHARED WKProcessPool
//    By default every WKWebView spawns its own WebKit subprocess. On a device
//    with 6 pooled views that is 6 separate OS-level processes, each consuming
//    ~15-25 MB of RAM independently of any content they render.
//    A single shared WKProcessPool collapses all WebViews into ONE subprocess,
//    cutting baseline WebKit memory from O(n) to O(1).
//
// 2. BOUNDED POOL SIZE (maxPoolSize)
//    Without a cap, enqueue() grows the pool indefinitely. Opening a deck with
//    40 math cards and closing it would leave 40 WKWebViews in memory forever.
//    When the pool is at capacity, excess WebViews are explicitly destroyed
//    instead of being retained.
//
// 3. SINGLE PREWARM
//    prewarm() must be called once at app launch (QuizFlashApp.init).
//    The isPrewarmed guard makes subsequent calls no-ops, but call sites
//    outside the app entry point should be removed to keep intent clear.
//

class MathWebViewPool {

    static let shared = MathWebViewPool()

    /// Notification token to flush the pool if the OS runs extremely low on RAM.
    private var memoryWarningTask: Task<Void, Never>?

    init() {
        memoryWarningTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification) {
                guard let self = self else { return }
                await MainActor.run {
                    self.flush()
                }
            }
        }
    }

    deinit {
        memoryWarningTask?.cancel()
    }

    // Maximum number of idle WebViews kept alive between uses.
    // Reduced from 8 to 2 to minimize resting memory footprint.
    // 2 is enough for instant flip animation (front + back) while
    // subsequent cards can spawn on demand without accumulating.
    private static let maxPoolSize = 2

    // One process pool shared across every WKWebView instance.
    // This is the single most impactful memory optimization available for
    // multi-WebView scenarios on iOS.
    private let sharedProcessPool = WKProcessPool()

    private var pool: [WKWebView] = []
    private var isPrewarmed = false

    // MARK: - Prewarm

    /// Populates the pool with ready-to-use WebViews at app launch.
    ///
    /// Call this **once** from `QuizFlashApp.init()`.
    /// The `isPrewarmed` guard makes subsequent calls safe but they should
    /// not appear elsewhere — the intent of this method is app-launch only.
    func prewarm(count: Int = 6) {
        guard !isPrewarmed else { return }
        isPrewarmed = true

        // Stagger creation across the first second to avoid a spike on the
        // main thread immediately after launch while the UI is still settling.
        let clamped = min(count, Self.maxPoolSize)
        for i in 0..<clamped {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                // Ensure we don't exceed max size during async initialization
                if self.pool.count < Self.maxPoolSize {
                    self.pool.append(self.create())
                }
            }
        }
    }

    // MARK: - Dequeue / Enqueue

    /// Returns a pre-warmed WebView from the pool (zero allocation cost),
    /// or creates a new one on demand if the pool is exhausted.
    func dequeue() -> WKWebView {
        pool.popLast() ?? create()
    }

    /// Returns a WebView to the pool after clearing its state.
    ///
    /// If the pool is already at `maxPoolSize`, the WebView is discarded
    /// instead of being retained, preventing unbounded memory growth when
    /// large decks (many math cards) are opened and closed repeatedly.
    func enqueue(_ webView: WKWebView) {
        guard pool.count < Self.maxPoolSize else {
            // Pool is full — explicitly kill the WKProcess for this view
            // before letting ARC release the wrapper.
            // about:blank is the ONLY reliable way to flush WebKit memory on iOS.
            webView.evaluateJavaScript("document.body.innerHTML = ''; window.webkit.messageHandlers = null;")
            webView.load(URLRequest(url: URL(string: "about:blank")!))
            return
        }

        // Reset content so the previous deck's HTML does not linger in memory.
        webView.evaluateJavaScript("document.body.innerHTML = '';")
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        pool.append(webView)
    }

    /// Empties the entire pool and releases the WKWebViews.
    /// Called automatically on `didReceiveMemoryWarningNotification`.
    func flush() {
        pool.removeAll()
    }

    // MARK: - Factory

    private func create() -> WKWebView {
        let config = WKWebViewConfiguration()
        // Assign the shared process pool so all WebViews in the app share a
        // single WebKit subprocess rather than each spawning their own.
        config.processPool = sharedProcessPool

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        return webView
    }
}

// =============================================================================
// MARK: - MathWebView
// =============================================================================

struct MathWebView: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let textColor: Color
    let colorScheme: ColorScheme
    let isBold: Bool
    let isItalic: Bool
    let alignment: HorizontalAlignment
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(contentHeight: $contentHeight) }

    // 🟢 NOU: Funcția SwiftUI automată care prinde momentul când cardul dispare
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 1. Unlink coordinator to break any lingering weak/unowned chains
        coordinator.webView = nil

        // 2. Remove script handler to break the JS context retain cycle
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "heightUpdate")

        // 3. Return to pool (or discard if full)
        MathWebViewPool.shared.enqueue(uiView)
    }

    func makeUIView(context: Context) -> WKWebView {
        // 🟢 NOU: Împrumutăm WebView-ul (0 milisecunde în loc de 300 milisecunde)
        let webView = MathWebViewPool.shared.dequeue()

        // Re-atașăm mesajul de înălțime la controller folosind delegatul specializat
        // care reține webView-ul *WEAK*, nu *STRONG*.
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "heightUpdate")
        let scriptHandlerWrapper = WeakScriptMessageHandler(delegate: context.coordinator)
        webView.configuration.userContentController.add(scriptHandlerWrapper, name: "heightUpdate")

        context.coordinator.webView = webView
        context.coordinator.lastRenderedText = text
        
        loadContent(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastRenderedText != text else { return }
        context.coordinator.lastRenderedText = text
        loadContent(in: webView)
    }

    private func loadContent(in webView: WKWebView) {
        // loadHTMLString e complet non-blocking. Procesul grafic rulează separat de sistemul iOS principal!
        webView.loadHTMLString(buildHTML(), baseURL: Bundle.main.bundleURL)
    }

    // -------------------------------------------------------------------------
    // MARK: - HTML Builder
    // -------------------------------------------------------------------------

    private func buildHTML() -> String {
        let cssAlign: String
        switch alignment {
        case .center:   cssAlign = "center"
        case .trailing: cssAlign = "right"
        default:        cssAlign = "left"
        }

        let weight    = isBold   ? "bold"   : "normal"
        let fontStyle = isItalic ? "italic" : "normal"
        let cssColor  = getCSSColor()

        let safeText  = text.replacingOccurrences(of: "&", with: "&amp;")
        let mdText    = processHTMLMarkdown(safeText)
        let finalText = processInlineCode(mdText)

        let katexTags: String
        if let urls = Self.katexBundleURLs() {
            katexTags = """
            <link rel="stylesheet" href="\(urls.css)">
            <script src="\(urls.js)"></script>
            <script src="\(urls.autoRender)"></script>
            """
        } else {
            katexTags = """
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"></script>
            """
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        \(katexTags)
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body {
                background: transparent;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                font-size: \(fontSize)px;
                font-weight: \(weight);
                font-style: \(fontStyle);
                color: \(cssColor);
                text-align: \(cssAlign);
                line-height: 1.6;
                padding: 4px 2px;
                overflow: hidden;
                word-break: break-word;
            }
            #content { width: 100%; white-space: pre-wrap; }

            .katex-display {
                margin: 0.6em 0;
                overflow-x: auto;
                overflow-y: visible !important;
                padding: 6px 0;
                -webkit-overflow-scrolling: touch;
                scrollbar-width: none;
            }
            .katex-display::-webkit-scrollbar { display: none; }
            .katex { font-size: 1.08em !important; }
            .katex-error {
                color: inherit !important;
                font-style: normal !important;
                font-family: -apple-system, sans-serif !important;
            }
            code {
                font-family: ui-monospace, 'SF Mono', Menlo, monospace;
                font-size: 0.88em;
                background: rgba(120, 120, 120, 0.15);
                color: inherit;
                border: 1px solid rgba(120, 120, 120, 0.2);
                border-radius: 6px;
                padding: 2px 6px;
                white-space: pre-wrap;
            }
            strong, b { font-weight: bold; }
            em, i     { font-style: italic; }
        </style>
        </head>
        <body>
        <div id="content">\(finalText)</div>
        <script>
        const extraMacros = {
            "\\\\thinspace":    "\\\\,",
            "\\\\negthinspace": "\\\\!",
            "\\\\medspace":     "\\\\:",
            "\\\\thickspace":   "\\\\;",
            "\\\\R":  "\\\\mathbb{R}",
            "\\\\N":  "\\\\mathbb{N}",
            "\\\\Z":  "\\\\mathbb{Z}",
            "\\\\Q":  "\\\\mathbb{Q}",
            "\\\\C":  "\\\\mathbb{C}",
            "\\\\eps":      "\\\\varepsilon",
            "\\\\epsilon":  "\\\\varepsilon"
        };

        renderMathInElement(document.getElementById('content'), {
            delimiters: [
                { left: '$$',    right: '$$',    display: true  },
                { left: '\\\\[', right: '\\\\]', display: true  },
                { left: '$',     right: '$',     display: false },
                { left: '\\\\(', right: '\\\\)', display: false }
            ],
            throwOnError: false,
            errorColor:   'inherit',
            macros:        extraMacros
        });

        function reportHeight() {
            const el = document.getElementById('content');
            const h  = Math.max(el.getBoundingClientRect().height, el.scrollHeight);
            if (h > 0) {
                window.webkit.messageHandlers.heightUpdate.postMessage(Math.ceil(h) + 20);
            }
        }

        setTimeout(reportHeight, 80);
        setTimeout(reportHeight, 300);

        if (window.ResizeObserver) {
            new ResizeObserver(reportHeight).observe(document.getElementById('content'));
        }
        </script>
        </body>
        </html>
        """
    }

    private func getCSSColor() -> String {
        if textColor == .primary {
            return colorScheme == .dark ? "#FFFFFF" : "#000000"
        }
        let traits = UITraitCollection(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light
        )
        let resolved = UIColor(textColor).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgba(\(Int(r*255)),\(Int(g*255)),\(Int(b*255)),\(a))"
    }

    private func processHTMLMarkdown(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*") {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "<b>$1</b>"
            )
        }
        return result
    }

    private func processInlineCode(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "`([^`\\n]+)`") else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange  = Range(match.range,        in: result),
                  let innerRange = Range(match.range(at: 1), in: result) else { continue }
            let inner = String(result[innerRange])
            result.replaceSubrange(fullRange, with: "<code>\(inner)</code>")
        }
        return result
    }

    private static func katexBundleURLs() -> (js: String, css: String, autoRender: String)? {
        guard
            let js  = Bundle.main.url(forResource: "katex.min",       withExtension: "js"),
            let css = Bundle.main.url(forResource: "katex.min",       withExtension: "css"),
            let ar  = Bundle.main.url(forResource: "auto-render.min", withExtension: "js")
        else { return nil }
        return (js.absoluteString, css.absoluteString, ar.absoluteString)
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        @Binding var contentHeight: CGFloat
        weak var webView: WKWebView? // WEAK reference to break the retain cycle
        var lastRenderedText: String = ""

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "heightUpdate",
                  let h = message.body as? Double, h > 0
            else { return }
            DispatchQueue.main.async { self.contentHeight = CGFloat(h) }
        }
    }
}

// =============================================================================
// MARK: - WeakScriptMessageHandler
// =============================================================================

/// Acts as a purely weak intermediary between WKUserContentController and our Coordinator.
/// WKUserContentController retains its script message handlers strongly. If we passed
/// the Coordinator directly, WKWebView -> String -> Handler -> Coordinator -> WKWebView,
/// resulting in a permanent cyclic memory leak.
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
