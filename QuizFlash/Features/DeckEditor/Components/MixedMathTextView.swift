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

struct MixedMathRenderedTokenDebug: Equatable {
    let text: String
    let kind: String
    let left: CGFloat
    let top: CGFloat
    let width: CGFloat
    let height: CGFloat
    let right: CGFloat
    let bottom: CGFloat
}

struct MixedMathRenderedLineDebug: Equatable {
    let index: Int
    let widthLimit: CGFloat
    let left: CGFloat
    let top: CGFloat
    let width: CGFloat
    let height: CGFloat
    let right: CGFloat
    let bottom: CGFloat
    let tokens: [MixedMathRenderedTokenDebug]
}

struct MixedMathScrollableDebug: Equatable {
    let kind: String
    let wrapperHeight: CGFloat
    let scrollHeight: CGFloat
    let clientHeight: CGFloat
    let visualHeight: CGFloat
    let visualTop: CGFloat
    let visualBottom: CGFloat
    let paddingTop: CGFloat
    let paddingBottom: CGFloat
    let topAdjustment: CGFloat
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
    var intrinsicWidthLimit: CGFloat? = nil
    var intrinsicMeasurementWidthLimit: CGFloat? = nil
    var onIntrinsicContentSizeChange: ((CGSize) -> Void)? = nil
    var onRenderedLineDebugChange: (([MixedMathRenderedLineDebug]) -> Void)? = nil
    var onScrollableDebugChange: (([MixedMathScrollableDebug]) -> Void)? = nil
    var showsRenderDebugBounds: Bool = false
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var webHeight: CGFloat = 50
    @State private var webIntrinsicWidth: CGFloat = 0
    @State private var horizontalOverflowState = HorizontalOverflowState()
    @State private var renderedLineDebug: [MixedMathRenderedLineDebug] = []
    @State private var scrollableDebug: [MixedMathScrollableDebug] = []

