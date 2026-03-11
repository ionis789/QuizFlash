//
//  DeckGridRichPreviewRenderer.swift
//  QuizFlash
//
//  Deck-owned image rasterization pipeline for heavy deck previews.
//

import SwiftUI
import SwiftData
import UIKit
import WebKit

// =============================================================================
// MARK: - Shared Metrics
// =============================================================================

enum DeckGridCardMetrics {
    static let headerRowHeight: CGFloat = 20
    static let headerRegionHeight: CGFloat = 23
    static let headerControlHeight: CGFloat = 20
    static let headerControlHitSize: CGFloat = 28
    static let headerMenuIconSize: CGFloat = 10.5
    static let headerTopInset: CGFloat = 6
    static let sideInset: CGFloat = 14
    static let bottomInset: CGFloat = 14
    static let headerTrailingReserve: CGFloat = 30
    static let contentTopPadding: CGFloat = 6
    static let zoneSpacing: CGFloat = 10
    static let separatorWidth: CGFloat = 26
    static let mediaThumbnailSize: CGFloat = 34
    static let mediaBadgeSize: CGFloat = 22
    static let mediaInsetCompensation: CGFloat = 42
    static let statusDotSize: CGFloat = 6
    static let bottomBlurHeight: CGFloat = 44
}

private enum DeckGridCardContentDensity {
    case short
    case standard
    case dense
}

// =============================================================================
// MARK: - Card Preview Cache
// =============================================================================

final class CardPreviewCache {
    static let shared = CardPreviewCache()

    private let cache = NSCache<NSString, CardPreviewPayload>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 20 * 1024 * 1024
    }

    func payload(for id: PersistentIdentifier) -> CardPreviewPayload? {
        cache.object(forKey: cacheKey(for: id))
    }

    func store(_ payload: CardPreviewPayload, for id: PersistentIdentifier) {
        let cost = (payload.thumbnailData?.count ?? 0) + 512
        cache.setObject(payload, forKey: cacheKey(for: id), cost: cost)
    }

    func invalidate(for id: PersistentIdentifier) {
        cache.removeObject(forKey: cacheKey(for: id))
    }

    @MainActor private var sharedActor: CardFetchActor?

    @MainActor
    private func getOrCreateActor(container: ModelContainer) -> CardFetchActor {
        if let actor = sharedActor { return actor }
        let actor = CardFetchActor(container: container)
        sharedActor = actor
        return actor
    }

    @MainActor
    func fetchSnapshot(deckID: PersistentIdentifier, container: ModelContainer) async -> CardDataSnapshot {
        let actor = getOrCreateActor(container: container)
        return await actor.fetchSnapshot(deckID: deckID)
    }

    @MainActor
    func loadPayload(for id: PersistentIdentifier, container: ModelContainer) async -> CardPreviewPayload? {
        if let cached = payload(for: id) { return cached }

        let actor = getOrCreateActor(container: container)
        if let generated = await actor.generateThumbnail(for: id) {
            store(generated, for: id)
            return generated
        }
        return nil
    }

    @MainActor
    func flush() {
        let dying = sharedActor
        sharedActor = nil
        cache.removeAllObjects()

        if let actor = dying {
            Task { await actor.tearDown() }
        }
    }

    private func cacheKey(for id: PersistentIdentifier) -> NSString {
        "\(id.hashValue)" as NSString
    }
}

final class CardPreviewPayload: @unchecked Sendable {
    let thumbnailData: Data?
    let hasFrontImage: Bool
    let hasFrontSketch: Bool

    nonisolated init(thumbnailData: Data?, hasFrontImage: Bool, hasFrontSketch: Bool) {
        self.thumbnailData = thumbnailData
        self.hasFrontImage = hasFrontImage
        self.hasFrontSketch = hasFrontSketch
    }
}

// =============================================================================
// MARK: - Rich Preview Request
// =============================================================================

enum DeckGridRichPreviewSide: String, Sendable {
    case front
    case back
}

enum DeckGridRichPreviewTone: String, Sendable {
    case question
    case answer

    func cssColor(for isDarkMode: Bool) -> String {
        switch self {
        case .question:
            return isDarkMode ? "#FFFFFF" : "#000000"
        case .answer:
            return isDarkMode
                ? "rgba(255,255,255,0.84)"
                : "rgba(0,0,0,0.62)"
        }
    }
}

struct DeckGridRichPreviewRequest: Hashable, Sendable {
    private static let cacheVersion = "v2"

    let cardID: PersistentIdentifier
    let side: DeckGridRichPreviewSide
    let text: String
    let width: CGFloat
    let maxHeight: CGFloat
    let fontSize: CGFloat
    let tone: DeckGridRichPreviewTone
    let isDarkMode: Bool

    var cacheKey: NSString {
        let widthSignature = Int((width * UIScreen.main.scale).rounded())
        let heightSignature = Int((maxHeight * UIScreen.main.scale).rounded())
        let textSignature = text.hashValue
        return [
            Self.cacheVersion,
            "\(cardID.hashValue)",
            "\(textSignature)",
            side.rawValue,
            "\(widthSignature)",
            "\(heightSignature)",
            String(format: "%.2f", fontSize),
            tone.rawValue,
            isDarkMode ? "dark" : "light"
        ].joined(separator: "|") as NSString
    }
}

// =============================================================================
// MARK: - Rich Preview Cache
// =============================================================================

