//
//  DeckGridRichPreviewRenderer.swift
//  QuizFlash
//
//  Serial rich-preview snapshot renderer for the deck grid.
//

import SwiftUI
import SwiftData
import UIKit
import WebKit

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

    func cssColor(for colorScheme: ColorScheme) -> String {
        switch self {
        case .question:
            return colorScheme == .dark ? "#FFFFFF" : "#000000"
        case .answer:
            return colorScheme == .dark
                ? "rgba(255,255,255,0.84)"
                : "rgba(0,0,0,0.62)"
        }
    }
}

struct DeckGridRichPreviewRequest: Hashable, Sendable {
    let cardID: PersistentIdentifier
    let editedAt: Date
    let side: DeckGridRichPreviewSide
    let text: String
    let width: CGFloat
    let maxHeight: CGFloat
    let fontSize: CGFloat
    let tone: DeckGridRichPreviewTone
    let colorScheme: ColorScheme

    var cacheKey: NSString {
        let widthSignature = Int((width * UIScreen.main.scale).rounded())
        let heightSignature = Int((maxHeight * UIScreen.main.scale).rounded())
        let timeSignature = Int(editedAt.timeIntervalSinceReferenceDate * 1000)
        return [
            "\(cardID.hashValue)",
            "\(timeSignature)",
            side.rawValue,
            "\(widthSignature)",
            "\(heightSignature)",
            String(format: "%.2f", fontSize),
            tone.rawValue,
            colorScheme == .dark ? "dark" : "light"
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
        cache.countLimit = 240
        cache.totalCostLimit = 30 * 1024 * 1024
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
// MARK: - Renderer
// =============================================================================

actor DeckGridRichPreviewGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            isLocked = false
        }
    }
}

@MainActor
final class DeckGridRichPreviewRenderer: NSObject, WKNavigationDelegate {
    static let shared = DeckGridRichPreviewRenderer()

    private let gate = DeckGridRichPreviewGate()
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
        if let cached = DeckGridRichPreviewCache.shared.image(for: request) {
            return cached
        }

        let expectedGeneration = generation
        await gate.acquire()
        defer {
            Task {
                await gate.release()
            }
        }

        guard !Task.isCancelled, expectedGeneration == generation else { return nil }
        guard await ensureTemplateLoaded(expectedGeneration: expectedGeneration) else { return nil }
        guard !Task.isCancelled, expectedGeneration == generation else { return nil }
        guard let script = DeckGridRichPreviewHTML.updateScript(for: request) else { return nil }
        guard await evaluateWhenReady(script, expectedGeneration: expectedGeneration) else { return nil }
        guard !Task.isCancelled, expectedGeneration == generation else { return nil }

        try? await Task.sleep(nanoseconds: 45_000_000)
        let measuredHeight = await measureHeight(expectedGeneration: expectedGeneration)
        let snapshotHeight = min(max(1, measuredHeight), request.maxHeight)
        guard snapshotHeight > 1 else { return nil }

        webView.frame = CGRect(origin: .zero, size: CGSize(width: request.width, height: snapshotHeight))
        webView.layoutIfNeeded()

        guard let snapshot = await takeSnapshot(size: webView.bounds.size),
              expectedGeneration == generation,
              !Task.isCancelled else { return nil }

        DeckGridRichPreviewCache.shared.store(snapshot, for: request)
        return snapshot
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
        DeckGridRichPreviewCache.shared.flush()
    }

    // MARK: - WKNavigationDelegate

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

    // MARK: - Internals

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
        try? await Task.sleep(nanoseconds: 35_000_000)
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

    private func takeSnapshot(size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(origin: .zero, size: size)
            configuration.afterScreenUpdates = true
            webView.takeSnapshot(with: configuration) { image, _ in
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

// =============================================================================
// MARK: - HTML Builder
// =============================================================================

private enum DeckGridRichPreviewHTML {
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
        \(MathTextSanitizer.katexExtraMacrosJSObjectLiteral)
        };

        let updateTimeout;

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
            '\(request.tone.cssColor(for: request.colorScheme))',
            \(request.fontSize),
            'left',
            'normal',
            'normal',
            '\(inlineCodeBackground(for: request.colorScheme))',
            '\(inlineCodeBorder(for: request.colorScheme))',
            '\(inlineCodeForeground(for: request.colorScheme))'
        );
        """
    }

    private static func inlineCodeBackground(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? "rgba(255,255,255,0.085)" : "rgba(17,24,39,0.065)"
    }

    private static func inlineCodeBorder(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? "rgba(255,255,255,0.11)" : "rgba(17,24,39,0.08)"
    }

    private static func inlineCodeForeground(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? "rgba(255,255,255,0.94)" : "rgba(17,24,39,0.88)"
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

}
