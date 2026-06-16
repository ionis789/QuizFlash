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

struct MixedMathGestureDebugSnapshot: Equatable {
    let timestamp: Date
    let decision: String
    let reason: String
    let direction: String
    let location: CGPoint
    let horizontalMagnitude: CGFloat
    let verticalMagnitude: CGFloat
    let canScrollLeft: Bool
    let canScrollRight: Bool
    let regionCount: Int
}

struct MixedMathRenderStatusDebug: Equatable {
    let stage: String
    let contentLength: Int
    let childCount: Int
    let textLength: Int
    let bodyWidth: CGFloat
    let bodyHeight: CGFloat
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let contentScrollWidth: CGFloat
    let contentScrollHeight: CGFloat
    let inlineCodeCount: Int
    let mathCount: Int
    let displayMathCount: Int
    let inlineCodeScrollCount: Int
    let inlineMathScrollCount: Int
    let layoutMetricReportCount: Int
    let lineDebugReportCount: Int
}

struct MixedMathNativeRenderDebug: Equatable {
    var webViewID = "unassigned"
    var checkoutSource = "unknown"
    var checkoutCount = 0
    var windowAttached = false
    var isHidden = false
    var alpha: CGFloat = 0
    var layerOpacity: Float = 0
    var effectiveOpacity: Float = 0
    var frame: CGRect = .zero
    var bounds: CGRect = .zero
    var intersectsWindow = false
    var stage = "idle"
    var renderToken = "none"
    var readinessChecks = 0
    var didFinishCount = 0
    var javaScriptExecutionCount = 0
    var heightMessageCount = 0
    var widthMessageCount = 0
    var renderStatusMessageCount = 0
    var lastHeight: CGFloat = 0
    var lastWidth: CGFloat = 0
    var lastError = "none"
    var events: [String] = []
}

extension Notification.Name {
    static let quizFlashMixedMathVisibilityProbe = Notification.Name(
        "QuizFlash.MixedMathVisibilityProbe"
    )
}

private var quizFlashHorizontalOverflowAssociationKey: UInt8 = 0
private var quizFlashScrollableMathInteractionRegionsAssociationKey: UInt8 = 0

struct ScrollableMathInteractionRegion: Equatable {
    let rect: CGRect
    let canScrollLeft: Bool
    let canScrollRight: Bool
}

private final class MathWKWebView: WKWebView {
    var allowsFullQuizFlashInteraction = true
    var scrollableInteractionRegions: [ScrollableMathInteractionRegion] = []
    let quizFlashDebugID = String(UUID().uuidString.prefix(8))
    var quizFlashCheckoutSource = "created"
    var quizFlashCheckoutCount = 0

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        guard !allowsFullQuizFlashInteraction else { return true }