@MainActor
final class DeckGridRichPreviewCache {
    static let shared = DeckGridRichPreviewCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 360
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for request: DeckGridRichPreviewRequest) -> UIImage? {
        cache.object(forKey: request.cacheKey)
    }

    func store(_ image: UIImage, for request: DeckGridRichPreviewRequest) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: request.cacheKey, cost: cost)
    }

    func flush() {
        cache.removeAllObjects()
    }
}

// =============================================================================
// MARK: - Rich Preview Worker Pool
// =============================================================================

actor DeckRichTextRasterizerCoordinator {
    private var available: [Int]
    private var waiters: [CheckedContinuation<Int, Never>] = []

    init(workerCount: Int) {
        available = Array(0..<workerCount)
    }

    func acquire() async -> Int {
        if let worker = available.popLast() {
            return worker
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release(_ worker: Int) {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume(returning: worker)
        } else {
            available.append(worker)
        }
    }
}

@MainActor
private final class DeckRichTextRasterizerWorker: NSObject, WKNavigationDelegate {
    private var webView: WKWebView
    private var isTemplateLoaded = false
    private var loadContinuation: CheckedContinuation<Bool, Never>?
    private var generation: UInt64 = 0

    override init() {
        webView = Self.makeWebView()
        super.init()
        webView.navigationDelegate = self
    }

    func image(for request: DeckGridRichPreviewRequest) async -> UIImage? {
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let expectedGeneration = generation
        guard await ensureTemplateLoaded(expectedGeneration: expectedGeneration) else { return nil }
        guard !Task.isCancelled, expectedGeneration == generation else { return nil }
        guard let script = DeckGridRichPreviewHTML.updateScript(for: request) else { return nil }
        guard await evaluateWhenReady(script, expectedGeneration: expectedGeneration) else { return nil }
        guard !Task.isCancelled, expectedGeneration == generation else { return nil }

        try? await Task.sleep(nanoseconds: 30_000_000)
        let measuredHeight = await measureHeight(expectedGeneration: expectedGeneration)
        let snapshotHeight = min(max(1, measuredHeight), request.maxHeight)
        guard snapshotHeight > 1 else { return nil }

        webView.frame = CGRect(origin: .zero, size: CGSize(width: request.width, height: snapshotHeight))
        webView.layoutIfNeeded()

        return await takeSnapshot(size: webView.bounds.size, expectedGeneration: expectedGeneration)
    }

    func suspend() {
        generation &+= 1
        loadContinuation?.resume(returning: false)
        loadContinuation = nil
        isTemplateLoaded = false
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView = Self.makeWebView()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isTemplateLoaded = true
        loadContinuation?.resume(returning: true)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isTemplateLoaded = false
        loadContinuation?.resume(returning: false)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isTemplateLoaded = false
        loadContinuation?.resume(returning: false)
        loadContinuation = nil
    }

    private func ensureTemplateLoaded(expectedGeneration: UInt64) async -> Bool {
        if isTemplateLoaded { return true }
        if expectedGeneration != generation { return false }

        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
            webView.loadHTMLString(
                DeckGridRichPreviewHTML.baseHTMLTemplate,
                baseURL: Bundle.main.bundleURL
            )
        }
    }

    private func evaluateWhenReady(_ script: String, expectedGeneration: UInt64, retries: Int = 16) async -> Bool {
        guard expectedGeneration == generation else { return false }
        let readiness = await evaluateJavaScript("typeof updateMathContent")
        if let readiness = readiness as? String, readiness == "function" {
            _ = await evaluateJavaScript(script)
            return true
        }

        guard retries > 0, !Task.isCancelled else { return false }
        try? await Task.sleep(nanoseconds: 25_000_000)
        return await evaluateWhenReady(script, expectedGeneration: expectedGeneration, retries: retries - 1)
    }

    private func measureHeight(expectedGeneration: UInt64) async -> CGFloat {
        guard expectedGeneration == generation else { return 0 }
        let script = """
        (() => {
            const el = document.getElementById('content');
            if (!el) { return 0; }
            return Math.ceil(Math.max(el.getBoundingClientRect().height, el.scrollHeight));
        })()
        """
        let result = await evaluateJavaScript(script)
        if let number = result as? NSNumber {
            return CGFloat(truncating: number)
        }
        if let value = result as? Double {
            return CGFloat(value)
        }
        return 0
    }

    private func evaluateJavaScript(_ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result)
            }
        }
    }

    private func takeSnapshot(size: CGSize, expectedGeneration: UInt64) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(origin: .zero, size: size)
            configuration.afterScreenUpdates = true
            webView.takeSnapshot(with: configuration) { image, _ in
                guard expectedGeneration == self.generation, !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.isUserInteractionEnabled = false
        return webView
    }
}

@MainActor
final class DeckGridRichPreviewRenderer {
    static let shared = DeckGridRichPreviewRenderer()

    private static let workerCount = 3

    private let coordinator = DeckRichTextRasterizerCoordinator(workerCount: workerCount)
    private let workers: [DeckRichTextRasterizerWorker]

    private init() {
        workers = (0..<Self.workerCount).map { _ in DeckRichTextRasterizerWorker() }
    }

    func image(for request: DeckGridRichPreviewRequest) async -> UIImage? {
        if let cached = DeckGridRichPreviewCache.shared.image(for: request) {
            return cached
        }

        let workerIndex = await coordinator.acquire()
        defer {
            Task { await coordinator.release(workerIndex) }
        }

        guard !Task.isCancelled else { return nil }
        guard let image = await workers[workerIndex].image(for: request) else { return nil }
        guard !Task.isCancelled else { return nil }
        DeckGridRichPreviewCache.shared.store(image, for: request)
        return image
    }

