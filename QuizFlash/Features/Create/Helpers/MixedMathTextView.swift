import SwiftUI
import WebKit

// =============================================================================
// MARK: - MathTextSanitizer
// =============================================================================

struct MathTextSanitizer {

    static func heal(_ input: String) -> String {
        var t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        t = stripOuterDollarWrapper(t)
        t = fixOrphanDollar(t)
        t = stripInvalidMathTokens(t)
        return t
    }

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

    private static func fixOrphanDollar(_ input: String) -> String {
        var t = input
        let count = t.filter { $0 == "$" }.count
        guard count % 2 != 0 else { return t }
        if t.hasSuffix("$") && !t.hasSuffix("$$") {
            t = String(t.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if t.hasPrefix("$") && !t.hasPrefix("$$") {
            t = String(t.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
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
            guard
                let fullRange  = Range(match.range, in: result),
                let innerRange = Range(match.range(at: 1), in: result)
            else { continue }
            let inner = String(result[innerRange])
            if inner.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
                result.replaceSubrange(fullRange, with: inner)
            }
        }
        return result
    }

    static func containsMath(_ text: String) -> Bool {
        text.contains("$")     ||
        text.contains("\\[")   ||
        text.contains("\\(")   ||
        text.contains("\\begin")
    }

    /// True dacă textul conține cod inline cu backtick-uri singure
    static func containsInlineCode(_ text: String) -> Bool {
        let pattern = "`[^`\n]+`"
        return (try? NSRegularExpression(pattern: pattern))
            .map { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
            ?? false
    }
}

// =============================================================================
// MARK: - MixedMathTextView
//
// View principal pentru redarea textului mixt: text + math (KaTeX) + inline code.
// Codul în blocuri (```) este gestionat de CodeBlockPreviewView, NU de acest view.
// =============================================================================

struct MixedMathTextView: View {
    let text: String
    let fontSize: CGFloat
    let textColor: Color
    let alignment: HorizontalAlignment
    var isBold: Bool = false
    var isItalic: Bool = false

    @State private var webHeight: CGFloat = 50

    var body: some View {
        let clean = MathTextSanitizer.heal(text)

        if MathTextSanitizer.containsMath(clean) || MathTextSanitizer.containsInlineCode(clean) {
            // WebView — redă KaTeX + inline code styling
            MathWebView(
                text: clean,
                fontSize: fontSize,
                isBold: isBold,
                isItalic: isItalic,
                alignment: alignment,
                contentHeight: $webHeight
            )
            .frame(height: webHeight)
            .frame(maxWidth: .infinity)
        } else {
            Text(clean)
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
// MARK: - MathWebView
// =============================================================================

struct MathWebView: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let isBold: Bool
    let isItalic: Bool
    let alignment: HorizontalAlignment
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "heightUpdate")

        let config = WKWebViewConfiguration()
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false

        context.coordinator.webView = webView
        loadContent(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastRenderedText != text else { return }
        context.coordinator.lastRenderedText = text
        loadContent(in: webView)
    }

    private func loadContent(in webView: WKWebView) {
        webView.loadHTMLString(buildHTML(), baseURL: Bundle.main.bundleURL)
    }

    // MARK: - HTML Builder

    private func buildHTML() -> String {
        let cssAlign: String
        switch alignment {
        case .center:   cssAlign = "center"
        case .trailing: cssAlign = "right"
        default:        cssAlign = "left"
        }

        let weight = isBold   ? "bold"   : "normal"
        let style  = isItalic ? "italic" : "normal"

        // HTML escape: DOAR & → &amp;
        // Păstrăm $, \, ^, _ pentru KaTeX; păstrăm ` pentru code styling
        let safeText = text.replacingOccurrences(of: "&", with: "&amp;")

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
                font-family: -apple-system, sans-serif;
                font-size: \(fontSize)px;
                font-weight: \(weight);
                font-style: \(style);
                color: white;
                text-align: \(cssAlign);
                line-height: 1.6;
                padding: 4px 2px;
                overflow: hidden;
                word-break: break-word;
            }
            #content { width: 100%; }
            .katex { font-size: 1em !important; }
            .katex-error {
                color: inherit !important;
                font-style: normal !important;
                font-family: -apple-system, sans-serif !important;
            }

            /* ─── Inline code styling ─────────────────────────────────────── */
            /* Backtick-urile singure `code` → chip monospatat                */
            code {
                font-family: ui-monospace, 'SF Mono', Menlo, monospace;
                font-size: 0.88em;
                background: rgba(255, 255, 255, 0.12);
                border: 1px solid rgba(255, 255, 255, 0.15);
                border-radius: 4px;
                padding: 1px 5px;
                white-space: pre-wrap;
            }

            /* bold inline */
            strong, b { font-weight: bold; }
            em, i      { font-style: italic; }
        </style>
        </head>
        <body>
        <div id="content">\(processInlineCode(safeText))</div>
        <script>
            const extraMacros = {
                "\\\\thinspace":    "\\\\,",
                "\\\\negthinspace": "\\\\!",
                "\\\\medspace":     "\\\\:",
                "\\\\thickspace":   "\\\\;",
                "\\\\R":            "\\\\mathbb{R}",
                "\\\\N":            "\\\\mathbb{N}",
                "\\\\Z":            "\\\\mathbb{Z}",
                "\\\\Q":            "\\\\mathbb{Q}",
                "\\\\C":            "\\\\mathbb{C}",
                "\\\\eps":          "\\\\varepsilon",
                "\\\\epsilon":      "\\\\varepsilon"
            };

            renderMathInElement(document.getElementById('content'), {
                delimiters: [
                    { left: '$$', right: '$$', display: true  },
                    { left: '$',  right: '$',  display: false }
                ],
                throwOnError: false,
                errorColor: 'inherit',
                macros: extraMacros
            });

            function reportHeight() {
                const h = document.getElementById('content').getBoundingClientRect().height;
                if (h > 0) {
                    window.webkit.messageHandlers.heightUpdate.postMessage(Math.ceil(h) + 16);
                }
            }

            reportHeight();

            if (window.ResizeObserver) {
                new ResizeObserver(() => reportHeight()).observe(document.getElementById('content'));
            }
        </script>
        </body>
        </html>
        """
    }

    /// Convertește backtick-urile inline `code` în tag-uri HTML <code>
    /// ATENȚIE: nu procesăm blocuri ``` ``` — acelea sunt în CodeBlockPreviewView
    private func processInlineCode(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "`([^`\\n]+)`") else { return text }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))

        for match in matches.reversed() {
            guard
                let fullRange  = Range(match.range,        in: result),
                let innerRange = Range(match.range(at: 1), in: result)
            else { continue }

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

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler {
        @Binding var contentHeight: CGFloat
        var webView: WKWebView?
        var lastRenderedText: String = ""

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "heightUpdate",
                  let h = message.body as? Double, h > 0 else { return }
            DispatchQueue.main.async {
                self.contentHeight = CGFloat(h)
            }
        }
    }
}