        return scrollableInteractionRegion(containing: point) != nil
    }

    func scrollableInteractionRegion(containing point: CGPoint) -> ScrollableMathInteractionRegion? {
        scrollableInteractionRegions.first { region in
            region.rect
                .insetBy(dx: -UIConstants.Spacing.small, dy: -UIConstants.Spacing.small)
                .contains(point)
        }
    }
}

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

    var quizflashScrollableMathInteractionRegions: [ScrollableMathInteractionRegion] {
        get {
            objc_getAssociatedObject(
                self,
                &quizFlashScrollableMathInteractionRegionsAssociationKey
            ) as? [ScrollableMathInteractionRegion] ?? []
        }
        set {
            objc_setAssociatedObject(
                self,
                &quizFlashScrollableMathInteractionRegionsAssociationKey,
                newValue,
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
    var fontFamily: FontFamily = .system
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
    var onGestureDebugChange: ((MixedMathGestureDebugSnapshot) -> Void)? = nil
    var onRenderStatusDebugChange: ((MixedMathRenderStatusDebug) -> Void)? = nil
    var onNativeRenderDebugChange: ((MixedMathNativeRenderDebug) -> Void)? = nil
    var showsRenderDebugBounds: Bool = false
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var webHeight: CGFloat = 50
    @State private var webIntrinsicWidth: CGFloat = 0
    @State private var horizontalOverflowState = HorizontalOverflowState()
    @State private var renderedLineDebug: [MixedMathRenderedLineDebug] = []
    @State private var scrollableDebug: [MixedMathScrollableDebug] = []
    @State private var gestureDebug: MixedMathGestureDebugSnapshot?
    @State private var renderStatusDebug: MixedMathRenderStatusDebug?
    @State private var nativeRenderDebug = MixedMathNativeRenderDebug()

    var body: some View {
        let clean = MathTextSanitizer.heal(text)
        let signature = renderSignature(for: clean)
        let usesWebRendering = intrinsicWidthLimit != nil
            || MathTextSanitizer.containsMath(clean)
            || MathTextSanitizer.containsInlineCode(clean)
        let canSupportReadOnlyOverflowScrolling = (
            !isInteractive
            && allowsReadOnlyOverflowScrolling
            && (MathTextSanitizer.containsMath(clean) || MathTextSanitizer.containsInlineCode(clean))
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
        let reportsRenderStatusDebug = onRenderStatusDebugChange != nil
        let reportsNativeRenderDebug = onNativeRenderDebugChange != nil

        if usesWebRendering {
            MathWebView(
                text: clean,
                fontSize: fontSize,
                fontFamily: fontFamily,
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
                gestureDebug: $gestureDebug,
                renderStatusDebug: $renderStatusDebug,
                nativeRenderDebug: reportsNativeRenderDebug
                    ? $nativeRenderDebug
                    : .constant(MixedMathNativeRenderDebug()),
                reportsIntrinsicContentWidth: intrinsicWidthLimit != nil,
                reportsRenderedLineDebug: reportsRenderedLineDebug,
                reportsScrollableDebug: reportsScrollableDebug,
                reportsRenderStatusDebug: reportsRenderStatusDebug,
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
            .onAppear {
                reportIntrinsicContentSize()
            }
            .onChange(of: renderedLineDebug) { _, newValue in
                onRenderedLineDebugChange?(newValue)
            }
            .onChange(of: scrollableDebug) { _, newValue in
                onScrollableDebugChange?(newValue)
            }
            .onChange(of: gestureDebug) { _, newValue in
                guard let newValue else { return }
                onGestureDebugChange?(newValue)
            }
            .onChange(of: renderStatusDebug) { _, newValue in
                guard let newValue else { return }
                onRenderStatusDebugChange?(newValue)
            }
            .onChange(of: nativeRenderDebug) { _, newValue in
                onNativeRenderDebugChange?(newValue)
            }
            .overlay {
                if shouldShowHorizontalOverflowHint {
                    HorizontalOverflowIndicator(
                        canScrollLeft: horizontalOverflowState.canScrollLeft,
                        canScrollRight: horizontalOverflowState.canScrollRight,
                        verticalCenterY: horizontalOverflowState.indicatorCenterY,
                        regions: horizontalOverflowState.scrollableInteractionRegions
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
        let baseFont = fontFamily.uiFont(size: fontSize, weight: weight)

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
            fontFamily.rawValue,
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
        let base = fontFamily.font(size: fontSize)
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

    // Maximum number of idle WebViews kept alive between uses. Rich preview
    // cards can mount many math leaves at once; keeping the pool large enough
    // avoids recreating WKWebViews during repeated preview open/close cycles.
    private static let maxPoolSize = 48

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
        let webView: WKWebView
        if let pooledWebView = pool.popLast() {
            webView = pooledWebView
            (webView as? MathWKWebView)?.quizFlashCheckoutSource = "pool"
        } else {
            webView = create()
            (webView as? MathWKWebView)?.quizFlashCheckoutSource = "new"
        }
        (webView as? MathWKWebView)?.quizFlashCheckoutCount += 1
        return webView
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

        let webView = MathWKWebView(frame: .zero, configuration: config)
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
    let fontFamily: FontFamily
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
    @Binding var gestureDebug: MixedMathGestureDebugSnapshot?
    @Binding var renderStatusDebug: MixedMathRenderStatusDebug?
    @Binding var nativeRenderDebug: MixedMathNativeRenderDebug
    let reportsIntrinsicContentWidth: Bool
    let reportsRenderedLineDebug: Bool
    let reportsScrollableDebug: Bool
    let reportsRenderStatusDebug: Bool
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
            gestureDebug: $gestureDebug,
            renderStatusDebug: $renderStatusDebug,
            nativeRenderDebug: $nativeRenderDebug,
            reportsIntrinsicContentWidth: reportsIntrinsicContentWidth,
            reportsRenderedLineDebug: reportsRenderedLineDebug,
            reportsScrollableDebug: reportsScrollableDebug,
            reportsRenderStatusDebug: reportsRenderStatusDebug,
            horizontalOverflowState: $horizontalOverflowState,
            onTap: onTap
        )
    }

    // Called automatically by SwiftUI when the view is removed from the hierarchy.
    // Breaks the retain cycle and returns the WKWebView to the shared pool.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 1. Unlink coordinator to break any lingering weak/unowned chains
        coordinator.cancelPendingUpdate()
        coordinator.invalidateRender()
        coordinator.webView = nil
        uiView.navigationDelegate = nil

        // 2. Remove the script message handler to break the JS context retain cycle
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "heightUpdate")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "widthUpdate")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "lineDebugUpdate")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "scrollableDebugUpdate")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "renderStatusUpdate")
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "renderStatusUpdate")
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
        if reportsRenderStatusDebug {
            webView.configuration.userContentController.add(scriptHandlerWrapper, name: "renderStatusUpdate")
        }
        webView.configuration.userContentController.add(scriptHandlerWrapper, name: "overflowUpdate")
        webView.configuration.userContentController.add(scriptHandlerWrapper, name: "tapUpdate")

        context.coordinator.webView = webView
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(webView: webView)
        context.coordinator.lastRenderedSignature = renderSignature
        context.coordinator.onTap = onTap
        webView.quizflashHasHorizontalOverflow = false
        webView.quizflashScrollableMathInteractionRegions = []

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
        context.coordinator.configureRenderStatusDebugHandler(on: webView, enabled: reportsRenderStatusDebug)
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
        if let mathWebView = webView as? MathWKWebView {
            mathWebView.allowsFullQuizFlashInteraction = isInteractive
            mathWebView.scrollableInteractionRegions = isInteractive
                ? []
                : horizontalOverflowState.scrollableInteractionRegions
        }
        webView.quizflashScrollableMathInteractionRegions = isInteractive
            ? []
            : horizontalOverflowState.scrollableInteractionRegions
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
        let cssFontFamily = fontFamily.cssFontFamily
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
        let renderToken = context.coordinator.beginRender()
        let js = "updateMathContent('\(b64)', '\(cssColor)', \(fontSize), '\(cssAlign)', '\(weight)', '\(fontStyle)', '\(cssFontFamily)', \(allowDisplayMathOverflowScrolling), \(measurementWidth), \(debugBounds), '\(renderToken)');"
        context.coordinator.applyUpdate(js: js, renderToken: renderToken)
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
                -webkit-touch-callout: none;
                -webkit-user-select: none;
                user-select: none;
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
            #content::-webkit-scrollbar { display: none; }
            .katex-display {
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
                display: block;
                width: 100%;
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
            .katex-inline-scroll::-webkit-scrollbar { display: none; }
            .katex-inline-scroll .katex {
                display: inline-block;
                min-width: max-content;
                max-width: none;
                white-space: nowrap;
            }
            .katex-inline-scroll .katex > .katex-html,
            .katex-display > .katex > .katex-html {
                display: inline-block;
                min-width: max-content;
                width: max-content;
                white-space: nowrap;
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
            .inline-code-scroll {
                display: block;
                width: 100%;
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
            .inline-code-scroll::-webkit-scrollbar { display: none; }
            .inline-code-scroll code.inline-code {
                display: inline-block;
                min-width: max-content;
                max-width: none;
                white-space: pre;
            }
            .nonbreaking-hyphen-token {
                white-space: nowrap;
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
                font-family: inherit !important;
            }
            code.inline-code {
                font-family: ui-monospace, 'SF Mono', Menlo, monospace;
                font-size: 0.88em;
                display: inline-block;
                max-width: none;
                line-height: 1.35;
                overflow-wrap: normal;
                word-break: normal;
                white-space: pre;
                vertical-align: middle;
            }
            code.inline-code--standard {
                background: rgba(120, 120, 120, 0.15);
                color: inherit;
                border: 1px solid rgba(120, 120, 120, 0.2);
                border-radius: 6px;
                padding: 1px 6px 2px;
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
                max-width: none;
                overflow-wrap: normal;
                word-break: normal;
                white-space: pre;
            }
            code.inline-code--breakable-token {
                max-width: none;
                overflow-wrap: normal;
                word-break: normal;
                white-space: pre;
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
        const renderDebugState = {
            layoutMetricReportCount: 0,
            lineDebugReportCount: 0
        };
        let tapMovementLimit = 10;
        let tapDurationLimit = 450;
        let syntheticClickSuppressionWindow = 650;
        let tapBridgeState = {
            startPoint: null,
            startTime: 0,
            cancelled: false,
            lastTouchTapTime: 0,
            isInstalled: false
        };

        function updateMathContent(b64, color, fontSize, align, weight, fontStyle, fontFamily, allowDisplayMathOverflowScrolling, intrinsicMeasurementWidthLimit, showsRenderDebugBounds, renderToken) {
            document.body.style.color = color;
            document.body.style.fontSize = fontSize + 'px';
            document.body.style.textAlign = align;
            document.body.style.fontWeight = weight;
            document.body.style.fontStyle = fontStyle;
            document.body.style.fontFamily = fontFamily;
            document.body.dataset.allowDisplayMathOverflowScrolling = allowDisplayMathOverflowScrolling ? '1' : '0';
            document.body.dataset.intrinsicMeasurementWidthLimit = intrinsicMeasurementWidthLimit > 0 ? intrinsicMeasurementWidthLimit : '';
            document.body.dataset.renderDebugBounds = showsRenderDebugBounds ? '1' : '0';
            document.body.dataset.renderToken = renderToken || '';

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
            classifyInlineMathFlow(contentDiv);
            bindNonBreakingHyphenatedWords(contentDiv);
            clearTimeout(updateTimeout);
            reportRenderStatus('post-dom');
            schedulePostRenderLayoutPass(contentDiv, renderToken);
        }

        function currentRenderToken() {
            return document.body.dataset.renderToken || '';
        }

        function isActiveRender(renderToken) {
            return !!renderToken && renderToken === currentRenderToken();
        }

        function payloadWithRenderToken(payload) {
            const token = currentRenderToken();
            if (payload && typeof payload === 'object' && !Array.isArray(payload)) {
                return Object.assign({ renderToken: token }, payload);
            }
            return { renderToken: token, value: payload };
        }

        function installTapBridge(contentDiv) {
            if (!contentDiv || tapBridgeState.isInstalled) { return; }
            tapBridgeState.isInstalled = true;

            const isContentTouch = event => {
                const target = event.target;
                return !!target && (target === contentDiv || contentDiv.contains(target));
            };

            document.addEventListener('touchstart', event => {
                if (!isContentTouch(event)) { return; }
                const touch = event.changedTouches && event.changedTouches[0];
                if (!touch) { return; }
                tapBridgeState.startPoint = { x: touch.clientX, y: touch.clientY };
                tapBridgeState.startTime = Date.now();
                tapBridgeState.cancelled = false;
            }, { passive: true, capture: true });

            document.addEventListener('touchmove', event => {
                if (!tapBridgeState.startPoint) { return; }
                const touch = event.changedTouches && event.changedTouches[0];
                if (!touch) { return; }

                const dx = touch.clientX - tapBridgeState.startPoint.x;
                const dy = touch.clientY - tapBridgeState.startPoint.y;
                if (Math.hypot(dx, dy) > tapMovementLimit) {
                    tapBridgeState.cancelled = true;
                }
            }, { passive: true, capture: true });

            document.addEventListener('touchend', event => {
                if (!isContentTouch(event)) {
                    tapBridgeState.startPoint = null;
                    tapBridgeState.cancelled = false;
                    return;
                }
                const touch = event.changedTouches && event.changedTouches[0];
                if (!touch || !tapBridgeState.startPoint) {
                    tapBridgeState.startPoint = null;
                    tapBridgeState.cancelled = false;
                    return;
                }

                const dx = touch.clientX - tapBridgeState.startPoint.x;
                const dy = touch.clientY - tapBridgeState.startPoint.y;
                const distance = Math.hypot(dx, dy);
                const duration = Date.now() - tapBridgeState.startTime;
                const wasCancelled = tapBridgeState.cancelled;
                tapBridgeState.startPoint = null;
                tapBridgeState.cancelled = false;

                if (wasCancelled || distance > tapMovementLimit || duration > tapDurationLimit) { return; }
                tapBridgeState.lastTouchTapTime = Date.now();
                postTapUpdate();
            }, { passive: true, capture: true });

            document.addEventListener('touchcancel', () => {
                tapBridgeState.startPoint = null;
                tapBridgeState.cancelled = false;
            }, { passive: true, capture: true });

            document.addEventListener('click', event => {
                if (!isContentTouch(event)) { return; }
                if (Date.now() - tapBridgeState.lastTouchTapTime < syntheticClickSuppressionWindow) { return; }
                postTapUpdate();
            }, { capture: true });
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

        function schedulePostRenderLayoutPass(contentDiv, renderToken) {
            const run = () => {
                if (!isActiveRender(renderToken)) { return; }
                reportRenderStatus('pre-layout');
                prepareOverflowContainers();
                stabilizeScrollableMathBounds(contentDiv);
                reportLayoutMetrics();
                reportRenderStatus('post-metrics');
                reportLineDebug();
                reportRenderStatus('post-line-debug');
                reportOverflow();
            };

            requestAnimationFrame(() => {
                requestAnimationFrame(run);
            });

            updateTimeout = setTimeout(run, 80);
        }

        function prepareOverflowContainers() {
            const contentDiv = document.getElementById('content');
            unwrapForcedInlineCodeLineBreaks(contentDiv);
            unwrapInlineBoundaryContainers(contentDiv);
            unwrapInlineOverflowContainers(contentDiv);
            unwrapInlineCodeOverflowContainers(contentDiv);
            bindInlineTrailingPunctuation(contentDiv);
            stabilizeInlineCodeLineBreaks(contentDiv);

            const overflowTargets = Array.from(contentDiv.querySelectorAll('.katex-display'));

            const allowOverflow = document.body.dataset.allowDisplayMathOverflowScrolling === '1';
            if (allowOverflow) {
                const contentRect = contentDiv.getBoundingClientRect();
                const maxInlineWidth = contentRect.width;
                const inlineKatex = Array.from(contentDiv.querySelectorAll('.katex')).filter(node => !node.closest('.katex-display'));

                inlineKatex.forEach(node => {
                    if (
                        !inlineMathNeedsOverflowContainer(node, contentRect, maxInlineWidth)
                        && !inlineMathNeedsOwnLine(node, contentDiv, maxInlineWidth)
                    ) { return; }

                    const scrollSubject = node.closest('.katex-inline-boundary') || node;
                    const wrapper = document.createElement('span');
                    wrapper.className = 'katex-inline-scroll';
                    scrollSubject.parentNode.insertBefore(wrapper, scrollSubject);
                    wrapper.appendChild(scrollSubject);
                    overflowTargets.push(wrapper);
                });

                const inlineCode = Array.from(contentDiv.querySelectorAll('code.inline-code'));
                inlineCode.forEach(node => {
                    if (!inlineCodeNeedsOverflowContainer(node, contentRect, maxInlineWidth)) { return; }

                    const wrapper = document.createElement('span');
                    wrapper.className = 'inline-code-scroll';
                    node.parentNode.insertBefore(wrapper, node);
                    wrapper.appendChild(node);
                    overflowTargets.push(wrapper);
                });
            }

            overflowTargets.forEach(block => {
                bindScrollableMathEdgeGuard(block);
                block.onscroll = reportOverflow;
            });
        }

        function bindScrollableMathEdgeGuard(block) {
            if (!block || block.dataset.qfEdgeGuardBound === '1') { return; }
            block.dataset.qfEdgeGuardBound = '1';

            let startX = 0;
            let startY = 0;
            let tracking = false;

            block.addEventListener('touchstart', event => {
                if (event.touches.length !== 1) {
                    tracking = false;
                    return;
                }

                const touch = event.touches[0];
                startX = touch.clientX;
                startY = touch.clientY;
                tracking = true;
            }, { passive: true });

            block.addEventListener('touchmove', event => {
                if (!tracking || event.touches.length !== 1) { return; }

                const touch = event.touches[0];
                const dx = touch.clientX - startX;
                const dy = touch.clientY - startY;
                const horizontal = Math.abs(dx);
                const vertical = Math.abs(dy);
                if (horizontal <= vertical * 1.15) { return; }

                const maxScrollLeft = Math.max(0, block.scrollWidth - block.clientWidth);
                const atLeftEdge = block.scrollLeft <= 1;
                const atRightEdge = block.scrollLeft >= maxScrollLeft - 1;
                const wantsPastLeftEdge = dx > 0 && atLeftEdge;
                const wantsPastRightEdge = dx < 0 && atRightEdge;

                if ((wantsPastLeftEdge || wantsPastRightEdge) && event.cancelable) {
                    event.preventDefault();
                    block.scrollLeft = wantsPastLeftEdge ? 0 : maxScrollLeft;
                }
            }, { passive: false });

            const reset = () => {
                tracking = false;
            };
            block.addEventListener('touchend', reset, { passive: true });
            block.addEventListener('touchcancel', reset, { passive: true });
        }

        function inlineMathNeedsOverflowContainer(node, contentRect, maxInlineWidth) {
            const rect = visualBoundsForElement(node) || node.getBoundingClientRect();
            const tolerance = 1;
            const visualWidth = rect.right - rect.left;
            const intrinsicWidth = intrinsicKatexVisualWidth(node);

            if (intrinsicWidth > maxInlineWidth + tolerance) { return true; }
            if (visualWidth > maxInlineWidth + tolerance) { return true; }
            if (rect.left < contentRect.left - tolerance) { return true; }
            if (rect.right > contentRect.right + tolerance) { return true; }

            return false;
        }

        function inlineMathNeedsOwnLine(node, contentDiv, maxInlineWidth) {
            const mathBounds = visualBoundsForElement(node) || node.getBoundingClientRect();
            const intrinsicWidth = intrinsicKatexVisualWidth(node);
            if (!mathBounds || intrinsicWidth <= 0 || maxInlineWidth <= 0) { return false; }

            const sameLineTextWidth = nonMathTextWidthOnSameLine(contentDiv, mathBounds);
            if (sameLineTextWidth <= 0) { return false; }

            return intrinsicWidth + sameLineTextWidth > maxInlineWidth + 1;
        }

        function nonMathTextWidthOnSameLine(contentDiv, lineBounds) {
            if (!contentDiv || !lineBounds) { return 0; }

            const range = document.createRange();
            let width = 0;
            const walker = document.createTreeWalker(
                contentDiv,
                NodeFilter.SHOW_TEXT,
                {
                    acceptNode(node) {
                        const parent = node.parentElement;
                        if (!parent || parent.closest('code, .katex, script, style')) {
                            return NodeFilter.FILTER_REJECT;
                        }

                        return (node.textContent || '').trim().length > 0
                            ? NodeFilter.FILTER_ACCEPT
                            : NodeFilter.FILTER_REJECT;
                    }
                }
            );

            let node;
            while ((node = walker.nextNode())) {
                const value = node.textContent || '';
                const tokenPattern = /\\S+/g;
                let match;

                while ((match = tokenPattern.exec(value)) !== null) {
                    range.setStart(node, match.index);
                    range.setEnd(node, match.index + match[0].length);

                    Array.from(range.getClientRects()).forEach(rect => {
                        if (rect.width <= 0.5 || rect.height <= 0.5) { return; }
                        const overlap = Math.min(rect.bottom, lineBounds.bottom) - Math.max(rect.top, lineBounds.top);
                        const requiredOverlap = Math.min(rect.height, lineBounds.bottom - lineBounds.top) * 0.45;
                        if (overlap >= requiredOverlap) {
                            width += rect.width;
                        }
                    });
                }
            }

            range.detach();
            return width;
        }

        function intrinsicKatexVisualWidth(node) {
            if (!node) { return 0; }

            const html = node.querySelector('.katex-html');
            const candidates = html
                ? [html, ...Array.from(html.children).filter(child => {
                    return child.classList.contains('base') || child.classList.contains('tag');
                })]
                : [node];

            return candidates.reduce((width, element) => {
                const rectWidth = Array.from(element.getClientRects()).reduce((maxWidth, rect) => {
                    return Math.max(maxWidth, rect.width || 0);
                }, 0);
                const scrollWidth = element.scrollWidth || 0;
                const offsetWidth = element.offsetWidth || 0;
                return Math.max(width, rectWidth, scrollWidth, offsetWidth);
            }, 0);
        }

        function inlineCodeNeedsOverflowContainer(node, contentRect, maxInlineWidth) {
            const rect = visualBoundsForElement(node) || node.getBoundingClientRect();
            const tolerance = 1;
            const visualWidth = rect.right - rect.left;
            const intrinsicWidth = intrinsicElementVisualWidth(node);

            if (intrinsicWidth > maxInlineWidth + tolerance) { return true; }
            if (visualWidth > maxInlineWidth + tolerance) { return true; }

            return false;
        }

        function stabilizeInlineCodeLineBreaks(contentDiv) {
            if (!contentDiv) { return; }

            const tolerance = 1;
            const maxAttempts = 3;
            for (let attempt = 0; attempt < maxAttempts; attempt++) {
                const contentRect = contentDiv.getBoundingClientRect();
                const maxInlineWidth = Math.max(contentRect.width, 1);
                let changed = false;

                const inlineCode = Array.from(contentDiv.querySelectorAll('code.inline-code'))
                    .filter(node => !node.closest('.inline-code-scroll'));

                inlineCode.forEach(node => {
                    const rects = Array.from(node.getClientRects())
                        .filter(rect => rect.width > 0.5 && rect.height > 0.5);
                    if (rects.length === 0) { return; }

                    const rect = rects[rects.length - 1];
                    const intrinsicWidth = intrinsicElementVisualWidth(node);
                    if (intrinsicWidth > maxInlineWidth + tolerance) { return; }
                    if (rect.right <= contentRect.right + tolerance) { return; }

                    const previous = node.previousSibling;
                    if (
                        previous
                        && previous.nodeType === Node.ELEMENT_NODE
                        && previous.dataset
                        && previous.dataset.qfInlineCodeBreak === '1'
                    ) { return; }

                    const forcedBreak = document.createElement('br');
                    forcedBreak.dataset.qfInlineCodeBreak = '1';
                    node.parentNode.insertBefore(forcedBreak, node);
                    changed = true;
                });

                if (!changed) { break; }
            }
        }

        function intrinsicElementVisualWidth(node) {
            if (!node) { return 0; }

            const rectWidth = Array.from(node.getClientRects()).reduce((maxWidth, rect) => {
                return Math.max(maxWidth, rect.width || 0);
            }, 0);
            const scrollWidth = node.scrollWidth || 0;
            const offsetWidth = node.offsetWidth || 0;
            return Math.max(rectWidth, scrollWidth, offsetWidth);
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

        function unwrapInlineCodeOverflowContainers(contentDiv) {
            Array.from(contentDiv.querySelectorAll('.inline-code-scroll')).forEach(wrapper => {
                const parent = wrapper.parentNode;
                while (wrapper.firstChild) {
                    parent.insertBefore(wrapper.firstChild, wrapper);
                }
                parent.removeChild(wrapper);
            });
        }

        function unwrapForcedInlineCodeLineBreaks(contentDiv) {
            if (!contentDiv) { return; }

            Array.from(contentDiv.querySelectorAll('br[data-qf-inline-code-break="1"]')).forEach(node => {
                node.parentNode.removeChild(node);
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

            Array.from(contentDiv.querySelectorAll('.katex-display, .katex-inline-scroll, .inline-code-scroll')).forEach(wrapper => {
                const math = wrapper.querySelector('.katex');
                const code = wrapper.querySelector('code.inline-code');
                const subject = math || code;
                if (!subject) { return; }

                wrapper.style.height = '';
                wrapper.style.minHeight = '';
                subject.style.position = '';
                subject.style.top = '';

                const wrapperRect = wrapper.getBoundingClientRect();
                const visualBounds = visualBoundsForElement(subject);
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
                    subject.style.position = 'relative';
                    subject.style.top = topAdjustment + 'px';
                }

                const adjustedRect = wrapper.getBoundingClientRect();
                debugRows.push({
                    kind: wrapper.classList.contains('katex-display')
                        ? 'display'
                        : (wrapper.classList.contains('inline-code-scroll') ? 'code' : 'inline'),
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
                window.webkit.messageHandlers.scrollableDebugUpdate.postMessage(payloadWithRenderToken(debugRows));
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
            const html = node.querySelector('.katex-html');
            const bases = html ? Array.from(html.children).filter(child => {
                return child.classList.contains('base') || child.classList.contains('tag');
            }) : [];

            if (bases.length > 0) {
                bases.forEach(child => appendRects(child.getClientRects()));
                return;
            }

            if (html) {
                appendRects(html.getClientRects());
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
            if (!el) { return; }
            renderDebugState.layoutMetricReportCount += 1;
            const intrinsicMeasurementWidthLimit = parseFloat(document.body.dataset.intrinsicMeasurementWidthLimit || '0') || 0;
            let bounds = intrinsicMeasurementWidthLimit > 0
                ? measuredVisualContentBoundsAtWidth(el, intrinsicMeasurementWidthLimit)
                : measuredVisualContentBounds(el);
            if (!bounds) {
                const rect = el.getBoundingClientRect();
                const width = Math.max(rect.width, el.scrollWidth, intrinsicMeasurementWidthLimit, 1);
                const height = Math.max(rect.height, el.scrollHeight, 1);
                bounds = {
                    left: rect.left,
                    right: rect.left + width,
                    top: rect.top,
                    bottom: rect.top + height,
                    width: width,
                    height: height
                };
            }
            if (bounds.height > 0 && window.webkit && window.webkit.messageHandlers.heightUpdate) {
                window.webkit.messageHandlers.heightUpdate.postMessage(payloadWithRenderToken(Math.ceil(bounds.height)));
            }
            if (bounds.width > 0 && window.webkit && window.webkit.messageHandlers.widthUpdate) {
                window.webkit.messageHandlers.widthUpdate.postMessage(payloadWithRenderToken(Math.ceil(bounds.width)));
            }
        }

        function reportLineDebug() {
            if (!window.webkit || !window.webkit.messageHandlers.lineDebugUpdate) { return; }
            renderDebugState.lineDebugReportCount += 1;
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

            window.webkit.messageHandlers.lineDebugUpdate.postMessage(payloadWithRenderToken(payload));
        }

        function reportRenderStatus(stage) {
            if (!window.webkit || !window.webkit.messageHandlers.renderStatusUpdate) { return; }
            const el = document.getElementById('content');
            if (!el) { return; }

            const bodyRect = document.body.getBoundingClientRect();
            const contentRect = el.getBoundingClientRect();
            window.webkit.messageHandlers.renderStatusUpdate.postMessage(payloadWithRenderToken({
                stage: stage || 'unknown',
                contentLength: (el.innerHTML || '').length,
                childCount: el.childElementCount || 0,
                textLength: (el.textContent || '').length,
                bodyWidth: Math.ceil(bodyRect.width || 0),
                bodyHeight: Math.ceil(bodyRect.height || 0),
                contentWidth: Math.ceil(contentRect.width || 0),
                contentHeight: Math.ceil(contentRect.height || 0),
                contentScrollWidth: Math.ceil(el.scrollWidth || 0),
                contentScrollHeight: Math.ceil(el.scrollHeight || 0),
                inlineCodeCount: el.querySelectorAll('code.inline-code').length,
                mathCount: el.querySelectorAll('.katex').length,
                displayMathCount: el.querySelectorAll('.katex-display').length,
                inlineCodeScrollCount: el.querySelectorAll('.inline-code-scroll').length,
                inlineMathScrollCount: el.querySelectorAll('.katex-inline-scroll').length,
                layoutMetricReportCount: renderDebugState.layoutMetricReportCount,
                lineDebugReportCount: renderDebugState.lineDebugReportCount
            }));
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
                window.webkit.messageHandlers.overflowUpdate.postMessage(payloadWithRenderToken({
                    canScrollLeft: false,
                    canScrollRight: false,
                    indicatorCenterY: null,
                    interactionRects: []
                }));
                return;
            }

            const contentDiv = document.getElementById('content');
            const contentRect = contentDiv ? contentDiv.getBoundingClientRect() : document.body.getBoundingClientRect();
            const displays = Array.from(document.querySelectorAll('.katex-display, .katex-inline-scroll, .inline-code-scroll'));
            const overflowState = displays.reduce(
                (state, block) => {
                    const hasOverflow = (block.scrollWidth - block.clientWidth) > 1;
                    if (!hasOverflow) { return state; }

                    const maxScrollLeft = Math.max(0, block.scrollWidth - block.clientWidth);
                    const canScrollBlockLeft = block.scrollLeft > 1;
                    const canScrollBlockRight = block.scrollLeft < maxScrollLeft - 1;
                    const blockRect = block.getBoundingClientRect();
                    if (state.indicatorCenterY === null && (canScrollBlockLeft || canScrollBlockRight)) {
                        state.indicatorCenterY = (blockRect.top - contentRect.top) + (blockRect.height / 2);
                    }
                    state.interactionRects.push({
                        left: blockRect.left - contentRect.left,
                        top: blockRect.top - contentRect.top,
                        width: blockRect.width,
                        height: blockRect.height,
                        canScrollLeft: canScrollBlockLeft,
                        canScrollRight: canScrollBlockRight
                    });
                    if (canScrollBlockLeft) {
                        state.canScrollLeft = true;
                    }
                    if (canScrollBlockRight) {
                        state.canScrollRight = true;
                    }
                    return state;
                },
                { canScrollLeft: false, canScrollRight: false, indicatorCenterY: null, interactionRects: [] }
            );
            window.webkit.messageHandlers.overflowUpdate.postMessage(payloadWithRenderToken(overflowState));
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

    class Coordinator: NSObject, WKScriptMessageHandler, UIGestureRecognizerDelegate, WKNavigationDelegate {
        @Binding var contentHeight: CGFloat
        @Binding var intrinsicContentWidth: CGFloat
        @Binding var renderedLineDebug: [MixedMathRenderedLineDebug]
        @Binding var scrollableDebug: [MixedMathScrollableDebug]
        @Binding var gestureDebug: MixedMathGestureDebugSnapshot?
        @Binding var renderStatusDebug: MixedMathRenderStatusDebug?
        @Binding var nativeRenderDebug: MixedMathNativeRenderDebug
        var reportsIntrinsicContentWidth: Bool
        private var reportsRenderedLineDebug: Bool
        private var reportsScrollableDebug: Bool
        private var reportsRenderStatusDebug: Bool
        @Binding var horizontalOverflowState: HorizontalOverflowState
        weak var webView: WKWebView? // WEAK reference to break the retain cycle
        var lastRenderedSignature: String = ""
        var onTap: (() -> Void)?
        private var updateRetryTask: Task<Void, Never>?
        private var pendingRenderUpdate: (js: String, renderToken: String)?
        private var lastTapEmissionTime: TimeInterval = 0
        private var activeRenderToken = UUID().uuidString
        private var visibilityProbeObserver: NSObjectProtocol?
        private var visibilityProbeTask: Task<Void, Never>?

        init(
            contentHeight: Binding<CGFloat>,
            intrinsicContentWidth: Binding<CGFloat>,
            renderedLineDebug: Binding<[MixedMathRenderedLineDebug]>,
            scrollableDebug: Binding<[MixedMathScrollableDebug]>,
            gestureDebug: Binding<MixedMathGestureDebugSnapshot?>,
            renderStatusDebug: Binding<MixedMathRenderStatusDebug?>,
            nativeRenderDebug: Binding<MixedMathNativeRenderDebug>,
            reportsIntrinsicContentWidth: Bool,
            reportsRenderedLineDebug: Bool,
            reportsScrollableDebug: Bool,
            reportsRenderStatusDebug: Bool,
            horizontalOverflowState: Binding<HorizontalOverflowState>,
            onTap: (() -> Void)?
        ) {
            _contentHeight = contentHeight
            _intrinsicContentWidth = intrinsicContentWidth
            _renderedLineDebug = renderedLineDebug
            _scrollableDebug = scrollableDebug
            _gestureDebug = gestureDebug
            _renderStatusDebug = renderStatusDebug
            _nativeRenderDebug = nativeRenderDebug
            self.reportsIntrinsicContentWidth = reportsIntrinsicContentWidth
            self.reportsRenderedLineDebug = reportsRenderedLineDebug
            self.reportsScrollableDebug = reportsScrollableDebug
            self.reportsRenderStatusDebug = reportsRenderStatusDebug
            _horizontalOverflowState = horizontalOverflowState
            self.onTap = onTap
            super.init()
            visibilityProbeObserver = NotificationCenter.default.addObserver(
                forName: .quizFlashMixedMathVisibilityProbe,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let reason = notification.userInfo?["reason"] as? String ?? "unknown"
                self?.scheduleVisibilityProbes(reason: reason)
            }
        }

        deinit {
            updateRetryTask?.cancel()
            visibilityProbeTask?.cancel()
            if let visibilityProbeObserver {
                NotificationCenter.default.removeObserver(visibilityProbeObserver)
            }
        }

        func attach(webView: WKWebView) {
            guard let mathWebView = webView as? MathWKWebView else {
                recordNativeEvent("attach non-MathWKWebView", stage: "attached")
                return
            }

            nativeRenderDebug.webViewID = mathWebView.quizFlashDebugID
            nativeRenderDebug.checkoutSource = mathWebView.quizFlashCheckoutSource
            nativeRenderDebug.checkoutCount = mathWebView.quizFlashCheckoutCount
            recordNativeEvent(
                "attach source=\(mathWebView.quizFlashCheckoutSource) checkout=\(mathWebView.quizFlashCheckoutCount)",
                stage: "attached"
            )
        }

        func beginRender() -> String {
            let token = UUID().uuidString
            activeRenderToken = token
            nativeRenderDebug.renderToken = String(token.prefix(8))
            nativeRenderDebug.readinessChecks = 0
            nativeRenderDebug.javaScriptExecutionCount = 0
            nativeRenderDebug.heightMessageCount = 0
            nativeRenderDebug.widthMessageCount = 0
            nativeRenderDebug.renderStatusMessageCount = 0
            nativeRenderDebug.lastHeight = 0
            nativeRenderDebug.lastWidth = 0
            nativeRenderDebug.lastError = "none"
            nativeRenderDebug.events = []
            recordNativeEvent("begin render", stage: "render-begun")
            return token
        }

        func invalidateRender() {
            activeRenderToken = UUID().uuidString
            pendingRenderUpdate = nil
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "heightUpdate":
                guard let h = renderCGFloat(from: message.body), h > 0 else { return }
                Task { @MainActor in
                    self.nativeRenderDebug.heightMessageCount += 1
                    self.nativeRenderDebug.lastHeight = h
                    self.recordNativeEvent("height message \(Int(h.rounded()))", stage: "height-received")
                    self.contentHeight = h
                }

            case "widthUpdate":
                guard reportsIntrinsicContentWidth else { return }
                guard let w = renderCGFloat(from: message.body), w > 0 else { return }
                Task { @MainActor in
                    self.nativeRenderDebug.widthMessageCount += 1
                    self.nativeRenderDebug.lastWidth = w
                    self.recordNativeEvent("width message \(Int(w.rounded()))", stage: "width-received")
                    self.intrinsicContentWidth = w
                }

            case "lineDebugUpdate":
                let payload = renderDictionaryArray(from: message.body)
                let lines = payload.compactMap(Self.renderedLineDebug(from:))
                Task { @MainActor in
                    self.renderedLineDebug = lines
                }

            case "scrollableDebugUpdate":
                let payload = renderDictionaryArray(from: message.body)
                let rows = payload.compactMap(Self.scrollableDebug(from:))
                Task { @MainActor in
                    self.scrollableDebug = rows
                }

            case "renderStatusUpdate":
                guard let payload = renderDictionary(from: message.body) else { return }
                Task { @MainActor in
                    self.nativeRenderDebug.renderStatusMessageCount += 1
                    self.recordNativeEvent(
                        "render status \(payload["stage"] as? String ?? "unknown")",
                        stage: "status-received"
                    )
                    self.renderStatusDebug = Self.renderStatusDebug(from: payload)
                }

            case "overflowUpdate":
                guard let overflowPayload = renderDictionary(from: message.body) else { return }
                let canScrollLeft = overflowPayload["canScrollLeft"] as? Bool ?? false
                let canScrollRight = overflowPayload["canScrollRight"] as? Bool ?? false
                let indicatorCenterY = Self.cgFloatValue(overflowPayload["indicatorCenterY"])
                let interactionRegions = Self.dictionaryArray(from: overflowPayload["interactionRects"] ?? [])
                    .map(Self.scrollableInteractionRegion(from:))
                Task { @MainActor in
                    self.webView?.quizflashHasHorizontalOverflow = canScrollLeft || canScrollRight
                    self.webView?.quizflashScrollableMathInteractionRegions = interactionRegions
                    self.horizontalOverflowState = HorizontalOverflowState(
                        canScrollLeft: canScrollLeft,
                        canScrollRight: canScrollRight,
                        indicatorCenterY: indicatorCenterY > 0 ? indicatorCenterY : nil,
                        scrollableInteractionRegions: interactionRegions
                    )
                }

            case "tapUpdate":
                Task { @MainActor in
                    self.publishGestureDebug(
                        decision: "TAP",
                        reason: "js tap bridge",
                        direction: "none",
                        location: .zero,
                        horizontal: 0,
                        vertical: 0,
                        canScrollLeft: self.horizontalOverflowState.canScrollLeft,
                        canScrollRight: self.horizontalOverflowState.canScrollRight,
                        regionCount: self.horizontalOverflowState.scrollableInteractionRegions.count
                    )
                    self.emitTap()
                }

            default:
                return
            }
        }

        private func renderCGFloat(from body: Any) -> CGFloat? {
            guard let value = renderPayloadValue(from: body) else { return nil }
            return Self.cgFloatValue(value)
        }

        private func renderDictionary(from body: Any) -> [String: Any]? {
            guard let payload = body as? [String: Any],
                  payloadRenderTokenMatches(payload)
            else { return nil }
            return payload
        }

        private func renderDictionaryArray(from body: Any) -> [[String: Any]] {
            guard let value = renderPayloadValue(from: body) else { return [] }
            return Self.dictionaryArray(from: value)
        }

        private func renderPayloadValue(from body: Any) -> Any? {
            guard let payload = body as? [String: Any],
                  payloadRenderTokenMatches(payload)
            else { return nil }
            return payload["value"]
        }

        private func payloadRenderTokenMatches(_ payload: [String: Any]) -> Bool {
            payload["renderToken"] as? String == activeRenderToken
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

        nonisolated private static func scrollableInteractionRegion(
            from payload: [String: Any]
        ) -> ScrollableMathInteractionRegion {
            ScrollableMathInteractionRegion(
                rect: CGRect(
                    x: cgFloatValue(payload["left"]),
                    y: cgFloatValue(payload["top"]),
                    width: cgFloatValue(payload["width"]),
                    height: cgFloatValue(payload["height"])
                ),
                canScrollLeft: payload["canScrollLeft"] as? Bool ?? false,
                canScrollRight: payload["canScrollRight"] as? Bool ?? false
            )
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

        nonisolated private static func renderStatusDebug(from payload: [String: Any]) -> MixedMathRenderStatusDebug {
            MixedMathRenderStatusDebug(
                stage: payload["stage"] as? String ?? "unknown",
                contentLength: intValue(payload["contentLength"]),
                childCount: intValue(payload["childCount"]),
                textLength: intValue(payload["textLength"]),
                bodyWidth: cgFloatValue(payload["bodyWidth"]),
                bodyHeight: cgFloatValue(payload["bodyHeight"]),
                contentWidth: cgFloatValue(payload["contentWidth"]),
                contentHeight: cgFloatValue(payload["contentHeight"]),
                contentScrollWidth: cgFloatValue(payload["contentScrollWidth"]),
                contentScrollHeight: cgFloatValue(payload["contentScrollHeight"]),
                inlineCodeCount: intValue(payload["inlineCodeCount"]),
                mathCount: intValue(payload["mathCount"]),
                displayMathCount: intValue(payload["displayMathCount"]),
                inlineCodeScrollCount: intValue(payload["inlineCodeScrollCount"]),
                inlineMathScrollCount: intValue(payload["inlineMathScrollCount"]),
                layoutMetricReportCount: intValue(payload["layoutMetricReportCount"]),
                lineDebugReportCount: intValue(payload["lineDebugReportCount"])
            )
        }

        nonisolated private static func cgFloatValue(_ value: Any?) -> CGFloat {
            if let value = value as? CGFloat { return value }
            if let value = value as? Double { return CGFloat(value) }
            if let value = value as? Int { return CGFloat(value) }
            if let value = value as? NSNumber { return CGFloat(truncating: value) }
            return 0
        }

        nonisolated private static func intValue(_ value: Any?) -> Int {
            if let value = value as? Int { return value }
            if let value = value as? Double { return Int(value) }
            if let value = value as? CGFloat { return Int(value) }
            if let value = value as? NSNumber { return value.intValue }
            return 0
        }

        func configureLineDebugHandler(on webView: WKWebView, enabled: Bool) {
            guard reportsRenderedLineDebug != enabled else { return }
            reportsRenderedLineDebug = enabled
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "lineDebugUpdate")

            guard enabled else {
                DispatchQueue.main.async { [weak self] in
                    self?.renderedLineDebug = []
                }
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
                DispatchQueue.main.async { [weak self] in
                    self?.scrollableDebug = []
                }
                return
            }

            let scriptHandlerWrapper = WeakScriptMessageHandler(delegate: self)
            webView.configuration.userContentController.add(scriptHandlerWrapper, name: "scrollableDebugUpdate")
        }

        func configureRenderStatusDebugHandler(on webView: WKWebView, enabled: Bool) {
            guard reportsRenderStatusDebug != enabled else { return }
            reportsRenderStatusDebug = enabled
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "renderStatusUpdate")

            guard enabled else {
                DispatchQueue.main.async { [weak self] in
                    self?.renderStatusDebug = nil
                }
                return
            }

            let scriptHandlerWrapper = WeakScriptMessageHandler(delegate: self)
            webView.configuration.userContentController.add(scriptHandlerWrapper, name: "renderStatusUpdate")
        }

        /// Safely evaluates JS once the `updateMathContent` function exists.
        /// This fixes the race condition where `evaluateJavaScript` fires before baseHTMLTemplate is fully loaded in new pooled webviews.
        func applyUpdate(js: String, renderToken: String, retries: Int = 15) {
            updateRetryTask?.cancel()
            pendingRenderUpdate = (js, renderToken)
            recordNativeEvent("update queued retries=\(retries)", stage: "update-queued")
            attemptUpdate(js: js, renderToken: renderToken, retries: retries)
        }

        func cancelPendingUpdate() {
            updateRetryTask?.cancel()
            updateRetryTask = nil
            pendingRenderUpdate = nil
        }

        private func attemptUpdate(js: String, renderToken: String, retries: Int) {
            guard renderToken == activeRenderToken else { return }
            guard let webView = webView else { return }
            nativeRenderDebug.readinessChecks += 1
            recordNativeEvent("readiness check retriesLeft=\(retries)", stage: "checking-ready")
            webView.evaluateJavaScript("typeof updateMathContent") { [weak self] result, error in
                guard let self else { return }
                guard renderToken == self.activeRenderToken else { return }
                if let str = result as? String, str == "function" {
                    self.recordNativeEvent("renderer ready", stage: "renderer-ready")
                    webView.evaluateJavaScript(js) { [weak self] _, executionError in
                        guard let self else { return }
                        guard renderToken == self.activeRenderToken else { return }
                        if let executionError {
                            self.nativeRenderDebug.lastError = executionError.localizedDescription
                            self.recordNativeEvent("JS error \(executionError.localizedDescription)", stage: "js-error")
                            return
                        }
                        self.nativeRenderDebug.javaScriptExecutionCount += 1
                        self.recordNativeEvent("updateMathContent executed", stage: "js-executed")
                        if self.pendingRenderUpdate?.renderToken == renderToken {
                            self.pendingRenderUpdate = nil
                        }
                        self.scheduleLayoutMetricReports(renderToken: renderToken)
                        self.scheduleVisibilityProbes(reason: "render update")
                    }
                } else if retries > 0 {
                    if let error {
                        self.nativeRenderDebug.lastError = error.localizedDescription
                    }
                    self.updateRetryTask?.cancel()
                    self.updateRetryTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(50))
                        guard let self, !Task.isCancelled else { return }
                        self.attemptUpdate(js: js, renderToken: renderToken, retries: retries - 1)
                    }
                } else {
                    self.nativeRenderDebug.lastError = error?.localizedDescription ?? "renderer unavailable"
                    self.recordNativeEvent("readiness exhausted", stage: "readiness-failed")
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            nativeRenderDebug.didFinishCount += 1
            recordNativeEvent("navigation didFinish", stage: "navigation-finished")
            guard let pendingRenderUpdate,
                  pendingRenderUpdate.renderToken == activeRenderToken
            else {
                return
            }

            attemptUpdate(
                js: pendingRenderUpdate.js,
                renderToken: pendingRenderUpdate.renderToken,
                retries: 15
            )
        }

        private func recordNativeEvent(_ event: String, stage: String) {
            refreshNativeViewState()
            nativeRenderDebug.stage = stage
            nativeRenderDebug.events.append(event)
            if nativeRenderDebug.events.count > 18 {
                nativeRenderDebug.events.removeFirst(nativeRenderDebug.events.count - 18)
            }
        }

        private func scheduleVisibilityProbes(reason: String) {
            visibilityProbeTask?.cancel()
            probeVisibility(reason: "\(reason) immediate")
            visibilityProbeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                self?.refreshPresentationIfVisible(reason: "\(reason) +220ms")
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                self?.refreshPresentationIfVisible(reason: "\(reason) +500ms")
            }
        }

        private func probeVisibility(reason: String) {
            refreshNativeViewState()
            let state = nativeRenderDebug
            recordNativeEvent(
                "visibility \(reason) window=\(state.windowAttached ? 1 : 0) hidden=\(state.isHidden ? 1 : 0) alpha=\(debugMetric(state.alpha)) layer=\(debugMetric(CGFloat(state.layerOpacity))) effective=\(debugMetric(CGFloat(state.effectiveOpacity))) frame=\(debugRect(state.frame)) intersects=\(state.intersectsWindow ? 1 : 0)",
                stage: "visibility-probe"
            )
        }

        private func refreshPresentationIfVisible(reason: String) {
            probeVisibility(reason: reason)
            guard let webView else { return }

            let state = nativeRenderDebug
            let hasRenderableAlpha = state.alpha > 0
                && state.layerOpacity > 0
                && state.effectiveOpacity > 0
            guard state.windowAttached,
                  !state.isHidden,
                  state.intersectsWindow,
                  hasRenderableAlpha,
                  state.bounds.width > 1,
                  state.bounds.height > 1 else {
                recordNativeEvent(
                    "presentation refresh skipped \(reason) effective=\(debugMetric(CGFloat(state.effectiveOpacity)))",
                    stage: "presentation-refresh-skipped"
                )
                return
            }

            webView.setNeedsLayout()
            webView.layoutIfNeeded()
            webView.scrollView.setNeedsLayout()
            webView.scrollView.layoutIfNeeded()
            webView.layer.setNeedsDisplay()
            webView.scrollView.layer.setNeedsDisplay()

            let repaintJavaScript = """
            (() => {
                const node = document.getElementById('content') || document.body;
                if (!node) return false;
                const previousTransform = node.style.transform;
                node.style.transform = 'translateZ(0.001px)';
                void node.offsetHeight;
                requestAnimationFrame(() => {
                    node.style.transform = previousTransform;
                    void node.offsetHeight;
                });
                return true;
            })();
            """

            webView.evaluateJavaScript(repaintJavaScript) { [weak self] _, error in
                guard let self else { return }
                if let error {
                    self.nativeRenderDebug.lastError = error.localizedDescription
                    self.recordNativeEvent(
                        "presentation refresh failed \(reason): \(error.localizedDescription)",
                        stage: "presentation-refresh-error"
                    )
                } else {
                    self.recordNativeEvent(
                        "presentation refresh executed \(reason)",
                        stage: "presentation-refreshed"
                    )
                }
            }
        }

        private func refreshNativeViewState() {
            guard let webView else { return }
            if let mathWebView = webView as? MathWKWebView {
                nativeRenderDebug.webViewID = mathWebView.quizFlashDebugID
                nativeRenderDebug.checkoutSource = mathWebView.quizFlashCheckoutSource
                nativeRenderDebug.checkoutCount = mathWebView.quizFlashCheckoutCount
            }
            nativeRenderDebug.windowAttached = webView.window != nil
            nativeRenderDebug.isHidden = webView.isHidden
            nativeRenderDebug.alpha = webView.alpha
            nativeRenderDebug.layerOpacity = webView.layer.opacity
            nativeRenderDebug.effectiveOpacity = effectiveOpacity(of: webView)
            nativeRenderDebug.frame = webView.frame
            nativeRenderDebug.bounds = webView.bounds
            if let window = webView.window {
                let frameInWindow = webView.convert(webView.bounds, to: window)
                nativeRenderDebug.intersectsWindow = window.bounds.intersects(frameInWindow)
            } else {
                nativeRenderDebug.intersectsWindow = false
            }
        }

        private func effectiveOpacity(of view: UIView) -> Float {
            var opacity: Float = 1
            var currentView: UIView? = view

            while let viewInHierarchy = currentView {
                guard !viewInHierarchy.isHidden else { return 0 }
                opacity *= viewInHierarchy.layer.opacity
                currentView = viewInHierarchy.superview
            }

            return opacity
        }

        private func debugMetric(_ value: CGFloat) -> String {
            String(format: "%.2f", Double(value))
        }

        private func debugRect(_ rect: CGRect) -> String {
            "\(debugMetric(rect.minX)),\(debugMetric(rect.minY)),\(debugMetric(rect.width))x\(debugMetric(rect.height))"
        }

        private func scheduleLayoutMetricReports(renderToken: String) {
            let delays: [Duration] = [
                .milliseconds(0),
                .milliseconds(50),
                .milliseconds(150),
                .milliseconds(350)
            ]

            updateRetryTask?.cancel()
            updateRetryTask = Task { @MainActor [weak self] in
                for delay in delays {
                    try? await Task.sleep(for: delay)
                    guard let self,
                          !Task.isCancelled,
                          renderToken == self.activeRenderToken,
                          let webView = self.webView else {
                        return
                    }

                    webView.evaluateJavaScript(
                        """
                        if (typeof reportLayoutMetrics === 'function') {
                            reportLayoutMetrics();
                        }
                        if (typeof reportLineDebug === 'function') {
                            reportLineDebug();
                        }
                        """,
                        completionHandler: nil
                    )
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
            if let mathWebView = webView as? MathWKWebView, !mathWebView.allowsFullQuizFlashInteraction {
                return shouldBeginReadOnlyScrollablePan(pan, in: mathWebView)
            }
            guard shouldHandOffHorizontalPanToParent(pan) else { return true }
            return false
        }

        private func shouldBeginReadOnlyScrollablePan(
            _ pan: UIPanGestureRecognizer,
            in mathWebView: MathWKWebView
        ) -> Bool {
            let location = pan.location(in: mathWebView)
            let region = mathWebView.scrollableInteractionRegion(containing: location)

            let view = pan.view ?? mathWebView
            let translation = pan.translation(in: view)
            let velocity = pan.velocity(in: view)
            let horizontal = max(abs(translation.x), abs(velocity.x))
            let vertical = max(abs(translation.y), abs(velocity.y))

            guard let region else {
                publishGestureDebug(
                    decision: "CARD",
                    reason: "no scroll region",
                    direction: "none",
                    location: location,
                    horizontal: horizontal,
                    vertical: vertical,
                    canScrollLeft: false,
                    canScrollRight: false,
                    regionCount: mathWebView.scrollableInteractionRegions.count
                )
                return false
            }

            guard horizontal > vertical * 1.15 else {
                publishGestureDebug(
                    decision: "CARD",
                    reason: "not horizontal",
                    direction: "none",
                    location: location,
                    horizontal: horizontal,
                    vertical: vertical,
                    canScrollLeft: region.canScrollLeft,
                    canScrollRight: region.canScrollRight,
                    regionCount: mathWebView.scrollableInteractionRegions.count
                )
                return false
            }

            let direction = abs(translation.x) > 0 ? translation.x : velocity.x
            guard direction != 0 else {
                publishGestureDebug(
                    decision: "CARD",
                    reason: "zero direction",
                    direction: "none",
                    location: location,
                    horizontal: horizontal,
                    vertical: vertical,
                    canScrollLeft: region.canScrollLeft,
                    canScrollRight: region.canScrollRight,
                    regionCount: mathWebView.scrollableInteractionRegions.count
                )
                return false
            }

            let wantsLeftScroll = direction > 0
            let canScrollRequestedDirection = wantsLeftScroll ? region.canScrollLeft : region.canScrollRight
            publishGestureDebug(
                decision: canScrollRequestedDirection ? "WEB" : "CARD",
                reason: canScrollRequestedDirection ? "scroll available" : "edge handoff",
                direction: wantsLeftScroll ? "finger right" : "finger left",
                location: location,
                horizontal: horizontal,
                vertical: vertical,
                canScrollLeft: region.canScrollLeft,
                canScrollRight: region.canScrollRight,
                regionCount: mathWebView.scrollableInteractionRegions.count
            )

            return canScrollRequestedDirection
        }

        private func publishGestureDebug(
            decision: String,
            reason: String,
            direction: String,
            location: CGPoint,
            horizontal: CGFloat,
            vertical: CGFloat,
            canScrollLeft: Bool,
            canScrollRight: Bool,
            regionCount: Int
        ) {
            gestureDebug = MixedMathGestureDebugSnapshot(
                timestamp: Date(),
                decision: decision,
                reason: reason,
                direction: direction,
                location: location,
                horizontalMagnitude: horizontal,
                verticalMagnitude: vertical,
                canScrollLeft: canScrollLeft,
                canScrollRight: canScrollRight,
                regionCount: regionCount
            )
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
    var indicatorCenterY: CGFloat?
    var scrollableInteractionRegions: [ScrollableMathInteractionRegion] = []

    var hasOverflow: Bool {
        canScrollLeft || canScrollRight
    }
}

private struct HorizontalOverflowIndicator: View {
    let canScrollLeft: Bool
    let canScrollRight: Bool
    let verticalCenterY: CGFloat?
    let regions: [ScrollableMathInteractionRegion]
    private let horizontalOffset: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                let visibleRegions = regions.filter { $0.canScrollLeft || $0.canScrollRight }
                if visibleRegions.isEmpty {
                    fallbackCues(in: proxy.size)
                } else {
                    ForEach(Array(visibleRegions.enumerated()), id: \.offset) { _, region in
                        regionCues(region, in: proxy.size)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func fallbackCues(in size: CGSize) -> some View {
        let centerY = clampedCenterY(verticalCenterY, in: size.height)

        if canScrollLeft {
            edgeCue(direction: .leading)
                .position(x: 0, y: centerY)
                .offset(x: -horizontalOffset)
        }
        if canScrollRight {
            edgeCue(direction: .trailing)
                .position(x: size.width, y: centerY)
                .offset(x: horizontalOffset)
        }
    }

    @ViewBuilder
    private func regionCues(_ region: ScrollableMathInteractionRegion, in size: CGSize) -> some View {
        let centerY = clampedCenterY(region.rect.midY, in: size.height)
        let leadingX = clampedX(region.rect.minX, in: size.width)
        let trailingX = clampedX(region.rect.maxX, in: size.width)

        if region.canScrollLeft {
            edgeCue(direction: .leading)
                .position(x: leadingX, y: centerY)
                .offset(x: -horizontalOffset)
        }
        if region.canScrollRight {
            edgeCue(direction: .trailing)
                .position(x: trailingX, y: centerY)
                .offset(x: horizontalOffset)
        }
    }

    private func clampedCenterY(in height: CGFloat) -> CGFloat {
        clampedCenterY(verticalCenterY, in: height)
    }

    private func clampedCenterY(_ centerY: CGFloat?, in height: CGFloat) -> CGFloat {
        guard let centerY else {
            return max(height / 2, 0)
        }

        let inset = UIConstants.Spacing.small
        return min(max(centerY, inset), max(height - inset, inset))
    }

    private func clampedX(_ value: CGFloat, in width: CGFloat) -> CGFloat {
        min(max(value, 0), max(width, 0))
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