    func suspend(flushCache: Bool = false) {
        for worker in workers {
            worker.suspend()
        }
        if flushCache {
            DeckGridRichPreviewCache.shared.flush()
        }
    }
}

// =============================================================================
// MARK: - Deck Surface Descriptor
// =============================================================================

struct DeckCardSurfaceDescriptor: Hashable, Sendable {
    let id: PersistentIdentifier
    let cardNumber: Int
    let interval: Int
    let reviewHistoryIsEmpty: Bool
    let frontText: String
    let backText: String
    let frontPreviewText: String
    let backPreviewText: String
    let frontNeedsRichSnapshot: Bool
    let backNeedsRichSnapshot: Bool

    init(card: GridCardInfo) {
        id = card.id
        cardNumber = card.cardNumber
        interval = card.interval
        reviewHistoryIsEmpty = card.reviewHistoryIsEmpty
        frontText = card.frontText
        backText = card.backText
        frontPreviewText = card.frontPreviewText
        backPreviewText = card.backPreviewText
        frontNeedsRichSnapshot = card.frontNeedsRichSnapshot
        backNeedsRichSnapshot = card.backNeedsRichSnapshot
    }

    var surfaceSignature: String {
        [
            "\(cardNumber)",
            "\(interval)",
            reviewHistoryIsEmpty ? "1" : "0",
            frontText,
            backText,
            frontPreviewText,
            backPreviewText,
            frontNeedsRichSnapshot ? "1" : "0",
            backNeedsRichSnapshot ? "1" : "0"
        ].joined(separator: "|")
    }
}

struct DeckCardSurfaceLayout: Hashable, Sendable {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let scale: CGFloat
    let isDarkMode: Bool
    let columns: Int

    var pixelWidth: Int {
        Int((cardWidth * scale).rounded())
    }

    var pixelHeight: Int {
        Int((cardHeight * scale).rounded())
    }

    var cacheKey: String {
        [
            "\(pixelWidth)",
            "\(pixelHeight)",
            "\(columns)",
            isDarkMode ? "dark" : "light"
        ].joined(separator: "|")
    }
}

// =============================================================================
// MARK: - Deck Card Surface Renderer
// =============================================================================

enum DeckCardSurfaceRenderer {
    static let renderVersion = "v3"

    static func renderSurface(
        descriptor: DeckCardSurfaceDescriptor,
        container: ModelContainer,
        layout: DeckCardSurfaceLayout
    ) async -> UIImage? {
        let mediaPayload = await CardPreviewCache.shared.loadPayload(for: descriptor.id, container: container)
        let hasFooterVisual = (mediaPayload?.thumbnailData != nil)
            || (mediaPayload?.hasFrontImage == true)
            || (mediaPayload?.hasFrontSketch == true)
        let plan = contentPlan(
            for: descriptor,
            cardWidth: layout.cardWidth,
            hasFooterVisual: hasFooterVisual
        )

        async let questionRich = richTextImageIfNeeded(
            text: plan.questionRichText,
            needsRichPreview: plan.questionNeedsRichPreview,
            descriptor: descriptor,
            width: plan.questionWidth,
            maxHeight: plan.questionMaxHeight,
            fontSize: plan.questionFontSize,
            tone: .question,
            side: plan.questionSide,
            layout: layout
        )

        async let answerRich = richTextImageIfNeeded(
            text: plan.answerRichText,
            needsRichPreview: plan.answerNeedsRichPreview,
            descriptor: descriptor,
            width: plan.answerWidth,
            maxHeight: plan.answerMaxHeight,
            fontSize: plan.answerFontSize,
            tone: .answer,
            side: .back,
            layout: layout
        )

        let questionSnapshot = await questionRich
        let answerSnapshot = await answerRich

        return composeCard(
            descriptor: descriptor,
            layout: layout,
            plan: plan,
            questionSnapshot: questionSnapshot,
            answerSnapshot: answerSnapshot,
            mediaPayload: mediaPayload
        )
    }

