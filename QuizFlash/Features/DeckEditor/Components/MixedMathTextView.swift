import SwiftUI
import WebKit
import ObjectiveC.runtime

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

private var quizFlashHorizontalOverflowAssociationKey: UInt8 = 0

#if DEBUG
struct MathWebViewPoolDebugSnapshot: Equatable {
    let idleCount: Int
    let pendingPrewarmTaskCount: Int
    let isPrewarmed: Bool
}
#endif

extension WKWebView {
    var quizflashHasHorizontalOverflow: Bool {
        get {
            (objc_getAssociatedObject(self, &quizFlashHorizontalOverflowAssociationKey) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &quizFlashHorizontalOverflowAssociationKey,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
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
    /// When `false` the underlying WKWebView stops participating in hit-testing
    /// so taps and swipes pass through to the parent SwiftUI view.
    /// Set to `false` in read-only contexts (card playback, preview).
    /// Set to `true` in editable contexts (FlashcardEditorView, ZoneContentView).
    var isInteractive: Bool = true
    /// Re-enables interaction in read-only mode for overflowing display-math
    /// blocks that need local horizontal panning.
    var allowsReadOnlyOverflowScrolling: Bool = false
    var lineLimit: Int? = nil
    var renderStyle: MixedMathRenderStyle = .standard
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var webHeight: CGFloat = 50
    @State private var horizontalOverflowState = HorizontalOverflowState()

    var body: some View {
        let clean = MathTextSanitizer.heal(text)
        let signature = renderSignature(for: clean)
        let shouldAllowWebInteraction = isInteractive || (
            allowsReadOnlyOverflowScrolling && MathTextSanitizer.containsMath(clean)
        )
        let shouldShowHorizontalOverflowHint = (
            !isInteractive
            && allowsReadOnlyOverflowScrolling
            && horizontalOverflowState.hasOverflow
        )

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
                horizontalOverflowState: $horizontalOverflowState,
                isInteractive: isInteractive,
                allowsReadOnlyOverflowScrolling: shouldAllowWebInteraction && !isInteractive,
                onTap: onTap
            )
            .frame(height: webHeight)
            .frame(maxWidth: .infinity)
            // Keep hit-testing disabled for standard read-only previews, but
            // allow block-math overflow areas to receive horizontal pans.
            .allowsHitTesting(shouldAllowWebInteraction)
            .overlay {
                if shouldShowHorizontalOverflowHint {
                    HorizontalOverflowIndicator(
                        canScrollLeft: horizontalOverflowState.canScrollLeft,
                        canScrollRight: horizontalOverflowState.canScrollRight
                    )
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: UIConstants.Animation.instant), value: shouldShowHorizontalOverflowHint)
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
// 1. REUSED WKWEBVIEWS
//    On iOS 15+ a custom WKProcessPool no longer changes WebKit process
//    behaviour. The real win here is reusing already initialised WKWebView
//    instances so KaTeX assets, DOM scaffolding, and renderer warm-up are paid
//    once instead of on every card appearance.
//
// 2. BOUNDED POOL SIZE (maxPoolSize)
//    Without a cap, enqueue() grows the pool indefinitely. Opening a deck with
//    40 math cards and closing it would leave 40 WKWebViews in memory forever.
//    When the pool is at capacity, excess WebViews are explicitly destroyed
//    instead of being retained.
//
// 3. BOUNDED PREWARM
//    prewarm() is intentionally small and delayed. WebKit startup is expensive on
//    iOS 17, so normal Home/Library usage must not pay for a full math pool.
//

class MathWebViewPool {

    static let shared = MathWebViewPool()

    /// Notification token to flush the pool if the OS runs extremely low on RAM.
    private var memoryWarningTask: Task<Void, Never>?
    private var prewarmTasks: [Task<Void, Never>] = []

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
        prewarmTasks.forEach { $0.cancel() }
    }

    // Maximum number of idle WebViews kept alive between uses.
    // Increased to 12 to support scrolling through grid view with KaTeX
    // while maintaining a stable process limit.
    private static let maxPoolSize = 12

    private var pool: [WKWebView] = []
    private var isPrewarmed = false

    // MARK: - Prewarm

    /// Populates a small number of ready-to-use WebViews after the app settles.
    func prewarm(count: Int = 2, initialDelayMilliseconds: Int = 1_500) {
        guard !isPrewarmed else { return }
        isPrewarmed = true

        let clamped = min(count, Self.maxPoolSize)
        for i in 0..<clamped {
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(initialDelayMilliseconds + (350 * i)))
                guard let self, !Task.isCancelled else { return }
                // Ensure we don't exceed max size during async initialization
                if self.pool.count < Self.maxPoolSize {
                    self.pool.append(self.create())
                }
            }
            prewarmTasks.append(task)
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
        prewarmTasks.forEach { $0.cancel() }
        prewarmTasks.removeAll()
        pool.removeAll()
        isPrewarmed = false
    }

#if DEBUG
    func debugSnapshot() -> MathWebViewPoolDebugSnapshot {
        MathWebViewPoolDebugSnapshot(
            idleCount: pool.count,
            pendingPrewarmTaskCount: prewarmTasks.count,
            isPrewarmed: isPrewarmed
        )
    }
#endif

    // MARK: - Factory

    private func create() -> WKWebView {
        let config = WKWebViewConfiguration()

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
    @Binding var horizontalOverflowState: HorizontalOverflowState
    /// When `false`, the WKWebView becomes non-interactive so taps and drags
    /// continue to the parent SwiftUI surface unobstructed.
    var isInteractive: Bool = true
    /// Keeps display-math blocks pannable in otherwise read-only contexts.
    var allowsReadOnlyOverflowScrolling: Bool = false
    var onTap: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            contentHeight: $contentHeight,
            horizontalOverflowState: $horizontalOverflowState,
            onTap: onTap
        )
    }

    // Called automatically by SwiftUI when the view is removed from the hierarchy.
    // Breaks the retain cycle and returns the WKWebView to the shared pool.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 1. Unlink coordinator to break any lingering weak/unowned chains
        coordinator.cancelPendingUpdate()
        coordinator.webView = nil

        // 2. Remove the script message handler to break the JS context retain cycle
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "heightUpdate")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "overflowUpdate")

        // 3. Return to pool (or discard if full)
        MathWebViewPool.shared.enqueue(uiView)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = MathWebViewPool.shared.dequeue()

        webView.configuration.userContentController.removeScriptMessageHandler(forName: "heightUpdate")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "overflowUpdate")
        let scriptHandlerWrapper = WeakScriptMessageHandler(delegate: context.coordinator)
        webView.configuration.userContentController.add(scriptHandlerWrapper, name: "heightUpdate")
        webView.configuration.userContentController.add(scriptHandlerWrapper, name: "overflowUpdate")

        context.coordinator.webView = webView
        context.coordinator.lastRenderedSignature = renderSignature
        context.coordinator.onTap = onTap
        webView.quizflashHasHorizontalOverflow = false

        // In read-only contexts (playback, preview), disable UIKit interaction
        // unless this view contains display math that needs local horizontal panning.
        applyInteractivity(to: webView)
        configureTapRecognizer(on: webView, coordinator: context.coordinator)

        loadContent(in: webView, context: context)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Re-apply interaction state in case isInteractive changed between renders.
        context.coordinator.onTap = onTap
        webView.quizflashHasHorizontalOverflow = horizontalOverflowState.hasOverflow
        applyInteractivity(to: webView)
        configureTapRecognizer(on: webView, coordinator: context.coordinator)
        guard context.coordinator.lastRenderedSignature != renderSignature else { return }
        context.coordinator.lastRenderedSignature = renderSignature
        loadContent(in: webView, context: context)
    }

    /// Enables or disables UIKit interaction on the WKWebView surface while
    /// keeping the page scroll itself locked in place.
    private func applyInteractivity(to webView: WKWebView) {
        let shouldAllowWebInteraction = isInteractive || allowsReadOnlyOverflowScrolling
        webView.isUserInteractionEnabled = shouldAllowWebInteraction
        webView.scrollView.isUserInteractionEnabled = shouldAllowWebInteraction
        // Keep the page itself locked; overflowing math uses the DOM container's
        // own horizontal overflow instead of scrolling the WKWebView page.
        webView.scrollView.isScrollEnabled = false
    }

    private func configureTapRecognizer(on webView: WKWebView, coordinator: Coordinator) {
        webView.gestureRecognizers?
            .compactMap { $0 as? MathWebViewTapGestureRecognizer }
            .forEach { webView.removeGestureRecognizer($0) }
        webView.scrollView.gestureRecognizers?
            .compactMap { $0 as? MathWebViewTapGestureRecognizer }
            .forEach { webView.scrollView.removeGestureRecognizer($0) }

        guard onTap != nil else { return }

        let tapGesture = MathWebViewTapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.numberOfTapsRequired = 1
        tapGesture.delegate = coordinator
        webView.scrollView.addGestureRecognizer(tapGesture)
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

        let safeText  = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let mdText    = processHTMLMarkdown(safeText)
        let finalText = processInlineCode(mdText, renderStyle: renderStyle)
        
        // Base64 encoding cleanly passes arbitrary UTF-8 characters across the JS payload boundary
        guard let b64 = finalText.data(using: .utf8)?.base64EncodedString() else { return }
        
        let allowDisplayMathOverflowScrolling = allowsReadOnlyOverflowScrolling ? "true" : "false"
        let js = "updateMathContent('\(b64)', '\(cssColor)', \(fontSize), '\(cssAlign)', '\(weight)', '\(fontStyle)', \(allowDisplayMathOverflowScrolling));"
        context.coordinator.applyUpdate(js: js)
    }

    // -------------------------------------------------------------------------
    // MARK: - HTML Builder
    // -------------------------------------------------------------------------

    /// A static, one-time HTML template injected into cached WebViews.
    static var baseHTMLTemplate: String {
        let katexTags: String
        if let localTags = MathTextSanitizer.katexLocalHTMLTags() {
            katexTags = localTags
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
                touch-action: pan-x;
                overscroll-behavior-x: contain;
            }
            .katex-display::-webkit-scrollbar { display: none; }
            .katex-inline-scroll {
                display: block;
                max-width: 100%;
                overflow-x: auto;
                overflow-y: hidden;
                padding: 4px 0;
                -webkit-overflow-scrolling: touch;
                scrollbar-width: none;
                touch-action: pan-x;
                overscroll-behavior-x: contain;
            }
            .katex-inline-scroll::-webkit-scrollbar { display: none; }
            .katex-inline-scroll > .katex {
                display: inline-block;
                min-width: max-content;
            }
            .katex-inline-boundary {
                white-space: nowrap;
            }
            .katex { font-size: 1.08em !important; }
            .katex-error {
                color: inherit !important;
                font-style: normal !important;
                font-family: -apple-system, sans-serif !important;
            }
            code.inline-code {
                font-family: ui-monospace, 'SF Mono', Menlo, monospace;
                font-size: 0.88em;
                max-width: 100%;
                overflow-wrap: anywhere;
                word-break: break-word;
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
        \(MathTextSanitizer.katexExtraMacrosJSObjectLiteral)
        };
        
        let updateTimeout;

        function updateMathContent(b64, color, fontSize, align, weight, fontStyle, allowDisplayMathOverflowScrolling) {
            document.body.style.color = color;
            document.body.style.fontSize = fontSize + 'px';
            document.body.style.textAlign = align;
            document.body.style.fontWeight = weight;
            document.body.style.fontStyle = fontStyle;
            document.body.dataset.allowDisplayMathOverflowScrolling = allowDisplayMathOverflowScrolling ? '1' : '0';

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
            prepareOverflowContainers();
            reportHeight();
            reportOverflow();
            updateTimeout = setTimeout(reportHeight, 50);
            setTimeout(reportOverflow, 50);
        }

        function prepareOverflowContainers() {
            const contentDiv = document.getElementById('content');
            unwrapInlineBoundaryContainers(contentDiv);
            unwrapInlineOverflowContainers(contentDiv);
            bindInlineTrailingPunctuation(contentDiv);

            const overflowTargets = [
                ...Array.from(contentDiv.querySelectorAll('.katex-display'))
            ];

            const allowOverflow = document.body.dataset.allowDisplayMathOverflowScrolling === '1';
            if (allowOverflow) {
                const maxInlineWidth = contentDiv.getBoundingClientRect().width;
                const inlineKatex = Array.from(contentDiv.querySelectorAll('.katex')).filter(node => !node.closest('.katex-display'));

                inlineKatex.forEach(node => {
                    const inlineWidth = node.getBoundingClientRect().width;
                    if (inlineWidth <= maxInlineWidth + 1) { return; }

                    const wrapper = document.createElement('span');
                    wrapper.className = 'katex-inline-scroll';
                    node.parentNode.insertBefore(wrapper, node);
                    wrapper.appendChild(node);
                    overflowTargets.push(wrapper);
                });
            }

            overflowTargets.forEach(block => {
                block.onscroll = reportOverflow;
            });
        }

        function bindInlineTrailingPunctuation(contentDiv) {
            const inlineKatex = Array.from(contentDiv.querySelectorAll('.katex')).filter(node => !node.closest('.katex-display'));

            inlineKatex.forEach(node => {
                const next = node.nextSibling;
                if (!next || next.nodeType !== Node.TEXT_NODE) { return; }

                const text = next.textContent || '';
                const match = text.match(/^([.,;:!?]+)/);
                if (!match) { return; }

                const punctuation = match[1];
                const remainder = text.slice(punctuation.length);
                const wrapper = document.createElement('span');
                wrapper.className = 'katex-inline-boundary';

                node.parentNode.insertBefore(wrapper, node);
                wrapper.appendChild(node);
                wrapper.appendChild(document.createTextNode(punctuation));

                if (remainder.length > 0) {
                    next.textContent = remainder;
                } else {
                    next.parentNode.removeChild(next);
                }
            });
        }

        function unwrapInlineOverflowContainers(contentDiv) {
            Array.from(contentDiv.querySelectorAll('.katex-inline-scroll')).forEach(wrapper => {
                const parent = wrapper.parentNode;
                while (wrapper.firstChild) {
                    parent.insertBefore(wrapper.firstChild, wrapper);
                }
                parent.removeChild(wrapper);
            });
        }

        function unwrapInlineBoundaryContainers(contentDiv) {
            Array.from(contentDiv.querySelectorAll('.katex-inline-boundary')).forEach(wrapper => {
                const parent = wrapper.parentNode;
                while (wrapper.firstChild) {
                    parent.insertBefore(wrapper.firstChild, wrapper);
                }
                parent.removeChild(wrapper);
            });
        }

        function reportHeight() {
            const el = document.getElementById('content');
            const h = Math.max(
                el.getBoundingClientRect().height,
                el.scrollHeight,
                document.body.scrollHeight,
                document.documentElement.scrollHeight
            );
            if (h > 0 && window.webkit && window.webkit.messageHandlers.heightUpdate) {
                window.webkit.messageHandlers.heightUpdate.postMessage(Math.ceil(h));
            }
        }

        function reportOverflow() {
            const allowOverflow = document.body.dataset.allowDisplayMathOverflowScrolling === '1';
            if (!window.webkit || !window.webkit.messageHandlers.overflowUpdate) { return; }
            if (!allowOverflow) {
                window.webkit.messageHandlers.overflowUpdate.postMessage(false);
                return;
            }

            const displays = Array.from(document.querySelectorAll('.katex-display, .katex-inline-scroll'));
            const overflowState = displays.reduce(
                (state, block) => {
                    const hasOverflow = (block.scrollWidth - block.clientWidth) > 1;
                    if (!hasOverflow) { return state; }

                    const maxScrollLeft = Math.max(0, block.scrollWidth - block.clientWidth);
                    if (block.scrollLeft > 1) {
                        state.canScrollLeft = true;
                    }
                    if (block.scrollLeft < maxScrollLeft - 1) {
                        state.canScrollRight = true;
                    }
                    return state;
                },
                { canScrollLeft: false, canScrollRight: false }
            );
            window.webkit.messageHandlers.overflowUpdate.postMessage(overflowState);
        }

        if (window.ResizeObserver) {
            new ResizeObserver(() => {
                prepareOverflowContainers();
                reportHeight();
                reportOverflow();
            }).observe(document.getElementById('content'));
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

    class Coordinator: NSObject, WKScriptMessageHandler, UIGestureRecognizerDelegate {
        @Binding var contentHeight: CGFloat
        @Binding var horizontalOverflowState: HorizontalOverflowState
        weak var webView: WKWebView? // WEAK reference to break the retain cycle
        var lastRenderedSignature: String = ""
        var onTap: (() -> Void)?
        private var updateRetryTask: Task<Void, Never>?

        init(
            contentHeight: Binding<CGFloat>,
            horizontalOverflowState: Binding<HorizontalOverflowState>,
            onTap: (() -> Void)?
        ) {
            _contentHeight = contentHeight
            _horizontalOverflowState = horizontalOverflowState
            self.onTap = onTap
        }

        deinit {
            updateRetryTask?.cancel()
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "heightUpdate":
                guard let h = message.body as? Double, h > 0 else { return }
                Task { @MainActor in
                    self.contentHeight = CGFloat(h)
                }

            case "overflowUpdate":
                if let overflowPayload = message.body as? [String: Any] {
                    let canScrollLeft = overflowPayload["canScrollLeft"] as? Bool ?? false
                    let canScrollRight = overflowPayload["canScrollRight"] as? Bool ?? false
                    Task { @MainActor in
                        self.webView?.quizflashHasHorizontalOverflow = canScrollLeft || canScrollRight
                        self.horizontalOverflowState = HorizontalOverflowState(
                            canScrollLeft: canScrollLeft,
                            canScrollRight: canScrollRight
                        )
                    }
                    return
                }

                guard let hasOverflow = message.body as? Bool else { return }
                Task { @MainActor in
                    self.webView?.quizflashHasHorizontalOverflow = hasOverflow
                    self.horizontalOverflowState = hasOverflow
                        ? HorizontalOverflowState(canScrollLeft: false, canScrollRight: true)
                        : .init()
                }

            default:
                return
            }
        }

        /// Safely evaluates JS once the `updateMathContent` function exists.
        /// This fixes the race condition where `evaluateJavaScript` fires before baseHTMLTemplate is fully loaded in new pooled webviews.
        func applyUpdate(js: String, retries: Int = 15) {
            updateRetryTask?.cancel()
            attemptUpdate(js: js, retries: retries)
        }

        func cancelPendingUpdate() {
            updateRetryTask?.cancel()
            updateRetryTask = nil
        }

        private func attemptUpdate(js: String, retries: Int) {
            guard let webView = webView else { return }
            webView.evaluateJavaScript("typeof updateMathContent") { [weak self] result, _ in
                guard let self else { return }
                if let str = result as? String, str == "function" {
                    webView.evaluateJavaScript(js)
                } else if retries > 0 {
                    self.updateRetryTask?.cancel()
                    self.updateRetryTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(50))
                        guard let self, !Task.isCancelled else { return }
                        self.attemptUpdate(js: js, retries: retries - 1)
                    }
                }
            }
        }

        @objc func handleTap() {
            onTap?()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

// =============================================================================
// MARK: - HorizontalOverflowIndicator
// =============================================================================

struct HorizontalOverflowState: Equatable {
    var canScrollLeft: Bool = false
    var canScrollRight: Bool = false

    var hasOverflow: Bool {
        canScrollLeft || canScrollRight
    }
}

private struct HorizontalOverflowIndicator: View {
    let canScrollLeft: Bool
    let canScrollRight: Bool
    private let horizontalOffset: CGFloat = 14

    var body: some View {
        ZStack {
            if canScrollLeft {
                edgeCue(direction: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .offset(x: -horizontalOffset)
            }
            if canScrollRight {
                edgeCue(direction: .trailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .offset(x: horizontalOffset)
            }
        }
        .padding(.vertical, UIConstants.Spacing.medium)
        .accessibilityHidden(true)
    }

    private func edgeCue(direction: OverflowEdgeDirection) -> some View {
        Image(systemName: direction == .leading ? "chevron.compact.left" : "chevron.compact.right")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.38))
    }
}

private enum OverflowEdgeDirection {
    case leading
    case trailing
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

private final class MathWebViewTapGestureRecognizer: UITapGestureRecognizer {}
