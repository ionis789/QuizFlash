import SwiftUI
import WebKit

// =============================================================================
// MARK: - MixedMathRenderStyle
// =============================================================================

/// Visual rendering modes for mixed rich-text previews.
///
/// The deck grid uses a quieter preview style so inline code and math remain
/// typographic instead of looking like standalone chips inside a compact card.
enum MixedMathRenderStyle: String, Sendable {
    case standard
    case deckCardPreview

    var inlineCodeClassName: String {
        switch self {
        case .standard:
            return "inline-code--standard"
        case .deckCardPreview:
            return "inline-code--deck-card-preview"
        }
    }
}

// MARK: - MixedMathTextView
// =============================================================================

struct MixedMathTextView: View {
    let text: String
    let fontSize: CGFloat
    let textColor: Color
    let alignment: HorizontalAlignment
    var isBold: Bool = false
    var isItalic: Bool = false
    /// When `false` the underlying WKWebView disables all its gesture recognisers
    /// so that taps and swipes pass through to the parent SwiftUI view.
    /// Set to `false` in read-only contexts (card playback, preview).
    /// Set to `true` in editable contexts (CreateCardView, ZoneContentView).
    var isInteractive: Bool = true
    var lineLimit: Int? = nil
    var renderStyle: MixedMathRenderStyle = .standard

    @Environment(\.colorScheme) private var colorScheme
    @State private var webHeight: CGFloat = 50

    var body: some View {
        let clean = MathTextSanitizer.heal(text)
        let signature = renderSignature(for: clean)

        if MathTextSanitizer.containsMath(clean) || MathTextSanitizer.containsInlineCode(clean) {
            MathWebView(
                text: clean,
                fontSize: fontSize,
                textColor: textColor,
                colorScheme: colorScheme,
                isBold: isBold,
                isItalic: isItalic,
                alignment: alignment,
                renderStyle: renderStyle,
                renderSignature: signature,
                contentHeight: $webHeight,
                isInteractive: isInteractive
            )
            .frame(height: webHeight)
            .frame(maxWidth: .infinity)
            // When non-interactive, disable SwiftUI hit-testing too so the
            // WKWebView layer never becomes the first responder for a tap.
            .allowsHitTesting(isInteractive)
        } else {
            Text(LocalizedStringKey(clean))
                .font(swiftUIFont)
                .foregroundColor(textColor)
                .multilineTextAlignment(nsTextAlignment)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func renderSignature(for cleanText: String) -> String {
        [
            cleanText,
            String(format: "%.3f", fontSize),
            colorSignature,
            alignmentSignature,
            isBold ? "1" : "0",
            isItalic ? "1" : "0",
            renderStyle.rawValue
        ].joined(separator: "|")
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

    private var alignmentSignature: String {
        switch alignment {
        case .center:
            return "center"
        case .trailing:
            return "trailing"
        default:
            return "leading"
        }
    }

    private var colorSignature: String {
        if textColor == .primary {
            return colorScheme == .dark ? "primary-dark" : "primary-light"
        }
        if textColor == .secondary {
            return colorScheme == .dark ? "secondary-dark" : "secondary-light"
        }
        return colorScheme == .dark ? "custom-dark" : "custom-light"
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
    // Increased to 12 to support scrolling through grid view with KaTeX
    // while maintaining a stable process limit.
    private static let maxPoolSize = 12

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
            webView.evaluateJavaScript("document.body.innerHTML = ''; window.webkit.messageHandlers = null;")
            webView.load(URLRequest(url: URL(string: "about:blank")!))
            return
        }

        // Fast clearing: just wipe the div content instead of reloading about:blank.
        // This keeps KaTeX JS/CSS cached in the DOM perfectly.
        webView.evaluateJavaScript("const el = document.getElementById('content'); if (el) el.innerHTML = '';")
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
        
        // Load the base HTML template once upon creation.
        webView.loadHTMLString(MathWebView.baseHTMLTemplate, baseURL: Bundle.main.bundleURL)
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
    let renderStyle: MixedMathRenderStyle
    let renderSignature: String
    @Binding var contentHeight: CGFloat
    /// When `false`, disables all UIKit gesture recognisers on the WKWebView
    /// so that taps and drags pass through to the parent SwiftUI view unobstructed.
    var isInteractive: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(contentHeight: $contentHeight) }

    // Called automatically by SwiftUI when the view is removed from the hierarchy.
    // Breaks the retain cycle and returns the WKWebView to the shared pool.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 1. Unlink coordinator to break any lingering weak/unowned chains
        coordinator.webView = nil

        // 2. Remove the script message handler to break the JS context retain cycle
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "heightUpdate")

        // 3. Return to pool (or discard if full)
        MathWebViewPool.shared.enqueue(uiView)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = MathWebViewPool.shared.dequeue()

        webView.configuration.userContentController.removeScriptMessageHandler(forName: "heightUpdate")
        let scriptHandlerWrapper = WeakScriptMessageHandler(delegate: context.coordinator)
        webView.configuration.userContentController.add(scriptHandlerWrapper, name: "heightUpdate")

        context.coordinator.webView = webView
        context.coordinator.lastRenderedSignature = renderSignature

        // In read-only contexts (playback, preview), disable all UIKit interaction
        // on the WKWebView. This prevents WebKit's internal gesture recognisers
        // from consuming taps and drags that must reach the SwiftUI layer above.
        applyInteractivity(to: webView)

        loadContent(in: webView, context: context)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Re-apply interaction state in case isInteractive changed between renders.
        applyInteractivity(to: webView)
        guard context.coordinator.lastRenderedSignature != renderSignature else { return }
        context.coordinator.lastRenderedSignature = renderSignature
        loadContent(in: webView, context: context)
    }