    static func placeholderImage(layout: DeckCardSurfaceLayout) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = layout.scale

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: layout.cardWidth, height: layout.cardHeight),
            format: format
        )

        let baseColor = layout.isDarkMode
            ? UIColor.secondarySystemGroupedBackground
            : UIColor.white
        let shimmerTop = UIColor.white.withAlphaComponent(layout.isDarkMode ? 0.04 : 0.3)
        let shimmerBottom = UIColor.label.withAlphaComponent(layout.isDarkMode ? 0.08 : 0.04)

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: CGSize(width: layout.cardWidth, height: layout.cardHeight))
            let cardPath = UIBezierPath(
                roundedRect: rect,
                cornerRadius: UIConstants.Radius.large
            )

            baseColor.setFill()
            cardPath.fill()

            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    shimmerTop.cgColor,
                    UIColor.clear.cgColor,
                    shimmerBottom.cgColor
                ] as CFArray,
                locations: [0, 0.35, 1]
            )

            context.cgContext.saveGState()
            cardPath.addClip()
            if let gradient {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: []
                )
            }
            drawPlaceholderBars(in: context.cgContext, rect: rect, isDarkMode: layout.isDarkMode)
            context.cgContext.restoreGState()
        }
    }

    private static func richTextImageIfNeeded(
        text: String,
        needsRichPreview: Bool,
        descriptor: DeckCardSurfaceDescriptor,
        width: CGFloat,
        maxHeight: CGFloat,
        fontSize: CGFloat,
        tone: DeckGridRichPreviewTone,
        side: DeckGridRichPreviewSide,
        layout: DeckCardSurfaceLayout
    ) async -> UIImage? {
        guard needsRichPreview else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let request = DeckGridRichPreviewRequest(
            cardID: descriptor.id,
            side: side,
            text: text,
            width: max(1, width),
            maxHeight: maxHeight,
            fontSize: fontSize,
            tone: tone,
            isDarkMode: layout.isDarkMode
        )
        return await DeckGridRichPreviewRenderer.shared.image(for: request)
    }

    private static func composeCard(
        descriptor: DeckCardSurfaceDescriptor,
        layout: DeckCardSurfaceLayout,
        plan: CardContentPlan,
        questionSnapshot: UIImage?,
        answerSnapshot: UIImage?,
        mediaPayload: CardPreviewPayload?
    ) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = layout.scale

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: layout.cardWidth, height: layout.cardHeight),
            format: format
        )

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: CGSize(width: layout.cardWidth, height: layout.cardHeight))
            drawCardBackground(in: context.cgContext, rect: rect, isDarkMode: layout.isDarkMode)
            drawTopBar(
                in: context.cgContext,
                descriptor: descriptor,
                width: layout.cardWidth,
                isDarkMode: layout.isDarkMode
            )
            drawContent(
                in: context.cgContext,
                descriptor: descriptor,
                plan: plan,
                questionSnapshot: questionSnapshot,
                answerSnapshot: answerSnapshot,
                mediaPayload: mediaPayload,
                cardSize: rect.size,
                isDarkMode: layout.isDarkMode
            )
            drawBottomOverlay(in: context.cgContext, rect: rect, isDarkMode: layout.isDarkMode)
        }
    }

    private static func drawCardBackground(in context: CGContext, rect: CGRect, isDarkMode: Bool) {
        let cardPath = UIBezierPath(
            roundedRect: rect,
            cornerRadius: UIConstants.Radius.large
        )

        let base = isDarkMode
            ? UIColor.secondarySystemGroupedBackground
            : UIColor.white
        base.setFill()
        cardPath.fill()

        context.saveGState()
        cardPath.addClip()

        let topHighlight = UIColor.white.withAlphaComponent(isDarkMode ? 0.028 : 0.3)
        let topGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                topHighlight.cgColor,
                UIColor.clear.cgColor
            ] as CFArray,
            locations: [0, 1]
        )
        if let topGradient {
            context.drawLinearGradient(
                topGradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.midY),
                options: []
            )
        }

        let bottomGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.clear.cgColor,
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(isDarkMode ? 0.08 : 0.018).cgColor
            ] as CFArray,
            locations: [0, 0.7, 1]
        )
        if let bottomGradient {
            context.drawLinearGradient(
                bottomGradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
        }

        context.restoreGState()
    }

    private static func drawTopBar(
        in context: CGContext,
        descriptor: DeckCardSurfaceDescriptor,
        width: CGFloat,
        isDarkMode: Bool
    ) {
        let horizontalInset = DeckGridCardMetrics.sideInset
        let dotRect = CGRect(
            x: horizontalInset,
            y: DeckGridCardMetrics.headerTopInset + 7,
            width: DeckGridCardMetrics.statusDotSize,
            height: DeckGridCardMetrics.statusDotSize
        )
        context.setFillColor(statusUIColor(for: descriptor).cgColor)
        context.fillEllipse(in: dotRect)

        let labelRect = CGRect(
            x: horizontalInset + DeckGridCardMetrics.statusDotSize + 10,
            y: DeckGridCardMetrics.headerTopInset + 1,
            width: width - horizontalInset * 2 - 40,
            height: DeckGridCardMetrics.headerRowHeight
        )
        let labelFont = roundedFont(size: 8.5, weight: .bold)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: UIColor.secondaryLabel,
            .kern: 0.45
        ]
        NSString(string: "CARD \(descriptor.cardNumber)").draw(in: labelRect, withAttributes: labelAttrs)

        let lineRect = CGRect(
            x: horizontalInset,
            y: DeckGridCardMetrics.headerTopInset + DeckGridCardMetrics.headerRegionHeight - 1,
            width: width - horizontalInset * 2 - DeckGridCardMetrics.headerTrailingReserve,
            height: 1
        )
        let lineGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.label.withAlphaComponent(isDarkMode ? 0.09 : 0.065).cgColor,
                UIColor.label.withAlphaComponent(isDarkMode ? 0.02 : 0.012).cgColor,
                UIColor.clear.cgColor
            ] as CFArray,
            locations: [0, 0.5, 1]
        )
        if let lineGradient {
            context.saveGState()
            context.clip(to: lineRect)
            context.drawLinearGradient(
                lineGradient,
                start: CGPoint(x: lineRect.minX, y: lineRect.midY),
                end: CGPoint(x: lineRect.maxX, y: lineRect.midY),
                options: []
            )
            context.restoreGState()
        }
    }

    private static func drawContent(
        in context: CGContext,
        descriptor: DeckCardSurfaceDescriptor,
        plan: CardContentPlan,
        questionSnapshot: UIImage?,
        answerSnapshot: UIImage?,
        mediaPayload: CardPreviewPayload?,
        cardSize: CGSize,
        isDarkMode: Bool
    ) {
        let horizontalInset = DeckGridCardMetrics.sideInset
        let contentTop = DeckGridCardMetrics.headerTopInset
            + DeckGridCardMetrics.headerRegionHeight
            + DeckGridCardMetrics.contentTopPadding
        let availableWidth = max(0, cardSize.width - horizontalInset * 2)
        let questionRect = CGRect(
            x: horizontalInset,
            y: contentTop,
            width: availableWidth,
            height: plan.questionMaxHeight
        )

        if let questionSnapshot {
            questionSnapshot.draw(in: CGRect(
                x: questionRect.minX,
                y: questionRect.minY,
                width: min(questionRect.width, questionSnapshot.size.width),
                height: min(questionRect.height, questionSnapshot.size.height)
            ))
        } else if !plan.questionFallbackText.isEmpty {
            let textColor = UIColor.label
            let attr = DeckGridFormattedFallbackBuilder.make(
                text: plan.questionFallbackText,
                fontSize: plan.questionFontSize,
                textColor: textColor,
                isDarkMode: isDarkMode
            )
            drawText(attr, in: questionRect, lineLimit: plan.questionLineLimit)
        } else if mediaPayload == nil {
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: roundedFont(size: 18, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let detailAttrs: [NSAttributedString.Key: Any] = [
                .font: roundedFont(size: 12, weight: .medium),
                .foregroundColor: UIColor.tertiaryLabel
            ]
            NSString(string: "Empty card").draw(
                in: CGRect(x: questionRect.minX, y: questionRect.minY, width: questionRect.width, height: 22),
                withAttributes: titleAttrs
            )
            NSString(string: "Add text, math, or media.").draw(
                in: CGRect(x: questionRect.minX, y: questionRect.minY + 26, width: questionRect.width, height: 18),
                withAttributes: detailAttrs
            )
        }

        if plan.hasSecondaryZone {
            let separatorY = questionRect.maxY + DeckGridCardMetrics.zoneSpacing
            context.setFillColor(UIColor.label.withAlphaComponent(isDarkMode ? 0.16 : 0.09).cgColor)
            context.fill(CGRect(
                x: horizontalInset,
                y: separatorY,
                width: DeckGridCardMetrics.separatorWidth,
                height: 1
            ))

            let answerY = separatorY + UIConstants.Spacing.small + 1
            let answerRect = CGRect(
                x: horizontalInset,
                y: answerY,
                width: plan.answerWidth,
                height: plan.answerMaxHeight
            )

            if let answerSnapshot {
                answerSnapshot.draw(in: CGRect(
                    x: answerRect.minX,
                    y: answerRect.minY,
                    width: min(answerRect.width, answerSnapshot.size.width),
                    height: min(answerRect.height, answerSnapshot.size.height)
                ))
            } else if !plan.answerFallbackText.isEmpty {
                let answerColor = isDarkMode
                    ? UIColor.white.withAlphaComponent(0.84)
                    : UIColor.black.withAlphaComponent(0.62)
                let attr = DeckGridFormattedFallbackBuilder.make(
                    text: plan.answerFallbackText,
                    fontSize: plan.answerFontSize,
                    textColor: answerColor,
                    isDarkMode: isDarkMode
                )
                drawText(attr, in: answerRect, lineLimit: plan.answerLineLimit)
            }
        }

        if let mediaPayload {
            drawMediaPayload(
                mediaPayload,
                in: context,
                cardSize: cardSize,
                isDarkMode: isDarkMode
            )
        }
    }

    private static func drawMediaPayload(
        _ payload: CardPreviewPayload,
        in context: CGContext,
        cardSize: CGSize,
        isDarkMode: Bool
    ) {
        let origin = CGPoint(
            x: cardSize.width - DeckGridCardMetrics.sideInset - DeckGridCardMetrics.mediaThumbnailSize,
            y: cardSize.height - DeckGridCardMetrics.bottomInset - DeckGridCardMetrics.mediaThumbnailSize
        )

        if let thumbnailData = payload.thumbnailData, let image = UIImage(data: thumbnailData) {
            let rect = CGRect(
                origin: origin,
                size: CGSize(
                    width: DeckGridCardMetrics.mediaThumbnailSize,
                    height: DeckGridCardMetrics.mediaThumbnailSize
                )
            )
            let path = UIBezierPath(
                roundedRect: rect,
                cornerRadius: UIConstants.Radius.medium
            )
            context.saveGState()
            path.addClip()
            image.draw(in: rect)
            context.restoreGState()

            context.setStrokeColor(
                UIColor.white.withAlphaComponent(isDarkMode ? 0.12 : 0.58).cgColor
            )
            context.setLineWidth(0.75)
            context.addPath(path.cgPath)
            context.strokePath()
            return
        }

        var badgeOrigin = origin
        let symbols = [
            payload.hasFrontImage ? "photo" : nil,
            payload.hasFrontSketch ? "scribble.variable" : nil
        ].compactMap { $0 }

        for symbol in symbols {
            let badgeRect = CGRect(
                origin: badgeOrigin,
                size: CGSize(
                    width: DeckGridCardMetrics.mediaBadgeSize,
                    height: DeckGridCardMetrics.mediaBadgeSize
                )
            )
            let badgePath = UIBezierPath(
                roundedRect: badgeRect,
                cornerRadius: UIConstants.Radius.small
            )
            context.setFillColor(
                UIColor.label.withAlphaComponent(isDarkMode ? 0.08 : 0.045).cgColor
            )
            context.addPath(badgePath.cgPath)
            context.fillPath()

            let image = UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            )
            image?.withTintColor(UIColor.secondaryLabel, renderingMode: UIImage.RenderingMode.alwaysOriginal)
                .draw(in: badgeRect.insetBy(dx: 5.5, dy: 5.5))

            badgeOrigin.x -= DeckGridCardMetrics.mediaBadgeSize + UIConstants.Spacing.tiny
        }
    }

    private static func drawBottomOverlay(in context: CGContext, rect: CGRect, isDarkMode: Bool) {
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.clear.cgColor,
                UIColor.secondarySystemGroupedBackground.withAlphaComponent(isDarkMode ? 0.16 : 0.05).cgColor,
                UIColor.secondarySystemGroupedBackground.withAlphaComponent(isDarkMode ? 0.42 : 0.12).cgColor
            ] as CFArray,
            locations: [0, 0.5, 1]
        )

        guard let gradient else { return }
        let overlayRect = CGRect(
            x: rect.minX,
            y: rect.maxY - DeckGridCardMetrics.bottomBlurHeight,
            width: rect.width,
            height: DeckGridCardMetrics.bottomBlurHeight
        )
        let path = UIBezierPath(
            roundedRect: rect,
            cornerRadius: UIConstants.Radius.large
        )

        context.saveGState()
        path.addClip()
        context.clip(to: overlayRect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: overlayRect.midX, y: overlayRect.minY),
            end: CGPoint(x: overlayRect.midX, y: overlayRect.maxY),
            options: []
        )
        context.restoreGState()
    }

    private static func drawText(_ text: NSAttributedString, in rect: CGRect, lineLimit: Int) {
        let mutable = NSMutableAttributedString(attributedString: text)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        mutable.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: mutable.length)
        )
        let drawingRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height
        )
        let options: NSStringDrawingOptions = [
            .usesLineFragmentOrigin,
            .usesFontLeading,
            .truncatesLastVisibleLine
        ]
        mutable.draw(with: drawingRect, options: options, context: nil)
    }

    private static func drawPlaceholderBars(in context: CGContext, rect: CGRect, isDarkMode: Bool) {
        let barColor = UIColor.label.withAlphaComponent(isDarkMode ? 0.12 : 0.07)
        let barRects = [
            CGRect(x: DeckGridCardMetrics.sideInset, y: 36, width: rect.width * 0.48, height: 18),
            CGRect(x: DeckGridCardMetrics.sideInset, y: 62, width: rect.width * 0.62, height: 14),
            CGRect(x: DeckGridCardMetrics.sideInset, y: 108, width: rect.width * 0.36, height: 10)
        ]

        context.setFillColor(barColor.cgColor)
        for bar in barRects {
            let path = UIBezierPath(roundedRect: bar, cornerRadius: 7)
            context.addPath(path.cgPath)
            context.fillPath()
        }
    }

    private static func contentPlan(
        for descriptor: DeckCardSurfaceDescriptor,
        cardWidth: CGFloat,
        hasFooterVisual: Bool
    ) -> CardContentPlan {
        let frontText = normalizedPreviewText(descriptor.frontPreviewText)
        let backText = normalizedPreviewText(descriptor.backPreviewText)
        let hasQuestionText = !frontText.isEmpty
        let hasAnswerText = !backText.isEmpty
        let primaryText = hasQuestionText ? frontText : backText
        let primaryTextCharacterCount = primaryText.replacingOccurrences(of: "\n", with: " ").count

        let density: DeckGridCardContentDensity
        if primaryTextCharacterCount <= 42 && !primaryText.contains("\n") {
            density = .short
        } else if primaryTextCharacterCount >= 110 || primaryText.contains("\n") {
            density = .dense
        } else {
            density = .standard
        }

        let questionLineLimit: Int
        if !hasQuestionText {
            questionLineLimit = 5
        } else if !hasAnswerText {
            questionLineLimit = density == .dense ? 6 : 5
        } else {
            switch density {
            case .short:
                questionLineLimit = 3
            case .standard:
                questionLineLimit = 4
            case .dense:
                questionLineLimit = 5
            }
        }

        let questionMaxHeight: CGFloat
        if !hasQuestionText && hasAnswerText {
            questionMaxHeight = 112
        } else if !hasAnswerText {
            questionMaxHeight = 118
        } else {
            switch density {
            case .short:
                questionMaxHeight = 58
            case .standard:
                questionMaxHeight = 80
            case .dense:
                questionMaxHeight = 98
            }
        }

        let answerLineLimit: Int
        switch density {
        case .short:
            answerLineLimit = 4
        case .standard:
            answerLineLimit = 3
        case .dense:
            answerLineLimit = 2
        }

        let answerMaxHeight: CGFloat
        switch density {
        case .short:
            answerMaxHeight = 60
        case .standard:
            answerMaxHeight = 48
        case .dense:
            answerMaxHeight = 38
        }

        let availableWidth = max(0, cardWidth - (DeckGridCardMetrics.sideInset * 2))
        let answerTrailingInset = hasFooterVisual ? DeckGridCardMetrics.mediaInsetCompensation : 0

        if hasQuestionText {
            return CardContentPlan(
                questionFallbackText: frontText,
                questionRichText: descriptor.frontText,
                questionNeedsRichPreview: descriptor.frontNeedsRichSnapshot,
                questionFontSize: 16.5,
                questionLineLimit: questionLineLimit,
                questionMaxHeight: questionMaxHeight,
                questionSide: .front,
                answerFallbackText: backText,
                answerRichText: descriptor.backText,
                answerNeedsRichPreview: descriptor.backNeedsRichSnapshot,
                answerFontSize: 13.5,
                answerLineLimit: answerLineLimit,
                answerMaxHeight: answerMaxHeight,
                questionWidth: availableWidth,
                answerWidth: max(0, availableWidth - answerTrailingInset),
                hasSecondaryZone: hasAnswerText
            )
        }

        return CardContentPlan(
            questionFallbackText: backText,
            questionRichText: descriptor.backText,
            questionNeedsRichPreview: descriptor.backNeedsRichSnapshot,
            questionFontSize: 15.5,
            questionLineLimit: 5,
            questionMaxHeight: 112,
            questionSide: .back,
            answerFallbackText: "",
            answerRichText: "",
            answerNeedsRichPreview: false,
            answerFontSize: 13.5,
            answerLineLimit: 0,
            answerMaxHeight: 0,
            questionWidth: availableWidth,
            answerWidth: availableWidth,
            hasSecondaryZone: false
        )
    }

    private static func normalizedPreviewText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.caseInsensitiveCompare("empty") == .orderedSame ? "" : trimmed
    }

    private static func statusUIColor(for descriptor: DeckCardSurfaceDescriptor) -> UIColor {
        if descriptor.reviewHistoryIsEmpty { return .systemBlue }
        if descriptor.interval == 0 { return .systemRed }
        if descriptor.interval >= 14 { return .systemTeal }
        return .systemOrange
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
    }
}