    var body: some View {
        let clean = MathTextSanitizer.heal(text)
        let signature = renderSignature(for: clean)
        let usesWebRendering = intrinsicWidthLimit != nil
            || MathTextSanitizer.containsMath(clean)
            || MathTextSanitizer.containsInlineCode(clean)
        let canSupportReadOnlyOverflowScrolling = (
            !isInteractive
            && allowsReadOnlyOverflowScrolling
            && MathTextSanitizer.containsMath(clean)
        )
        let shouldAllowReadOnlyOverflowInteraction = canSupportReadOnlyOverflowScrolling
            && horizontalOverflowState.hasOverflow
        let shouldAllowWebInteraction = isInteractive || shouldAllowReadOnlyOverflowInteraction
        let shouldShowHorizontalOverflowHint = (
            !isInteractive
            && allowsReadOnlyOverflowScrolling
            && horizontalOverflowState.hasOverflow
        )
        let reportsRenderedLineDebug = onRenderedLineDebugChange != nil
        let reportsScrollableDebug = onScrollableDebugChange != nil

        if usesWebRendering {
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
                intrinsicContentWidth: $webIntrinsicWidth,
                renderedLineDebug: $renderedLineDebug,
                scrollableDebug: $scrollableDebug,
                reportsIntrinsicContentWidth: intrinsicWidthLimit != nil,
                reportsRenderedLineDebug: reportsRenderedLineDebug,
                reportsScrollableDebug: reportsScrollableDebug,
                intrinsicMeasurementWidthLimit: intrinsicMeasurementWidthLimit,
                showsRenderDebugBounds: showsRenderDebugBounds,
                horizontalOverflowState: $horizontalOverflowState,
                isInteractive: isInteractive,
                allowsReadOnlyOverflowScrolling: canSupportReadOnlyOverflowScrolling,
                onTap: onTap
            )
            .frame(
                width: mathFrameWidth,
                height: webHeight
            )
            .frame(maxWidth: intrinsicWidthLimit == nil ? .infinity : nil)
            // Keep hit-testing disabled for normal read-only math so card taps
            // reach the parent instantly. Enable WebView touch only for actual
            // horizontal overflow that needs local panning.
            .allowsHitTesting(shouldAllowWebInteraction)
            .onChange(of: webHeight) { _, _ in
                reportIntrinsicContentSize()
            }
            .onChange(of: webIntrinsicWidth) { _, _ in
                reportIntrinsicContentSize()
            }
            .onChange(of: horizontalOverflowState) { _, _ in
                reportIntrinsicContentSize()
            }
            .onChange(of: renderedLineDebug) { _, newValue in
                onRenderedLineDebugChange?(newValue)
            }
            .onChange(of: scrollableDebug) { _, newValue in
                onScrollableDebugChange?(newValue)
            }
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
            emphasisText(clean)
                .foregroundColor(textColor)
                .multilineTextAlignment(nsTextAlignment)
                .lineLimit(lineLimit)
                .frame(
                    width: intrinsicWidthLimit,
                    alignment: frameAlignment
                )
                .frame(maxWidth: intrinsicWidthLimit == nil ? .infinity : nil, alignment: frameAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) { proxy in
                    CGSize(width: ceil(proxy.size.width), height: ceil(proxy.size.height))
                } action: { newSize in
                    guard let intrinsicWidthLimit else { return }
                    onIntrinsicContentSizeChange?(
                        measuredPlainTextSize(
                            clean,
                            availableWidth: intrinsicWidthLimit,
                            renderedHeight: newSize.height
                        )
                    )
                }
        }
    }

    private var mathFrameWidth: CGFloat? {
        intrinsicWidthLimit.map { max($0, 1) }
    }

    private func reportIntrinsicContentSize() {
        guard intrinsicWidthLimit != nil else { return }
        let limit = max(intrinsicWidthLimit ?? 1, 1)
        let measurementLimit = intrinsicMeasurementWidthLimit.map { max($0, 1) }
        let widthLimit = measurementLimit ?? limit
        let measuredWidth = webIntrinsicWidth > 0
            ? max(ceil(webIntrinsicWidth), 1)
            : widthLimit
        let width = measurementLimit == nil && horizontalOverflowState.hasOverflow
            ? limit
            : min(measuredWidth, widthLimit)
        let height = max(ceil(webHeight), 1)
        onIntrinsicContentSizeChange?(CGSize(width: width, height: height))
    }

    private func measuredPlainTextSize(
        _ value: String,
        availableWidth: CGFloat,
        renderedHeight: CGFloat
    ) -> CGSize {
        guard !value.isEmpty else {
            return CGSize(width: 1, height: max(ceil(renderedHeight), 1))
        }

        let attributed = plainAttributedString(for: value)
        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: max(availableWidth, 1), height: .greatestFiniteMagnitude)
        )

        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.usesFontLeading = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var widestLine: CGFloat = 1
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            widestLine = max(widestLine, ceil(usedRect.width))
        }

        return CGSize(
            width: min(max(widestLine, 1), max(availableWidth, 1)),
            height: max(ceil(renderedHeight), 1)
        )
    }

    private func plainAttributedString(for value: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var plainBuffer = ""
        var cursor = value.startIndex

        func append(_ text: String, isEmphasized: Bool = false) {
            guard !text.isEmpty else { return }
            result.append(
                NSAttributedString(
                    string: text,
                    attributes: plainTextAttributes(isEmphasized: isEmphasized)
                )
            )
        }

        func flushPlainBuffer() {
            append(plainBuffer)
            plainBuffer.removeAll(keepingCapacity: true)
        }

        while cursor < value.endIndex {
            if value[cursor...].hasPrefix("**") {
                let contentStart = value.index(cursor, offsetBy: 2)
                if let closing = value[contentStart...].range(of: "**") {
                    flushPlainBuffer()
                    append(String(value[contentStart..<closing.lowerBound]), isEmphasized: true)
                    cursor = closing.upperBound
                    continue
                }
            }

            plainBuffer.append(value[cursor])
            cursor = value.index(after: cursor)
        }

        flushPlainBuffer()
        return result
    }

    private func plainTextAttributes(isEmphasized: Bool) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = uiKitTextAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping

        return [
            .font: plainUIFont(isEmphasized: isEmphasized),
            .paragraphStyle: paragraphStyle
        ]
    }

    private func plainUIFont(isEmphasized: Bool) -> UIFont {
        let weight: UIFont.Weight = (isBold || isEmphasized) ? .bold : .regular
        let baseFont = UIFont.systemFont(ofSize: fontSize, weight: weight)

        guard isItalic,
              let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic)
        else {
            return baseFont
        }

        return UIFont(descriptor: descriptor, size: fontSize)
    }

    private func renderSignature(for cleanText: String) -> String {
        [
            cleanText,
            String(format: "%.3f", fontSize),
            colorSignature,
            alignmentSignature,
            isBold ? "1" : "0",
            isItalic ? "1" : "0",
            renderStyle.rawValue,
            String(format: "%.3f", intrinsicMeasurementWidthLimit ?? -1),
            showsRenderDebugBounds ? "debug-bounds" : "normal-bounds"
        ].joined(separator: "|")
    }

    private var swiftUIFont: Font {
        swiftUIFont(isEmphasized: false)
    }

    private func swiftUIFont(isEmphasized: Bool) -> Font {
        let base = Font.system(size: fontSize)
        switch (isBold || isEmphasized, isItalic) {
        case (true,  true):  return base.bold().italic()
        case (true,  false): return base.bold()
        case (false, true):  return base.italic()
        case (false, false): return base
        }
    }

    /// Renders AI-authored bold markers without routing plain card text through
    /// localization keys or broad Markdown interpretation.
    private func emphasisText(_ value: String) -> Text {
        var result = Text("")
        var plainBuffer = ""
        var cursor = value.startIndex

        func flushPlainBuffer() {
            guard !plainBuffer.isEmpty else { return }
            result = result + Text(verbatim: plainBuffer)
                .font(swiftUIFont(isEmphasized: false))
            plainBuffer.removeAll(keepingCapacity: true)
        }

        while cursor < value.endIndex {
            if value[cursor...].hasPrefix("**") {
                let contentStart = value.index(cursor, offsetBy: 2)
                if let closing = value[contentStart...].range(of: "**") {
                    flushPlainBuffer()
                    let inner = String(value[contentStart..<closing.lowerBound])
                    result = result + Text(verbatim: inner)
                        .font(swiftUIFont(isEmphasized: true))
                    cursor = closing.upperBound
                    continue
                }
            }

            plainBuffer.append(value[cursor])
            cursor = value.index(after: cursor)
        }

        flushPlainBuffer()
        return result
    }

    private var nsTextAlignment: TextAlignment {
        switch alignment {
        case .center:   return .center
        case .trailing: return .trailing
        default:        return .leading
        }
    }

    private var uiKitTextAlignment: NSTextAlignment {
        switch alignment {
        case .center:   return .center
        case .trailing: return .right
        default:        return .left
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
    @Binding var intrinsicContentWidth: CGFloat
    @Binding var renderedLineDebug: [MixedMathRenderedLineDebug]
    @Binding var scrollableDebug: [MixedMathScrollableDebug]
    let reportsIntrinsicContentWidth: Bool
    let reportsRenderedLineDebug: Bool
    let reportsScrollableDebug: Bool
    let intrinsicMeasurementWidthLimit: CGFloat?
    let showsRenderDebugBounds: Bool
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
            intrinsicContentWidth: $intrinsicContentWidth,
            renderedLineDebug: $renderedLineDebug,
            scrollableDebug: $scrollableDebug,
            reportsIntrinsicContentWidth: reportsIntrinsicContentWidth,
            reportsRenderedLineDebug: reportsRenderedLineDebug,
            reportsScrollableDebug: reportsScrollableDebug,
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
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "widthUpdate")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "lineDebugUpdate")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "scrollableDebugUpdate")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "overflowUpdate")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "tapUpdate")

        // 3. Return to pool (or discard if full)
        MathWebViewPool.shared.enqueue(uiView)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = MathWebViewPool.shared.dequeue()

        webView.configuration.userContentController.removeScriptMessageHandler(forName: "heightUpdate")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "widthUpdate")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lineDebugUpdate")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scrollableDebugUpdate")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "overflowUpdate")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tapUpdate")
        let scriptHandlerWrapper = WeakScriptMessageHandler(delegate: context.coordinator)
        webView.configuration.userContentController.add(scriptHandlerWrapper, name: "heightUpdate")
        webView.configuration.userContentController.add(scriptHandlerWrapper, name: "widthUpdate")
        if reportsRenderedLineDebug {
            webView.configuration.userContentController.add(scriptHandlerWrapper, name: "lineDebugUpdate")
        }
        if reportsScrollableDebug {
            webView.configuration.userContentController.add(scriptHandlerWrapper, name: "scrollableDebugUpdate")
        }
        webView.configuration.userContentController.add(scriptHandlerWrapper, name: "overflowUpdate")
        webView.configuration.userContentController.add(scriptHandlerWrapper, name: "tapUpdate")

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
        context.coordinator.reportsIntrinsicContentWidth = reportsIntrinsicContentWidth
        context.coordinator.configureLineDebugHandler(on: webView, enabled: reportsRenderedLineDebug)
        context.coordinator.configureScrollableDebugHandler(on: webView, enabled: reportsScrollableDebug)
        webView.quizflashHasHorizontalOverflow = horizontalOverflowState.hasOverflow
        applyInteractivity(to: webView)
        configurePanRecognizers(on: webView, coordinator: context.coordinator)
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

    private func configurePanRecognizers(on webView: WKWebView, coordinator: Coordinator) {
        let recognizers = (webView.gestureRecognizers ?? []) + (webView.scrollView.gestureRecognizers ?? [])
        recognizers
            .compactMap { $0 as? UIPanGestureRecognizer }
            .filter { $0 !== webView.scrollView.panGestureRecognizer }
            .forEach { $0.delegate = coordinator }
    }

    private func configureTapRecognizer(on webView: WKWebView, coordinator: Coordinator) {
        webView.gestureRecognizers?
            .compactMap { $0 as? MathWebViewTapGestureRecognizer }
            .forEach { webView.removeGestureRecognizer($0) }
        webView.scrollView.gestureRecognizers?
            .compactMap { $0 as? MathWebViewTapGestureRecognizer }
            .forEach { webView.scrollView.removeGestureRecognizer($0) }

        guard onTap != nil else { return }

        [webView, webView.scrollView].forEach { targetView in
            let tapGesture = MathWebViewTapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
            tapGesture.cancelsTouchesInView = false
            tapGesture.delaysTouchesBegan = false
            tapGesture.delaysTouchesEnded = false
            tapGesture.numberOfTapsRequired = 1
            tapGesture.delegate = coordinator
            targetView.addGestureRecognizer(tapGesture)
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

        let safeText  = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let mdText    = processHTMLMarkdown(safeText)
        let finalText = processInlineCode(mdText, renderStyle: renderStyle)
        
        // Base64 encoding cleanly passes arbitrary UTF-8 characters across the JS payload boundary
        guard let b64 = finalText.data(using: .utf8)?.base64EncodedString() else { return }
        
        let allowDisplayMathOverflowScrolling = allowsReadOnlyOverflowScrolling ? "true" : "false"
        let measurementWidth = max(ceil(intrinsicMeasurementWidthLimit ?? 0), 0)
        let debugBounds = showsRenderDebugBounds ? "true" : "false"
        let js = "updateMathContent('\(b64)', '\(cssColor)', \(fontSize), '\(cssAlign)', '\(weight)', '\(fontStyle)', \(allowDisplayMathOverflowScrolling), \(measurementWidth), \(debugBounds));"
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
                overflow-wrap: normal;
                word-break: normal;
                hyphens: none;
                -webkit-hyphens: none;
                margin: 0;
                padding: 0;
            }
            #content {
                width: 100%;
                white-space: normal;
                overflow-wrap: normal;
                word-break: normal;
                hyphens: none;
                -webkit-hyphens: none;
                padding: 2px 0px;
                line-height: 1.5;
                overflow-x: visible;
                overflow-y: visible;
                scrollbar-width: none;
            }
            #content.qf-token-flow {
                display: flex;
                flex-wrap: wrap;
                align-items: baseline;
                column-gap: 0.18em;
                row-gap: 0;
                align-content: flex-start;
            }
            #content.qf-token-flow br {
                flex-basis: 100%;
                width: 100%;
                height: 0;
            }
            #content.qf-token-flow .mixed-text-token,
            #content.qf-token-flow code.inline-code,
            #content.qf-token-flow .katex:not(.katex-display .katex) {
                flex: 0 0 auto;
            }
            .mixed-text-token {
                display: inline-block;
                white-space: nowrap;
            }
            #content::-webkit-scrollbar { display: none; }
            .katex-display {
                flex: 0 0 100%;
                margin: 0;
                overflow-x: auto;
                overflow-y: visible !important;
                padding: 0;
                line-height: normal;
                -webkit-overflow-scrolling: touch;
                scrollbar-width: none;
                touch-action: pan-x;
                overscroll-behavior-x: contain;
            }
            .katex-display::-webkit-scrollbar { display: none; }
            .katex-inline-scroll {
                display: inline-block;
                vertical-align: middle;
                max-width: 100%;
                overflow-x: auto;
                overflow-y: visible;
                padding: 0;
                line-height: 1.5;
                -webkit-overflow-scrolling: touch;
                scrollbar-width: none;
                touch-action: pan-x;
                overscroll-behavior-x: contain;
            }
            #content.qf-token-flow .katex-inline-scroll {
                flex: 0 0 100%;
                width: 100%;
                min-height: 1.5em;
            }
            .katex-inline-scroll::-webkit-scrollbar { display: none; }
            .katex-inline-scroll > .katex {
                display: inline-block;
                min-width: max-content;
            }
            .katex-inline-boundary {
                white-space: nowrap;
            }
            .katex-inline-atomic {
                display: inline-block;
                max-width: none;
                white-space: nowrap;
                vertical-align: baseline;
            }
            .katex-inline-atomic > .katex-html {
                display: inline-block;
                white-space: nowrap;
            }
            .nonbreaking-hyphen-token {
                white-space: nowrap;
            }
            body[data-render-debug-bounds="1"] .mixed-text-token {
                background: rgba(255, 214, 10, 0.22);
                box-shadow: inset 0 0 0 1px rgba(255, 214, 10, 0.72);
                border-radius: 3px;
            }
            body[data-render-debug-bounds="1"] code.inline-code {
                background: rgba(52, 199, 89, 0.24) !important;
                box-shadow: inset 0 0 0 1px rgba(52, 199, 89, 0.78);
                border-radius: 3px;
            }
            body[data-render-debug-bounds="1"] .katex {
                background: rgba(0, 122, 255, 0.22);
                box-shadow: inset 0 0 0 1px rgba(0, 122, 255, 0.78);
                border-radius: 3px;
            }
            body[data-render-debug-bounds="1"] .katex .base,
            body[data-render-debug-bounds="1"] .katex .tag {
                background: rgba(255, 45, 85, 0.18);
                box-shadow: inset 0 0 0 1px rgba(255, 45, 85, 0.66);
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
            }
            code.inline-code--standard {
                background: rgba(120, 120, 120, 0.15);
                color: inherit;
                border: 1px solid rgba(120, 120, 120, 0.2);
                border-radius: 6px;
                padding: 2px 6px;
            }
            code.inline-code--deck-card-preview {
                background: transparent;
                color: inherit;
                border: none;
                border-radius: 0;
                padding: 0;
                font-size: 0.92em;
                font-weight: 600;
                letter-spacing: -0.01em;
                opacity: 0.94;
            }
            code.inline-code--atomic {
                max-width: none;
                overflow-wrap: normal;
                word-break: normal;
                white-space: pre;
            }
            code.inline-code--wrapping {
                max-width: 100%;
                overflow-wrap: normal;
                word-break: normal;
                white-space: break-spaces;
            }
            code.inline-code--breakable-token {
                max-width: 100%;
                overflow-wrap: anywhere;
                word-break: break-word;
                white-space: normal;
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
        let tapMovementLimit = 10;
        let tapDurationLimit = 450;
        let syntheticClickSuppressionWindow = 650;
        let tapBridgeState = {
            startPoint: null,
            startTime: 0,
            lastTouchTapTime: 0,
            isInstalled: false
        };

        function updateMathContent(b64, color, fontSize, align, weight, fontStyle, allowDisplayMathOverflowScrolling, intrinsicMeasurementWidthLimit, showsRenderDebugBounds) {
            document.body.style.color = color;
            document.body.style.fontSize = fontSize + 'px';
            document.body.style.textAlign = align;
            document.body.style.fontWeight = weight;
            document.body.style.fontStyle = fontStyle;
            document.body.dataset.allowDisplayMathOverflowScrolling = allowDisplayMathOverflowScrolling ? '1' : '0';
            document.body.dataset.intrinsicMeasurementWidthLimit = intrinsicMeasurementWidthLimit > 0 ? intrinsicMeasurementWidthLimit : '';
            document.body.dataset.renderDebugBounds = showsRenderDebugBounds ? '1' : '0';

            let bin = window.atob(b64);
            let bytes = new Uint8Array(bin.length);
            for (let i = 0; i < bin.length; i++) {
                bytes[i] = bin.charCodeAt(i);
            }
            let text = new TextDecoder('utf-8').decode(bytes);

            const contentDiv = document.getElementById('content');
            installTapBridge(contentDiv);
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

            preserveAuthorLineBreaks(contentDiv);
            wrapInlineFlowTokens(contentDiv);
            classifyInlineMathFlow(contentDiv);
            bindNonBreakingHyphenatedWords(contentDiv);
            clearTimeout(updateTimeout);
            prepareOverflowContainers();
            stabilizeScrollableMathBounds(contentDiv);
            reportLayoutMetrics();
            reportLineDebug();
            reportOverflow();
            updateTimeout = setTimeout(reportLayoutMetrics, 50);
            setTimeout(reportLineDebug, 50);
            setTimeout(reportOverflow, 50);
        }

        function installTapBridge(contentDiv) {
            if (!contentDiv || tapBridgeState.isInstalled) { return; }
            tapBridgeState.isInstalled = true;

            contentDiv.addEventListener('touchstart', event => {
                const touch = event.changedTouches && event.changedTouches[0];
                if (!touch) { return; }
                tapBridgeState.startPoint = { x: touch.clientX, y: touch.clientY };
                tapBridgeState.startTime = Date.now();
            }, { passive: true });

            contentDiv.addEventListener('touchend', event => {
                const touch = event.changedTouches && event.changedTouches[0];
                if (!touch || !tapBridgeState.startPoint) {
                    tapBridgeState.startPoint = null;
                    return;
                }

                const dx = touch.clientX - tapBridgeState.startPoint.x;
                const dy = touch.clientY - tapBridgeState.startPoint.y;
                const distance = Math.hypot(dx, dy);
                const duration = Date.now() - tapBridgeState.startTime;
                tapBridgeState.startPoint = null;

                if (distance > tapMovementLimit || duration > tapDurationLimit) { return; }
                tapBridgeState.lastTouchTapTime = Date.now();
                postTapUpdate();
            }, { passive: true });

            contentDiv.addEventListener('touchcancel', () => {
                tapBridgeState.startPoint = null;
            }, { passive: true });

            contentDiv.addEventListener('click', () => {
                if (Date.now() - tapBridgeState.lastTouchTapTime < syntheticClickSuppressionWindow) { return; }
                postTapUpdate();
            });
        }

        function postTapUpdate() {
            if (window.webkit && window.webkit.messageHandlers.tapUpdate) {
                window.webkit.messageHandlers.tapUpdate.postMessage(true);
            }
        }

        function classifyInlineMathFlow(contentDiv) {
            if (!contentDiv) { return; }

            const inlineKatex = Array.from(contentDiv.querySelectorAll('.katex')).filter(node => !node.closest('.katex-display'));

            inlineKatex.forEach(node => {
                node.classList.add('katex-inline-atomic');
            });
        }

        function preserveAuthorLineBreaks(contentDiv) {
            if (!contentDiv) { return; }

            const textNodes = [];
            const walker = document.createTreeWalker(
                contentDiv,
                NodeFilter.SHOW_TEXT,
                {
                    acceptNode(node) {
                        const parent = node.parentElement;
                        if (!parent || parent.closest('code, .katex, script, style')) {
                            return NodeFilter.FILTER_REJECT;
                        }

                        return (node.textContent || '').includes('\\n')
                            ? NodeFilter.FILTER_ACCEPT
                            : NodeFilter.FILTER_REJECT;
                    }
                }
            );

            let node;
            while ((node = walker.nextNode())) {
                textNodes.push(node);
            }

            textNodes.forEach(textNode => {
                const parts = (textNode.textContent || '').split('\\n');
                const fragment = document.createDocumentFragment();

                parts.forEach((part, index) => {
                    if (index > 0) {
                        fragment.appendChild(document.createElement('br'));
                    }
                    if (part.length > 0) {
                        fragment.appendChild(document.createTextNode(part));
                    }
                });

                textNode.parentNode.replaceChild(fragment, textNode);
            });
        }

        function wrapInlineFlowTokens(contentDiv) {
            if (!contentDiv) { return; }

            contentDiv.classList.add('qf-token-flow');

            const textNodes = [];
            const walker = document.createTreeWalker(
                contentDiv,
                NodeFilter.SHOW_TEXT,
                {
                    acceptNode(node) {
                        const parent = node.parentElement;
                        if (!parent || parent.closest('code, .katex, script, style, .mixed-text-token')) {
                            return NodeFilter.FILTER_REJECT;
                        }

                        return NodeFilter.FILTER_ACCEPT;
                    }
                }
            );

            let node;
            while ((node = walker.nextNode())) {
                textNodes.push(node);
            }

            textNodes.forEach(textNode => {
                const value = textNode.textContent || '';
                if (!/\\S/.test(value)) {
                    textNode.parentNode.removeChild(textNode);
                    return;
                }

                const fragment = document.createDocumentFragment();
                const tokenPattern = /\\S+/g;
                let match;

                while ((match = tokenPattern.exec(value)) !== null) {
                    const wrapper = document.createElement('span');
                    wrapper.className = 'mixed-text-token';
                    wrapper.textContent = match[0];
                    fragment.appendChild(wrapper);
                }

                textNode.parentNode.replaceChild(fragment, textNode);
            });
        }

        function prepareOverflowContainers() {
            const contentDiv = document.getElementById('content');
            unwrapInlineBoundaryContainers(contentDiv);
            unwrapInlineOverflowContainers(contentDiv);
            bindInlineTrailingPunctuation(contentDiv);

            const overflowTargets = Array.from(contentDiv.querySelectorAll('.katex-display'));

            const allowOverflow = document.body.dataset.allowDisplayMathOverflowScrolling === '1';
            if (allowOverflow) {
                const contentRect = contentDiv.getBoundingClientRect();
                const maxInlineWidth = contentRect.width;
                const inlineKatex = Array.from(contentDiv.querySelectorAll('.katex')).filter(node => !node.closest('.katex-display'));

                inlineKatex.forEach(node => {
                    const inlineWidth = node.getBoundingClientRect().width;
                    if (!inlineMathNeedsOverflowContainer(node, contentRect, maxInlineWidth)) { return; }

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

        function inlineMathNeedsOverflowContainer(node, contentRect, maxInlineWidth) {
            const rect = visualBoundsForElement(node) || node.getBoundingClientRect();
            const tolerance = 1;
            const visualWidth = rect.right - rect.left;

            if (visualWidth > maxInlineWidth + tolerance) { return true; }
            if (rect.left < contentRect.left - tolerance) { return true; }
            if (rect.right > contentRect.right + tolerance) { return true; }

            return false;
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

        function bindNonBreakingHyphenatedWords(contentDiv) {
            if (!contentDiv) { return; }

            const pattern = /[\\p{L}\\p{N}]+(?:-[\\p{L}\\p{N}]+)+/gu;
            const textNodes = [];
            const walker = document.createTreeWalker(
                contentDiv,
                NodeFilter.SHOW_TEXT,
                {
                    acceptNode(node) {
                        const parent = node.parentElement;
                        if (!parent || parent.closest('code, .katex, script, style')) {
                            return NodeFilter.FILTER_REJECT;
                        }

                        pattern.lastIndex = 0;
                        return pattern.test(node.textContent || '')
                            ? NodeFilter.FILTER_ACCEPT
                            : NodeFilter.FILTER_REJECT;
                    }
                }
            );

            let node;
            while ((node = walker.nextNode())) {
                textNodes.push(node);
            }

            textNodes.forEach(textNode => {
                const value = textNode.textContent || '';
                const fragment = document.createDocumentFragment();
                let lastIndex = 0;

                pattern.lastIndex = 0;
                for (const match of value.matchAll(pattern)) {
                    const index = match.index || 0;
                    if (index > lastIndex) {
                        fragment.appendChild(document.createTextNode(value.slice(lastIndex, index)));
                    }

                    const wrapper = document.createElement('span');
                    wrapper.className = 'nonbreaking-hyphen-token';
                    wrapper.textContent = match[0];
                    fragment.appendChild(wrapper);
                    lastIndex = index + match[0].length;
                }

                if (lastIndex < value.length) {
                    fragment.appendChild(document.createTextNode(value.slice(lastIndex)));
                }

                textNode.parentNode.replaceChild(fragment, textNode);
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

        function stabilizeScrollableMathBounds(contentDiv) {
            if (!contentDiv) { return; }

            const debugRows = [];

            Array.from(contentDiv.querySelectorAll('.katex-display, .katex-inline-scroll')).forEach(wrapper => {
                const math = wrapper.querySelector('.katex');
                if (!math) { return; }

                wrapper.style.height = '';
                wrapper.style.minHeight = '';
                math.style.position = '';
                math.style.top = '';

                const wrapperRect = wrapper.getBoundingClientRect();
                const visualBounds = visualBoundsForElement(math);
                if (!visualBounds) { return; }

                const style = window.getComputedStyle(wrapper);
                const paddingTop = parseFloat(style.paddingTop || '0') || 0;
                const paddingBottom = parseFloat(style.paddingBottom || '0') || 0;
                const visualTop = visualBounds.top - wrapperRect.top;
                const visualBottom = visualBounds.bottom - wrapperRect.top;
                const topAdjustment = Math.max(paddingTop - visualTop, 0);
                const requiredHeight = Math.ceil(Math.max(
                    wrapperRect.height,
                    wrapper.scrollHeight,
                    visualBottom + topAdjustment + paddingBottom
                ));

                if (requiredHeight > Math.ceil(wrapperRect.height)) {
                    wrapper.style.height = requiredHeight + 'px';
                    wrapper.style.minHeight = requiredHeight + 'px';
                }

                if (topAdjustment > 0.5) {
                    math.style.position = 'relative';
                    math.style.top = topAdjustment + 'px';
                }

                const adjustedRect = wrapper.getBoundingClientRect();
                debugRows.push({
                    kind: wrapper.classList.contains('katex-display') ? 'display' : 'inline',
                    wrapperHeight: Math.ceil(adjustedRect.height),
                    scrollHeight: Math.ceil(wrapper.scrollHeight),
                    clientHeight: Math.ceil(wrapper.clientHeight),
                    visualHeight: Math.ceil(Math.max(visualBounds.bottom - visualBounds.top, 1)),
                    visualTop: Math.round(visualTop),
                    visualBottom: Math.round(visualBottom),
                    paddingTop: Math.round(paddingTop),
                    paddingBottom: Math.round(paddingBottom),
                    topAdjustment: Math.round(topAdjustment)
                });
            });

            if (window.webkit && window.webkit.messageHandlers.scrollableDebugUpdate) {
                window.webkit.messageHandlers.scrollableDebugUpdate.postMessage(debugRows);
            }
        }

        function visualBoundsForElement(element, includeRoot = true) {
            const rects = [];
            const append = list => {
                Array.from(list).forEach(rect => {
                    if (rect.width > 0.5 && rect.height > 0.5) {
                        rects.push(rect);
                    }
                });
            };

            if (element.classList && element.classList.contains('katex')) {
                appendKatexVisualRects(element, includeRoot, append);
            } else {
                if (includeRoot) {
                    append(element.getClientRects());
                }
                Array.from(element.querySelectorAll('*')).forEach(child => {
                    if (child.closest('.katex-mathml')) { return; }
                    if (child.tagName === 'ANNOTATION') { return; }
                    const style = window.getComputedStyle(child);
                    if (style.display === 'none' || style.visibility === 'hidden') { return; }
                    append(child.getClientRects());
                });
            }

            if (rects.length === 0) { return null; }

            return rects.reduce(
                (bounds, rect) => ({
                    left: Math.min(bounds.left, rect.left),
                    right: Math.max(bounds.right, rect.right),
                    top: Math.min(bounds.top, rect.top),
                    bottom: Math.max(bounds.bottom, rect.bottom)
                }),
                {
                    left: Number.POSITIVE_INFINITY,
                    right: Number.NEGATIVE_INFINITY,
                    top: Number.POSITIVE_INFINITY,
                    bottom: Number.NEGATIVE_INFINITY
                }
            );
        }

        function appendKatexVisualRects(node, includeRoot, appendRects) {
            const isDisplayMath = !!node.closest('.katex-display');

            if (!isDisplayMath && includeRoot) {
                appendRects(node.getClientRects());
                return;
            }

            const html = node.querySelector('.katex-html');
            const bases = html ? Array.from(html.children).filter(child => {
                return child.classList.contains('base') || child.classList.contains('tag');
            }) : [];

            if (bases.length > 0) {
                bases.forEach(child => appendRects(child.getClientRects()));
                return;
            }

            if (includeRoot) {
                appendRects(node.getClientRects());
            }
            Array.from(node.querySelectorAll('*')).forEach(child => {
                if (child.closest('.katex-mathml')) { return; }
                if (child.tagName === 'ANNOTATION') { return; }
                const style = window.getComputedStyle(child);
                if (style.display === 'none' || style.visibility === 'hidden') { return; }
                appendRects(child.getClientRects());
            });
        }

        function reportLayoutMetrics() {
            const el = document.getElementById('content');
            const intrinsicMeasurementWidthLimit = parseFloat(document.body.dataset.intrinsicMeasurementWidthLimit || '0') || 0;
            const bounds = intrinsicMeasurementWidthLimit > 0
                ? measuredVisualContentBoundsAtWidth(el, intrinsicMeasurementWidthLimit)
                : measuredVisualContentBounds(el);
            if (bounds.height > 0 && window.webkit && window.webkit.messageHandlers.heightUpdate) {
                window.webkit.messageHandlers.heightUpdate.postMessage(Math.ceil(bounds.height));
            }
            if (bounds.width > 0 && window.webkit && window.webkit.messageHandlers.widthUpdate) {
                window.webkit.messageHandlers.widthUpdate.postMessage(Math.ceil(bounds.width));
            }
        }

        function reportLineDebug() {
            if (!window.webkit || !window.webkit.messageHandlers.lineDebugUpdate) { return; }
            const el = document.getElementById('content');
            if (!el) { return; }

            const contentRect = el.getBoundingClientRect();
            const widthLimit = Math.max(contentRect.width, 1);
            const range = document.createRange();
            const tokenRects = [];

            function appendToken(text, kind, rect) {
                if (!text || rect.width <= 0.5 || rect.height <= 0.5) { return; }
                tokenRects.push({
                    text: text,
                    kind: kind,
                    top: rect.top,
                    bottom: rect.bottom,
                    midY: rect.top + (rect.height / 2),
                    left: rect.left - contentRect.left,
                    right: rect.right - contentRect.left,
                    width: rect.width,
                    height: rect.height
                });
            }

            function collect(node) {
                if (node.nodeType === Node.TEXT_NODE) {
                    collectTextNode(node);
                    return;
                }

                if (node.nodeType !== Node.ELEMENT_NODE) { return; }

                if (node.classList.contains('inline-code')) {
                    Array.from(node.getClientRects()).forEach(rect => {
                        appendToken(node.textContent || '', 'inlineCode', rect);
                    });
                    return;
                }

                if (node.classList.contains('katex')) {
                    const visualBounds = visualBoundsForElement(node, !node.closest('.katex-display'));
                    if (visualBounds) {
                        appendToken(node.textContent || 'math', 'math', {
                            top: visualBounds.top,
                            bottom: visualBounds.bottom,
                            left: visualBounds.left,
                            right: visualBounds.right,
                            width: visualBounds.right - visualBounds.left,
                            height: visualBounds.bottom - visualBounds.top
                        });
                    }
                    return;
                }

                Array.from(node.childNodes).forEach(collect);
            }

            function collectTextNode(node) {
                const value = node.textContent || '';
                const tokenPattern = /\\S+/g;
                let match;

                while ((match = tokenPattern.exec(value)) !== null) {
                    range.setStart(node, match.index);
                    range.setEnd(node, match.index + match[0].length);
                    Array.from(range.getClientRects()).forEach(rect => {
                        appendToken(match[0], 'text', rect);
                    });
                }
            }

            collect(el);
            range.detach();

            const fontSize = parseFloat(document.body.style.fontSize || '16') || 16;
            const lineMergeTolerance = Math.max(8, fontSize * 0.55);
            const lines = [];

            function belongsToLine(line, token) {
                const overlap = Math.min(line.bottom, token.bottom) - Math.max(line.top, token.top);
                const minHeight = Math.min(line.bottom - line.top, token.bottom - token.top);

                return overlap >= Math.min(minHeight * 0.35, 8)
                    || Math.abs(line.midY - token.midY) <= lineMergeTolerance;
            }

            tokenRects
                .sort((a, b) => (a.top - b.top) || (a.left - b.left))
                .forEach(token => {
                    let line = lines.find(candidate => belongsToLine(candidate, token));
                    if (!line) {
                        line = {
                            top: token.top,
                            bottom: token.bottom,
                            midY: token.midY,
                            left: token.left,
                            right: token.right,
                            tokens: []
                        };
                        lines.push(line);
                    } else {
                        line.top = Math.min(line.top, token.top);
                        line.bottom = Math.max(line.bottom, token.bottom);
                        line.left = Math.min(line.left, token.left);
                        line.right = Math.max(line.right, token.right);
                        line.midY = line.top + ((line.bottom - line.top) / 2);
                    }
                    line.tokens.push(token);
                });

            const payload = lines
                .sort((a, b) => (a.top - b.top) || (a.left - b.left))
                .map((line, index) => ({
                    index: index + 1,
                    widthLimit: Math.ceil(widthLimit),
                    left: Math.round(line.left),
                    top: Math.round(line.top - contentRect.top),
                    width: Math.ceil(Math.max(line.right - line.left, 1)),
                    height: Math.ceil(Math.max(line.bottom - line.top, 1)),
                    right: Math.round(line.right),
                    bottom: Math.round(line.bottom - contentRect.top),
                    tokens: line.tokens
                        .sort((a, b) => a.left - b.left)
                        .map(token => ({
                            text: token.text,
                            kind: token.kind,
                            left: Math.round(token.left),
                            top: Math.round(token.top - contentRect.top),
                            width: Math.ceil(token.width),
                            height: Math.ceil(token.height),
                            right: Math.round(token.right),
                            bottom: Math.round(token.bottom - contentRect.top)
                        }))
                }));

            window.webkit.messageHandlers.lineDebugUpdate.postMessage(payload);
        }

        function measuredVisualContentBoundsAtWidth(source, width) {
            const clone = source.cloneNode(true);
            clone.style.position = 'absolute';
            clone.style.visibility = 'hidden';
            clone.style.pointerEvents = 'none';
            clone.style.left = '-10000px';
            clone.style.top = '0';
            clone.style.width = Math.max(width, 1) + 'px';
            clone.style.maxWidth = 'none';
            clone.style.height = 'auto';
            clone.style.overflow = 'visible';

            document.body.appendChild(clone);
            const bounds = measuredVisualContentBounds(clone);
            clone.remove();

            return bounds;
        }

        function measuredVisualContentBounds(el) {
            const contentRect = el.getBoundingClientRect();
            const maxWidth = Math.max(contentRect.width, 1);
            const rects = [];
            const range = document.createRange();

            function appendRects(list) {
                Array.from(list).forEach(rect => {
                    if (rect.width > 0.5 && rect.height > 0.5) {
                        rects.push(rect);
                    }
                });
            }

            function collect(node) {
                if (node.nodeType === Node.TEXT_NODE) {
                    collectTextTokenRects(node);
                    return;
                }

                if (node.nodeType !== Node.ELEMENT_NODE) { return; }

                if (node.classList.contains('inline-code')) {
                    appendRects(node.getClientRects());
                    return;
                }

                if (node.classList.contains('katex')) {
                    collectKatexVisualRects(node);
                    return;
                }

                Array.from(node.childNodes).forEach(collect);
            }

            function collectKatexVisualRects(node) {
                appendKatexVisualRects(node, !node.closest('.katex-display'), appendRects);
            }

            function collectTextTokenRects(node) {
                const value = node.textContent || '';
                const tokenPattern = /\\S+/g;
                let match;

                while ((match = tokenPattern.exec(value)) !== null) {
                    range.setStart(node, match.index);
                    range.setEnd(node, match.index + match[0].length);
                    appendRects(range.getClientRects());
                }
            }

            collect(el);
            range.detach();

            if (rects.length === 0) {
                return {
                    width: Math.min(maxWidth, Math.max(el.scrollWidth, contentRect.width, 1)),
                    height: Math.max(contentRect.height, el.scrollHeight, 1)
                };
            }

            const fontSize = parseFloat(document.body.style.fontSize || '16') || 16;
            const lineMergeTolerance = Math.max(8, fontSize * 0.55);
            const lines = [];
            let minTop = Number.POSITIVE_INFINITY;
            let maxBottom = Number.NEGATIVE_INFINITY;

            function belongsToLine(line, rect) {
                const rectMidY = rect.top + (rect.height / 2);
                const overlap = Math.min(line.bottom, rect.bottom) - Math.max(line.top, rect.top);
                const minHeight = Math.min(line.bottom - line.top, rect.height);

                return overlap >= Math.min(minHeight * 0.35, 8)
                    || Math.abs(line.midY - rectMidY) <= lineMergeTolerance;
            }

            rects
                .sort((a, b) => (a.top - b.top) || (a.left - b.left))
                .forEach(rect => {
                    const midY = rect.top + (rect.height / 2);
                    let line = lines.find(candidate => belongsToLine(candidate, rect));
                    if (!line) {
                        line = {
                            top: rect.top,
                            bottom: rect.bottom,
                            midY: midY,
                            left: rect.left,
                            right: rect.right
                        };
                        lines.push(line);
                    } else {
                        line.top = Math.min(line.top, rect.top);
                        line.bottom = Math.max(line.bottom, rect.bottom);
                        line.left = Math.min(line.left, rect.left);
                        line.right = Math.max(line.right, rect.right);
                        line.midY = line.top + ((line.bottom - line.top) / 2);
                    }
                    minTop = Math.min(minTop, rect.top);
                    maxBottom = Math.max(maxBottom, rect.bottom);
                });

            const widestLine = lines.reduce((width, line) => {
                return Math.max(width, line.right - line.left);
            }, 1);
            const topOverflow = Math.max(contentRect.top - minTop, 0);
            const visualBottomFromContentTop = Math.max(maxBottom - contentRect.top, 1);
            const visualHeight = Math.max(
                topOverflow + visualBottomFromContentTop,
                el.scrollHeight,
                contentRect.height,
                1
            );
            return {
                width: Math.ceil(widestLine + 2),
                height: Math.ceil(visualHeight)
            };
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
                stabilizeScrollableMathBounds(document.getElementById('content'));
                reportLayoutMetrics();
                reportLineDebug();
                reportOverflow();
            }).observe(document.getElementById('content'));
        }
        installTapBridge(document.getElementById('content'));
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
        guard let regex = try? NSRegularExpression(pattern: "`([^`]+)`") else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange  = Range(match.range,        in: result),
                  let innerRange = Range(match.range(at: 1), in: result) else { continue }
            let inner = String(result[innerRange])
            result.replaceSubrange(
                fullRange,
                with: "<code class=\"inline-code \(renderStyle.inlineCodeClassName) \(inlineCodeLayoutClass(for: inner))\">\(inner)</code>"
            )
        }
        return result
    }

    private func inlineCodeLayoutClass(for value: String) -> String {
        if value.contains(where: \.isWhitespace) {
            return "inline-code--wrapping"
        }

        return value.count > 18 ? "inline-code--breakable-token" : "inline-code--atomic"
    }

    class Coordinator: NSObject, WKScriptMessageHandler, UIGestureRecognizerDelegate {
        @Binding var contentHeight: CGFloat
        @Binding var intrinsicContentWidth: CGFloat
        @Binding var renderedLineDebug: [MixedMathRenderedLineDebug]
        @Binding var scrollableDebug: [MixedMathScrollableDebug]
        var reportsIntrinsicContentWidth: Bool
        private var reportsRenderedLineDebug: Bool
        private var reportsScrollableDebug: Bool
        @Binding var horizontalOverflowState: HorizontalOverflowState
        weak var webView: WKWebView? // WEAK reference to break the retain cycle
        var lastRenderedSignature: String = ""
        var onTap: (() -> Void)?
        private var updateRetryTask: Task<Void, Never>?
        private var lastTapEmissionTime: TimeInterval = 0

        init(
            contentHeight: Binding<CGFloat>,
            intrinsicContentWidth: Binding<CGFloat>,
            renderedLineDebug: Binding<[MixedMathRenderedLineDebug]>,
            scrollableDebug: Binding<[MixedMathScrollableDebug]>,
            reportsIntrinsicContentWidth: Bool,
            reportsRenderedLineDebug: Bool,
            reportsScrollableDebug: Bool,
            horizontalOverflowState: Binding<HorizontalOverflowState>,
            onTap: (() -> Void)?
        ) {
            _contentHeight = contentHeight
            _intrinsicContentWidth = intrinsicContentWidth
            _renderedLineDebug = renderedLineDebug
            _scrollableDebug = scrollableDebug
            self.reportsIntrinsicContentWidth = reportsIntrinsicContentWidth
            self.reportsRenderedLineDebug = reportsRenderedLineDebug
            self.reportsScrollableDebug = reportsScrollableDebug
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

            case "widthUpdate":
                guard reportsIntrinsicContentWidth else { return }
                guard let w = message.body as? Double, w > 0 else { return }
                Task { @MainActor in
                    self.intrinsicContentWidth = CGFloat(w)
                }

            case "lineDebugUpdate":
                let payload = Self.dictionaryArray(from: message.body)
                let lines = payload.compactMap(Self.renderedLineDebug(from:))
                Task { @MainActor in
                    self.renderedLineDebug = lines
                }

            case "scrollableDebugUpdate":
                let payload = Self.dictionaryArray(from: message.body)
                let rows = payload.compactMap(Self.scrollableDebug(from:))
                Task { @MainActor in
                    self.scrollableDebug = rows
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

            case "tapUpdate":
                Task { @MainActor in
                    self.emitTap()
                }

            default:
                return
            }
        }

        nonisolated private static func renderedLineDebug(from payload: [String: Any]) -> MixedMathRenderedLineDebug? {
            let tokensPayload = dictionaryArray(from: payload["tokens"] ?? [])
            let index = payload["index"] as? Int ?? 0
            let widthLimit = cgFloatValue(payload["widthLimit"])
            let left = cgFloatValue(payload["left"])
            let top = cgFloatValue(payload["top"])
            let width = cgFloatValue(payload["width"])
            let height = cgFloatValue(payload["height"])
            let right = cgFloatValue(payload["right"])
            let bottom = cgFloatValue(payload["bottom"])
            let tokens = tokensPayload.compactMap(renderedTokenDebug(from:))
            return MixedMathRenderedLineDebug(
                index: index,
                widthLimit: widthLimit,
                left: left,
                top: top,
                width: width,
                height: height,
                right: right,
                bottom: bottom,
                tokens: tokens
            )
        }

        nonisolated private static func renderedTokenDebug(from payload: [String: Any]) -> MixedMathRenderedTokenDebug? {
            guard let text = payload["text"] as? String,
                  let kind = payload["kind"] as? String
            else { return nil }

            return MixedMathRenderedTokenDebug(
                text: text,
                kind: kind,
                left: cgFloatValue(payload["left"]),
                top: cgFloatValue(payload["top"]),
                width: cgFloatValue(payload["width"]),
                height: cgFloatValue(payload["height"]),
                right: cgFloatValue(payload["right"]),
                bottom: cgFloatValue(payload["bottom"])
            )
        }

        nonisolated private static func dictionaryArray(from body: Any) -> [[String: Any]] {
            if let payload = body as? [[String: Any]] {
                return payload
            }

            if let payload = body as? [NSDictionary] {
                return payload.compactMap { $0 as? [String: Any] }
            }

            if let payload = body as? NSArray {
                return payload.compactMap { item in
                    if let dictionary = item as? [String: Any] {
                        return dictionary
                    }
                    if let dictionary = item as? NSDictionary {
                        return dictionary as? [String: Any]
                    }
                    return nil
                }
            }

            return []
        }

        nonisolated private static func scrollableDebug(from payload: [String: Any]) -> MixedMathScrollableDebug? {
            guard let kind = payload["kind"] as? String else { return nil }

            return MixedMathScrollableDebug(
                kind: kind,
                wrapperHeight: cgFloatValue(payload["wrapperHeight"]),
                scrollHeight: cgFloatValue(payload["scrollHeight"]),
                clientHeight: cgFloatValue(payload["clientHeight"]),
                visualHeight: cgFloatValue(payload["visualHeight"]),
                visualTop: cgFloatValue(payload["visualTop"]),
                visualBottom: cgFloatValue(payload["visualBottom"]),
                paddingTop: cgFloatValue(payload["paddingTop"]),
                paddingBottom: cgFloatValue(payload["paddingBottom"]),
                topAdjustment: cgFloatValue(payload["topAdjustment"])
            )
        }

        nonisolated private static func cgFloatValue(_ value: Any?) -> CGFloat {
            if let value = value as? CGFloat { return value }
            if let value = value as? Double { return CGFloat(value) }
            if let value = value as? Int { return CGFloat(value) }
            if let value = value as? NSNumber { return CGFloat(truncating: value) }
            return 0
        }

        func configureLineDebugHandler(on webView: WKWebView, enabled: Bool) {
            guard reportsRenderedLineDebug != enabled else { return }
            reportsRenderedLineDebug = enabled
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "lineDebugUpdate")

            guard enabled else {
                renderedLineDebug = []
                return
            }

            let scriptHandlerWrapper = WeakScriptMessageHandler(delegate: self)
            webView.configuration.userContentController.add(scriptHandlerWrapper, name: "lineDebugUpdate")
        }

        func configureScrollableDebugHandler(on webView: WKWebView, enabled: Bool) {
            guard reportsScrollableDebug != enabled else { return }
            reportsScrollableDebug = enabled
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "scrollableDebugUpdate")

            guard enabled else {
                scrollableDebug = []
                return
            }

            let scriptHandlerWrapper = WeakScriptMessageHandler(delegate: self)
            webView.configuration.userContentController.add(scriptHandlerWrapper, name: "scrollableDebugUpdate")
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

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            Task { @MainActor in
                self.emitTap()
            }
        }

        @MainActor
        private func emitTap() {
            let now = Date().timeIntervalSinceReferenceDate
            guard now - lastTapEmissionTime > 0.28 else { return }
            lastTapEmissionTime = now
            onTap?()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            guard shouldHandOffHorizontalPanToParent(pan) else { return true }
            return false
        }

        private func shouldHandOffHorizontalPanToParent(_ pan: UIPanGestureRecognizer) -> Bool {
            guard horizontalOverflowState.hasOverflow else { return true }

            let view = pan.view ?? webView
            let translation = pan.translation(in: view)
            let velocity = pan.velocity(in: view)
            let horizontal = max(abs(translation.x), abs(velocity.x))
            let vertical = max(abs(translation.y), abs(velocity.y))

            guard horizontal > vertical * 1.15 else { return false }

            let direction = abs(translation.x) > 0 ? translation.x : velocity.x
            guard direction != 0 else { return false }

            if direction > 0 {
                return !horizontalOverflowState.canScrollLeft
            }

            return !horizontalOverflowState.canScrollRight
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