    /// Enables or disables all UIKit interaction on the WKWebView.
    /// Affects the view itself, its internal UIScrollView, and every
    /// subview gesture recogniser in the WebKit hierarchy.
    private func applyInteractivity(to webView: WKWebView) {
        webView.isUserInteractionEnabled = isInteractive
        webView.scrollView.isUserInteractionEnabled = isInteractive
        // Explicitly remove all gesture recognizers when non-interactive
        // so WebKit's internal recognizers cannot override UIKit hit-testing.
        if !isInteractive {
            webView.scrollView.gestureRecognizers?.forEach {
                webView.scrollView.removeGestureRecognizer($0)
            }
        }
    }

    private func loadContent(in webView: WKWebView, context: Context) {
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
        let finalText = processInlineCode(mdText, renderStyle: renderStyle)
        
        // Base64 encoding cleanly passes arbitrary UTF-8 characters across the JS payload boundary
        guard let b64 = finalText.data(using: .utf8)?.base64EncodedString() else { return }
        
        let js = "updateMathContent('\(b64)', '\(cssColor)', \(fontSize), '\(cssAlign)', '\(weight)', '\(fontStyle)');"
        context.coordinator.applyUpdate(js: js)
    }

    // -------------------------------------------------------------------------
    // MARK: - HTML Builder
    // -------------------------------------------------------------------------

    /// A static, one-time HTML template injected into cached WebViews.
    static var baseHTMLTemplate: String {
        let katexTags: String
        if let urls = katexBundleURLs() {
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
                overflow: hidden;
                word-break: break-word;
                margin: 0;
                padding: 0;
            }
            #content { width: 100%; white-space: pre-wrap; padding: 2px 0px; line-height: 1.5; }

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
            code.inline-code {
                font-family: ui-monospace, 'SF Mono', Menlo, monospace;
                font-size: 0.88em;
            }
            code.inline-code--standard {
                background: rgba(120, 120, 120, 0.15);
                color: inherit;
                border: 1px solid rgba(120, 120, 120, 0.2);
                border-radius: 6px;
                padding: 2px 6px;
                white-space: pre-wrap;
            }
            code.inline-code--deck-card-preview {
                background: transparent;
                color: inherit;
                border: none;
                border-radius: 0;
                padding: 0;
                white-space: pre-wrap;
                font-size: 0.92em;
                font-weight: 600;
                letter-spacing: -0.01em;
                opacity: 0.94;
            }
            strong, b { font-weight: bold; }
            em, i     { font-style: italic; }
        </style>
        </head>
        <body>
        <div id="content"></div>
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
        
        let updateTimeout;

        function updateMathContent(b64, color, fontSize, align, weight, fontStyle) {
            document.body.style.color = color;
            document.body.style.fontSize = fontSize + 'px';
            document.body.style.textAlign = align;
            document.body.style.fontWeight = weight;
            document.body.style.fontStyle = fontStyle;

            let bin = window.atob(b64);
            let bytes = new Uint8Array(bin.length);
            for (let i = 0; i < bin.length; i++) {
                bytes[i] = bin.charCodeAt(i);
            }
            let text = new TextDecoder('utf-8').decode(bytes);

            const contentDiv = document.getElementById('content');
            contentDiv.innerHTML = text;
            
            try {
                renderMathInElement(contentDiv, {
                    delimiters: [
                        { left: '$$',    right: '$$',    display: true  },
                        { left: '\\\\[', right: '\\\\]', display: true  },
                        { left: '$',     right: '$',     display: false },
                        { left: '\\\\(', right: '\\\\)', display: false }
                    ],
                    ignoredTags: ["script", "noscript", "style", "textarea", "pre", "option"],
                    throwOnError: false,
                    errorColor:   'inherit',
                    macros:        extraMacros
                });
            } catch(e) { console.error(e); }

            clearTimeout(updateTimeout);
            reportHeight();
            updateTimeout = setTimeout(reportHeight, 50);
        }

        function reportHeight() {
            const el = document.getElementById('content');
            const h  = Math.max(el.getBoundingClientRect().height, el.scrollHeight);
            if (h > 0 && window.webkit && window.webkit.messageHandlers.heightUpdate) {
                window.webkit.messageHandlers.heightUpdate.postMessage(Math.ceil(h));
            }
        }

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

    private func processInlineCode(_ text: String, renderStyle: MixedMathRenderStyle) -> String {
        guard let regex = try? NSRegularExpression(pattern: "`([^`\\n]+)`") else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange  = Range(match.range,        in: result),
                  let innerRange = Range(match.range(at: 1), in: result) else { continue }
            let inner = String(result[innerRange])
            result.replaceSubrange(
                fullRange,
                with: "<code class=\"inline-code \(renderStyle.inlineCodeClassName)\">\(inner)</code>"
            )
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
        var lastRenderedSignature: String = ""

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

        /// Safely evaluates JS once the `updateMathContent` function exists.
        /// This fixes the race condition where `evaluateJavaScript` fires before baseHTMLTemplate is fully loaded in new pooled webviews.
        func applyUpdate(js: String, retries: Int = 15) {
            guard let webView = webView else { return }
            webView.evaluateJavaScript("typeof updateMathContent") { result, _ in
                if let str = result as? String, str == "function" {
                    webView.evaluateJavaScript(js)
                } else if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.applyUpdate(js: js, retries: retries - 1)
                    }
                }
            }
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