private struct CardContentPlan {
    let questionFallbackText: String
    let questionRichText: String
    let questionNeedsRichPreview: Bool
    let questionFontSize: CGFloat
    let questionLineLimit: Int
    let questionMaxHeight: CGFloat
    let questionSide: DeckGridRichPreviewSide
    let answerFallbackText: String
    let answerRichText: String
    let answerNeedsRichPreview: Bool
    let answerFontSize: CGFloat
    let answerLineLimit: Int
    let answerMaxHeight: CGFloat
    let questionWidth: CGFloat
    let answerWidth: CGFloat
    let hasSecondaryZone: Bool
}

// =============================================================================
// MARK: - Fallback Text Builder
// =============================================================================

enum DeckGridFormattedFallbackBuilder {
    private enum Segment {
        case plain(String)
        case strong(String)
        case code(String)
    }

    static func make(
        text: String,
        fontSize: CGFloat,
        textColor: UIColor,
        isDarkMode: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let segments = parse(text)

        for segment in segments {
            let fragment: NSAttributedString

            switch segment {
            case .plain(let value):
                fragment = NSAttributedString(
                    string: value,
                    attributes: baseAttributes(fontSize: fontSize, textColor: textColor)
                )

            case .strong(let value):
                fragment = NSAttributedString(
                    string: value,
                    attributes: strongAttributes(fontSize: fontSize, textColor: textColor)
                )

            case .code(let value):
                fragment = NSAttributedString(
                    string: MathTextSanitizer.normalizedCodeLiteral(value),
                    attributes: codeAttributes(
                        fontSize: fontSize,
                        textColor: textColor,
                        isDarkMode: isDarkMode
                    )
                )
            }

            result.append(fragment)
        }

        if result.length == 0 {
            return NSAttributedString(
                string: text,
                attributes: baseAttributes(fontSize: fontSize, textColor: textColor)
            )
        }

        return result
    }

    private static func parse(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var buffer = ""
        var cursor = text.startIndex

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            segments.append(.plain(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        while cursor < text.endIndex {
            if text[cursor] == "`",
               let closing = text[text.index(after: cursor)...].firstIndex(of: "`") {
                flushBuffer()
                let inner = String(text[text.index(after: cursor)..<closing])
                segments.append(.code(inner))
                cursor = text.index(after: closing)
                continue
            }

            if text[cursor...].hasPrefix("**") {
                let contentStart = text.index(cursor, offsetBy: 2)
                if let closing = text[contentStart...].range(of: "**") {
                    flushBuffer()
                    let inner = String(text[contentStart..<closing.lowerBound])
                    segments.append(.strong(inner))
                    cursor = closing.upperBound
                    continue
                }
            }

            buffer.append(text[cursor])
            cursor = text.index(after: cursor)
        }

        flushBuffer()
        return segments
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func paragraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    private static func baseAttributes(fontSize: CGFloat, textColor: UIColor) -> [NSAttributedString.Key: Any] {
        [
            .font: roundedFont(size: fontSize, weight: .regular),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle()
        ]
    }

    private static func strongAttributes(fontSize: CGFloat, textColor: UIColor) -> [NSAttributedString.Key: Any] {
        [
            .font: roundedFont(size: fontSize, weight: .bold),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle()
        ]
    }

    private static func codeAttributes(
        fontSize: CGFloat,
        textColor: UIColor,
        isDarkMode: Bool
    ) -> [NSAttributedString.Key: Any] {
        let background = isDarkMode
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.06)
        let foreground = isDarkMode
            ? UIColor.white.withAlphaComponent(0.94)
            : textColor.withAlphaComponent(0.9)

        return [
            .font: UIFont.monospacedSystemFont(ofSize: max(11, fontSize * 0.9), weight: .semibold),
            .foregroundColor: foreground,
            .backgroundColor: background,
            .paragraphStyle: paragraphStyle()
        ]
    }
}

// =============================================================================
// MARK: - HTML Builder
// =============================================================================

private enum DeckGridRichPreviewHTML {
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
                overflow: hidden;
                padding: 4px 0;
            }
            .katex { font-size: 1.05em !important; }
            .katex-error {
                color: inherit !important;
                font-style: normal !important;
                font-family: -apple-system, sans-serif !important;
            }
            code.inline-code {
                font-family: ui-monospace, 'SF Mono', Menlo, monospace;
                font-size: 0.9em;
            }
            code.inline-code--deck-card-preview {
                display: inline-block;
                background: var(--inline-code-bg);
                color: var(--inline-code-fg);
                border: 1px solid var(--inline-code-border);
                border-radius: 7px;
                padding: 0.08em 0.34em 0.02em;
                white-space: pre-wrap;
                font-size: 0.92em;
                font-weight: 600;
                letter-spacing: -0.01em;
            }
            strong, b { font-weight: bold; }
            em, i     { font-style: italic; }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
        const extraMacros = {
            "\\\\thinspace": "\\\\,",
            "\\\\negthinspace": "\\\\!",
            "\\\\medspace": "\\\\:",
            "\\\\thickspace": "\\\\;",
            "\\\\R": "\\\\mathbb{R}",
            "\\\\N": "\\\\mathbb{N}",
            "\\\\Z": "\\\\mathbb{Z}",
            "\\\\Q": "\\\\mathbb{Q}",
            "\\\\C": "\\\\mathbb{C}",
            "\\\\eps": "\\\\varepsilon",
            "\\\\epsilon": "\\\\varepsilon"
        };

        var updateTimeout = null;

        function updateMathContent(b64, color, fontSize, align, weight, fontStyle, inlineCodeBackground, inlineCodeBorder, inlineCodeForeground) {
            document.body.style.color = color;
            document.body.style.fontSize = fontSize + 'px';
            document.body.style.textAlign = align;
            document.body.style.fontWeight = weight;
            document.body.style.fontStyle = fontStyle;
            document.documentElement.style.setProperty('--inline-code-bg', inlineCodeBackground);
            document.documentElement.style.setProperty('--inline-code-border', inlineCodeBorder);
            document.documentElement.style.setProperty('--inline-code-fg', inlineCodeForeground);

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
                        { left: '$$', right: '$$', display: true },
                        { left: '\\\\[', right: '\\\\]', display: true },
                        { left: '$', right: '$', display: false },
                        { left: '\\\\(', right: '\\\\)', display: false }
                    ],
                    ignoredTags: ["script", "noscript", "style", "textarea", "pre", "option"],
                    throwOnError: false,
                    errorColor: 'inherit',
                    macros: extraMacros
                });
            } catch(e) { console.error(e); }

            clearTimeout(updateTimeout);
            updateTimeout = setTimeout(() => {}, 0);
        }
        </script>
        </body>
        </html>
        """
    }

    static func updateScript(for request: DeckGridRichPreviewRequest) -> String? {
        let finalText = processMarkup(request.text)
        guard let encoded = finalText.data(using: .utf8)?.base64EncodedString() else { return nil }

        return """
        updateMathContent(
            '\(encoded)',
            '\(request.tone.cssColor(for: request.isDarkMode))',
            \(request.fontSize),
            'left',
            'normal',
            'normal',
            '\(inlineCodeBackground(for: request.isDarkMode))',
            '\(inlineCodeBorder(for: request.isDarkMode))',
            '\(inlineCodeForeground(for: request.isDarkMode))'
        );
        """
    }

    private static func inlineCodeBackground(for isDarkMode: Bool) -> String {
        isDarkMode ? "rgba(255,255,255,0.085)" : "rgba(17,24,39,0.065)"
    }

    private static func inlineCodeBorder(for isDarkMode: Bool) -> String {
        isDarkMode ? "rgba(255,255,255,0.11)" : "rgba(17,24,39,0.08)"
    }

    private static func inlineCodeForeground(for isDarkMode: Bool) -> String {
        isDarkMode ? "rgba(255,255,255,0.94)" : "rgba(17,24,39,0.88)"
    }

    private static func processMarkup(_ text: String) -> String {
        var html = ""
        var plainBuffer = ""
        var cursor = text.startIndex

        func flushPlainBuffer() {
            guard !plainBuffer.isEmpty else { return }
            html += processBoldMarkup(in: plainBuffer)
            plainBuffer.removeAll(keepingCapacity: true)
        }

        while cursor < text.endIndex {
            if text[cursor] == "`",
               let closing = text[text.index(after: cursor)...].firstIndex(of: "`") {
                flushPlainBuffer()
                let innerRange = text.index(after: cursor)..<closing
                let inner = MathTextSanitizer.normalizedCodeLiteral(String(text[innerRange]))
                html += "<code class=\"inline-code inline-code--deck-card-preview\">\(htmlEscaped(inner))</code>"
                cursor = text.index(after: closing)
                continue
            }

            plainBuffer.append(text[cursor])
            cursor = text.index(after: cursor)
        }

        flushPlainBuffer()
        return html
    }

    private static func processBoldMarkup(in text: String) -> String {
        var html = ""
        var cursor = text.startIndex

        while cursor < text.endIndex {
            if text[cursor...].hasPrefix("**") {
                let contentStart = text.index(cursor, offsetBy: 2)
                if let closing = text[contentStart...].range(of: "**") {
                    let inner = String(text[contentStart..<closing.lowerBound])
                    html += "<strong>\(htmlEscaped(inner))</strong>"
                    cursor = closing.upperBound
                    continue
                }
            }

            html += htmlEscaped(String(text[cursor]))
            cursor = text.index(after: cursor)
        }

        return html
    }

    private static func htmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func katexBundleURLs() -> (js: String, css: String, autoRender: String)? {
        guard
            let js = Bundle.main.url(forResource: "katex.min", withExtension: "js"),
            let css = Bundle.main.url(forResource: "katex.min", withExtension: "css"),
            let autoRender = Bundle.main.url(forResource: "auto-render.min", withExtension: "js")
        else { return nil }
        return (js.absoluteString, css.absoluteString, autoRender.absoluteString)
    }
}
