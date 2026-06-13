//
//  ZoneTextView.swift
//  QuizFlash
//

import SwiftUI
import UIKit
import Observation
import Foundation

private enum ZoneTextViewEmptyCaret {
    static let placeholder = "\u{200B}"

    static func displayText(for modelText: String) -> String {
        modelText.isEmpty ? placeholder : modelText
    }

    static func modelText(from displayText: String) -> String {
        displayText.replacingOccurrences(of: placeholder, with: "")
    }

    static func isPlaceholderDisplay(_ displayText: String?) -> Bool {
        displayText == placeholder
    }

    static func modelRange(from displayRange: NSRange, displayText: String) -> NSRange {
        guard !isPlaceholderDisplay(displayText) else {
            return NSRange(location: 0, length: 0)
        }

        let nsText = displayText as NSString
        let clampedLocation = min(max(displayRange.location, 0), nsText.length)
        let clampedEnd = min(max(displayRange.location + displayRange.length, clampedLocation), nsText.length)
        let prefix = nsText.substring(to: clampedLocation)
        let selectedText = nsText.substring(with: NSRange(location: clampedLocation, length: clampedEnd - clampedLocation))
        let placeholdersBefore = placeholderCount(in: prefix)
        let placeholdersInSelection = placeholderCount(in: selectedText)

        return NSRange(
            location: max(clampedLocation - placeholdersBefore, 0),
            length: max((clampedEnd - clampedLocation) - placeholdersInSelection, 0)
        )
    }

    static func displayRange(fromModelRange range: NSRange, modelText: String) -> NSRange {
        modelText.isEmpty ? NSRange(location: 0, length: 0) : range
    }

    private static func placeholderCount(in text: String) -> Int {
        text.components(separatedBy: placeholder).count - 1
    }
}

// MARK: - Full Hit Text View
/// Custom UITextView that keeps selection stable inside the editor surface.
final class FullHitTextView: UITextView {
    var usesCompactCaret: Bool = true

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        guard usesCompactCaret else { return rect }

        rect.size.width = 2.1
        return rect
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.bounds.contains(point) {
            return self
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Zone Editor Debug Store

@MainActor
final class ZoneEditorDebugStore {
    static let shared = ZoneEditorDebugStore()

    private(set) var eventIndex: Int = 0
    private(set) var lastEvent: String = "idle"
    private(set) var focusLine: String = "focus idle"
    private(set) var textViewLine: String = "textview idle"
    private(set) var selectedZoneLine: String = "zone idle"
    private(set) var selectedLayoutLine: String = "layout idle"
    private(set) var canvasLine: String = "canvas idle"
    private(set) var toolbarLine: String = "toolbar idle"
    private(set) var tapLine: String = "tap idle"
    private(set) var alignmentLine: String = "align idle"
    private(set) var caretLine: String = "caret idle"

    private init() { }

    var hudLines: [String] {
        [
            "#\(eventIndex) \(lastEvent)",
            focusLine,
            textViewLine,
            selectedZoneLine,
            selectedLayoutLine,
            canvasLine,
            toolbarLine,
            tapLine,
            alignmentLine,
            caretLine
        ]
    }

    func recordEvent(_ value: String) {
        eventIndex += 1
        lastEvent = value
    }

    func updateFocusManager(focusedZoneID: UUID?, pendingZoneID: UUID?, retainKeyboard: Bool) {
        setLine(
            &focusLine,
            "focus manager focused=\(shortID(focusedZoneID)) pending=\(shortID(pendingZoneID)) retain=\(retainKeyboard ? "1" : "0")"
        )
    }

    func updateTextView(
        zoneID: UUID?,
        mountedFocused: Bool,
        textViewFirstResponder: Bool,
        uiViewFirstResponder: Bool,
        requestedFirstResponder: Bool,
        textLength: Int
    ) {
        setLine(
            &textViewLine,
            "text mounted=\(flag(mountedFocused)) swiftFR=\(flag(textViewFirstResponder)) uiFR=\(flag(uiViewFirstResponder)) request=\(flag(requestedFirstResponder)) len=\(textLength) zone=\(shortID(zoneID))"
        )
    }

    func updateSelectedZone(
        pathID: String,
        zoneID: UUID?,
        contentType: String,
        sizeMode: String,
        blockAlignment: String,
        textAlignment: String,
        verticalAlignment: String,
        fixedWidth: CGFloat?,
        fixedHeight: CGFloat?
    ) {
        setLine(
            &selectedZoneLine,
            "zone path=\(pathID) id=\(shortID(zoneID)) type=\(contentType) size=\(sizeMode) block=\(blockAlignment) text=\(textAlignment) y=\(verticalAlignment) fixed=\(format(fixedWidth))x\(format(fixedHeight))"
        )
    }

    func updateSelectedLayout(
        blockSize: CGSize,
        contentWidth: CGFloat,
        leadingInset: CGFloat,
        renderedSize: CGSize,
        isSelected: Bool
    ) {
        setLine(
            &selectedLayoutLine,
            "layout block=\(format(blockSize.width))x\(format(blockSize.height)) contentW=\(format(contentWidth)) lead=\(format(leadingInset)) measured=\(format(renderedSize.width))x\(format(renderedSize.height)) selected=\(flag(isSelected))"
        )
    }

    func updateCanvas(
        cardSize: CGSize,
        contentSize: CGSize,
        scrollOffsetY: CGFloat,
        contentTopInset: CGFloat,
        contentBodyHeight: CGFloat,
        scrollContentHeight: CGFloat,
        selectedPathID: String?,
        selectedFrame: CGRect?,
        resolvedFrameCount: Int,
        keyboardVisible: Bool,
        keyboardHeight: CGFloat
    ) {
        let frameText: String
        if let selectedFrame {
            frameText = "\(format(selectedFrame.width))x\(format(selectedFrame.height)) @\(format(selectedFrame.minX)),\(format(selectedFrame.minY))"
        } else {
            frameText = "nil"
        }
        setLine(
            &canvasLine,
            "canvas offset=\(format(scrollOffsetY)) top=\(format(contentTopInset)) body=\(format(contentBodyHeight)) scroll=\(format(scrollContentHeight)) card=\(format(cardSize.width))x\(format(cardSize.height)) content=\(format(contentSize.width))x\(format(contentSize.height)) selected=\(selectedPathID ?? "nil") frames=\(resolvedFrameCount) frame=\(frameText) keyboard=\(flag(keyboardVisible)):\(format(keyboardHeight))"
        )
    }

    func updateToolbar(
        isVisible: Bool,
        keyboardHeight: CGFloat,
        toolbarTopY: CGFloat?,
        toolbarScale: CGFloat,
        toolbarOpacity: Double,
        topUpdateCount: Int
    ) {
        setLine(
            &toolbarLine,
            "toolbar vis=\(flag(isVisible)) kb=\(format(keyboardHeight)) top=\(format(toolbarTopY)) scale=\(format(toolbarScale)) op=\(format(CGFloat(toolbarOpacity))) topUpdates=\(topUpdateCount)"
        )
    }

    func recordTap(_ value: String) {
        setLine(&tapLine, value)
        recordEvent(value)
    }

    func recordAlignment(_ value: String) {
        setLine(&alignmentLine, value)
        recordEvent(value)
    }

    func recordFocusEvent(_ value: String, zoneID: UUID?) {
        setLine(&focusLine, "\(value) zone=\(shortID(zoneID))")
        recordEvent(value)
    }

    func recordCaret(zoneID: UUID?, selectedRange: NSRange, anchorY: CGFloat, windowRect: CGRect) {
        setLine(
            &caretLine,
            "caret zone=\(shortID(zoneID)) loc=\(selectedRange.location) len=\(selectedRange.length) anchorY=\(format(anchorY)) windowY=\(format(windowRect.maxY))"
        )
    }

    private func setLine(_ storage: inout String, _ value: String) {
        guard storage != value else { return }
        storage = value
    }

    private func shortID(_ id: UUID?) -> String {
        guard let id else { return "nil" }
        return String(id.uuidString.prefix(6))
    }

    private func flag(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private func format(_ value: CGFloat?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.0f", Double(value))
    }
}

// MARK: - Zone Text View Coordinator

final class ZoneTextViewCoordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    var zoneID: UUID?
    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((NSRange, String) -> Void)?
    var onFocusLineChange: ((Int, Int) -> Void)?
    var onCaretGeometryChange: ((CGFloat, CGRect) -> Void)?
    var onCommit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var lineSpacing: CGFloat = 0
    var contentInset: UIEdgeInsets = .zero
    var maximumVisibleHeight: CGFloat?
    var forcedLineBreakTintColor: UIColor = .systemPurple
    fileprivate var lastAppliedStylingSignature: ZoneTextViewStylingSignature?
    
    private var lastText: String = ""
    private var lastAcceptedText: String = ""
    private var lastAcceptedSelectedRange: NSRange = NSRange(location: 0, length: 0)
    var isUpdating: Bool = false
    weak var textView: UITextView?
    private var focusObserver: NSObjectProtocol?
    private var forcedLineBreakObserver: NSObjectProtocol?
    private var lastReportedCursorRange: NSRange?
    private var lastReportedText: String?
    private var lastReportedLineInfo: (zoneID: UUID?, lineIndex: Int, totalLines: Int)?
    private var lastReportedCaretAnchorY: CGFloat?
    private var lastReportedCaretWindowRect: CGRect?
    private var caretReportGeneration = 0
    private var waitsForSettledTextLayoutCaret = false
    fileprivate var focusSyncState: FocusSyncState = .idle
    
    override init() {
        super.init()
        focusObserver = NotificationCenter.default.addObserver(
            forName: .focusZoneTextView,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let zoneID = notification.object as? UUID,
               let self = self,
               self.zoneID == zoneID {
                if !(self.textView?.isFirstResponder ?? false) {
                    self.postWillFocusNotification(for: zoneID)
                    let didFocus = self.textView?.becomeFirstResponder() ?? false
                    if !didFocus {
                        Task { @MainActor in
                            ZoneEditorDebugStore.shared.recordFocusEvent("focus notification failed", zoneID: zoneID)
                        }
                        self.onFocusChange?(false)
                        return
                    }
                    Task { @MainActor in
                        ZoneEditorDebugStore.shared.recordFocusEvent("focus notification becameFR", zoneID: zoneID)
                        ZoneFocusManager.shared.completeFocus(for: zoneID)
                    }
                } else {
                    Task { @MainActor in
                        ZoneEditorDebugStore.shared.recordFocusEvent("focus notification alreadyFR", zoneID: zoneID)
                        ZoneFocusManager.shared.completeFocus(for: zoneID)
                    }
                }
            }
        }
        forcedLineBreakObserver = NotificationCenter.default.addObserver(
            forName: .zoneEditorInsertForcedLineBreak,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let targetZoneID = notification.object as? UUID,
                  self.zoneID == targetZoneID,
                  let textView = self.textView else {
                return
            }

            self.insertForcedLineBreak(in: textView)
        }
    }
    
    deinit {
        caretReportGeneration += 1
        if let observer = focusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = forcedLineBreakObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer.name != Self.doubleTapPassthroughRecognizerName else {
            return true
        }

        guard gestureRecognizer.name == Self.selectionCollapseTapRecognizerName,
              let textView,
              textView.selectedRange.length > 0 else {
            return false
        }

        return textView.bounds.contains(touch.location(in: textView))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc func handleSelectionCollapseTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let textView,
              textView.selectedRange.length > 0 else {
            return
        }

        placeCaret(at: recognizer.location(in: textView), in: textView)
    }

    static let selectionCollapseTapRecognizerName = "ZoneTextViewSelectionCollapseTapRecognizer"
    static let doubleTapPassthroughRecognizerName = "ZoneTextViewDoubleTapPassthroughRecognizer"

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        if let zoneID {
            postWillFocusNotification(for: zoneID)
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        normalizePlaceholderIfNeeded(in: textView)
        guard let displayText = textView.text else { return }
        guard !isUpdating else { return }

        let modelText = ZoneTextViewEmptyCaret.modelText(from: displayText)
        if shouldRejectCurrentText(modelText, in: textView) {
            restoreLastAcceptedText(in: textView)
            reportCursorPosition(from: textView, includeCaretAnchor: true, forceCaretGeometry: true)
            return
        }

        lastText = modelText
        rememberAcceptedText(modelText, selectedRange: textView.selectedRange)
        waitsForSettledTextLayoutCaret = true
        onTextChange?(modelText)
        reportCursorPosition(from: textView, includeCaretAnchor: false)
        scheduleSettledCaretReport(from: textView)
    }
    
    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isUpdating else { return }
        guard textView.isFirstResponder else { return }

        guard !waitsForSettledTextLayoutCaret else {
            reportCursorPosition(from: textView, includeCaretAnchor: false)
            scheduleSettledCaretReport(from: textView)
            return
        }

        reportCursorPosition(from: textView, includeCaretAnchor: true)
        scheduleSettledCaretReport(from: textView)
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        focusSyncState = .idle
        ZoneEditorDebugStore.shared.recordFocusEvent("textView didBegin", zoneID: zoneID)
        if let zoneID {
            Task { @MainActor in
                ZoneFocusManager.shared.completeFocus(for: zoneID)
            }
        }
        onFocusChange?(true)
        rememberAcceptedText(
            ZoneTextViewEmptyCaret.modelText(from: textView.text ?? ""),
            selectedRange: textView.selectedRange
        )
        reportCursorPosition(from: textView, includeCaretAnchor: true)
        scheduleSettledCaretReport(from: textView)
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        focusSyncState = .idle
        ZoneEditorDebugStore.shared.recordFocusEvent("textView didEnd", zoneID: zoneID)
        onFocusChange?(false)
    }

    private func postWillFocusNotification(for zoneID: UUID) {
        NotificationCenter.default.post(
            name: .zoneEditorWillFocusTextView,
            object: zoneID
        )
    }
    
    private func reportCursorPosition(
        from textView: UITextView,
        includeCaretAnchor: Bool,
        forceCaretGeometry: Bool = false
    ) {
        guard let displayText = textView.text else { return }
        let text = ZoneTextViewEmptyCaret.modelText(from: displayText)
        let nsRange = ZoneTextViewEmptyCaret.modelRange(
            from: textView.selectedRange,
            displayText: displayText
        )
        if lastReportedCursorRange != nsRange || lastReportedText != text {
            lastReportedCursorRange = nsRange
            lastReportedText = text
            onCursorChange?(nsRange, text)
        }

        let (focusedLineIndex, totalLines) = calculateLineInfo(from: text, location: nsRange.location)
        if lastReportedLineInfo?.zoneID != zoneID
            || lastReportedLineInfo?.lineIndex != focusedLineIndex
            || lastReportedLineInfo?.totalLines != totalLines {
            lastReportedLineInfo = (zoneID, focusedLineIndex, totalLines)
            onFocusLineChange?(focusedLineIndex, totalLines)
        }

        guard includeCaretAnchor else { return }
        guard textView.window != nil else { return }

        if let selectedTextRange = textView.selectedTextRange {
            textView.layoutIfNeeded()
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            let caretRect = textView.caretRect(for: selectedTextRange.start)
            let caretRectInWindow = textView.convert(caretRect, to: nil)
            let anchorY = min(
                max(caretRect.midY / max(textView.bounds.height, 1), 0.08),
                0.92
            )
            if !forceCaretGeometry,
               let lastReportedCaretAnchorY,
               let lastReportedCaretWindowRect,
               abs(lastReportedCaretAnchorY - anchorY) < 0.02,
               lastReportedCaretWindowRect.isNearlyEqual(to: caretRectInWindow, tolerance: 1) {
                return
            }

            lastReportedCaretAnchorY = anchorY
            lastReportedCaretWindowRect = caretRectInWindow
            ZoneEditorDebugStore.shared.recordCaret(
                zoneID: zoneID,
                selectedRange: nsRange,
                anchorY: anchorY,
                windowRect: caretRectInWindow
            )
            onCaretGeometryChange?(anchorY, caretRectInWindow)
        }
    }

    func rememberAcceptedText(_ modelText: String, selectedRange: NSRange) {
        lastAcceptedText = modelText
        lastAcceptedSelectedRange = ZoneTextViewEmptyCaret.modelRange(
            from: selectedRange,
            displayText: ZoneTextViewEmptyCaret.displayText(for: modelText)
        )
        lastText = modelText
    }

    private func normalizePlaceholderIfNeeded(in textView: UITextView) {
        guard let displayText = textView.text,
              !ZoneTextViewEmptyCaret.isPlaceholderDisplay(displayText),
              displayText.contains(ZoneTextViewEmptyCaret.placeholder) else {
            return
        }

        let originalRange = textView.selectedRange
        let modelText = ZoneTextViewEmptyCaret.modelText(from: displayText)
        let modelRange = ZoneTextViewEmptyCaret.modelRange(
            from: originalRange,
            displayText: displayText
        )

        isUpdating = true
        textView.text = ZoneTextViewEmptyCaret.displayText(for: modelText)
        isUpdating = false
        let displayRange = ZoneTextViewEmptyCaret.displayRange(
            fromModelRange: modelRange,
            modelText: modelText
        )
        if displayRange.location <= (textView.text as NSString).length {
            textView.selectedRange = displayRange
        }
    }

    private func shouldRejectCurrentText(_ modelText: String, in textView: UITextView) -> Bool {
        guard let maximumVisibleHeight,
              maximumVisibleHeight > 0,
              textView.bounds.width > 1,
              (modelText as NSString).length > (lastAcceptedText as NSString).length else {
            return false
        }

        textView.layoutIfNeeded()
        let targetSize = CGSize(
            width: textView.bounds.width,
            height: UIView.layoutFittingCompressedSize.height
        )
        let requiredHeight = ceil(textView.sizeThatFits(targetSize).height)
        return requiredHeight > ceil(maximumVisibleHeight) + 0.5
    }

    private func restoreLastAcceptedText(in textView: UITextView) {
        let displayText = ZoneTextViewEmptyCaret.displayText(for: lastAcceptedText)
        let displayRange = ZoneTextViewEmptyCaret.displayRange(
            fromModelRange: lastAcceptedSelectedRange,
            modelText: lastAcceptedText
        )

        isUpdating = true
        textView.text = displayText
        isUpdating = false

        if displayRange.location <= (displayText as NSString).length {
            textView.selectedRange = displayRange
        }
    }

    private func scheduleSettledCaretReport(from textView: UITextView) {
        guard textView.isFirstResponder else { return }
        caretReportGeneration += 1
        let generation = caretReportGeneration

        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self,
                  let textView,
                  self.caretReportGeneration == generation,
                  textView.window != nil else { return }

            textView.window?.layoutIfNeeded()
            textView.superview?.layoutIfNeeded()
            self.waitsForSettledTextLayoutCaret = false
            self.reportCursorPosition(
                from: textView,
                includeCaretAnchor: true,
                forceCaretGeometry: true
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak textView] in
                guard let self,
                      let textView,
                      self.caretReportGeneration == generation,
                      textView.window != nil else { return }

                textView.window?.layoutIfNeeded()
                textView.superview?.layoutIfNeeded()
                self.reportCursorPosition(
                    from: textView,
                    includeCaretAnchor: true,
                    forceCaretGeometry: true
                )
            }
        }
    }

    private func placeCaret(at point: CGPoint, in textView: UITextView) {
        guard let position = textView.closestPosition(to: point) else { return }

        let location = textView.offset(from: textView.beginningOfDocument, to: position)
        let textLength = ((textView.text ?? "") as NSString).length
        let clampedLocation = min(max(location, 0), textLength)
        let range = NSRange(location: clampedLocation, length: 0)
        textView.selectedRange = ZoneTextViewEmptyCaret.isPlaceholderDisplay(textView.text)
            ? NSRange(location: 0, length: 0)
            : range
        reportCursorPosition(from: textView, includeCaretAnchor: true)
        scheduleSettledCaretReport(from: textView)
    }

    private func insertForcedLineBreak(in textView: UITextView) {
        if let zoneID, !textView.isFirstResponder {
            postWillFocusNotification(for: zoneID)
            _ = textView.becomeFirstResponder()
            Task { @MainActor in
                ZoneFocusManager.shared.completeFocus(for: zoneID)
            }
        }

        let currentText = ZoneTextViewEmptyCaret.isPlaceholderDisplay(textView.text)
            ? ""
            : (textView.text ?? "")
        let textLength = (currentText as NSString).length
        let selectedRange = ZoneTextViewEmptyCaret.isPlaceholderDisplay(textView.text)
            ? NSRange(location: 0, length: 0)
            : NSRange(
                location: min(max(textView.selectedRange.location, 0), textLength),
                length: min(max(textView.selectedRange.length, 0), max(textLength - min(max(textView.selectedRange.location, 0), textLength), 0))
            )
        let mutable = NSMutableString(string: currentText)
        mutable.replaceCharacters(in: selectedRange, with: ZoneForcedLineBreak.marker)

        isUpdating = true
        textView.text = mutable as String
        textView.selectedRange = NSRange(
            location: selectedRange.location + (ZoneForcedLineBreak.marker as NSString).length,
            length: 0
        )
        isUpdating = false

        applyForcedLineBreakMarkerStyle(to: textView)
        textViewDidChange(textView)
        reportCursorPosition(from: textView, includeCaretAnchor: true, forceCaretGeometry: true)
    }
    
    private func calculateLineInfo(from text: String, location: Int) -> (lineIndex: Int, totalLines: Int) {
        let lines = ZoneForcedLineBreak.renderText(text).components(separatedBy: "\n")
        let totalLines = lines.count
        guard location >= 0 else { return (0, totalLines) }
        
        var currentIndex = 0
        for (index, line) in lines.enumerated() {
            let lineLength = (line as NSString).length + 1
            if location < currentIndex + lineLength { return (index, totalLines) }
            currentIndex += lineLength
        }
        return (max(0, totalLines - 1), totalLines)
    }

    func applyForcedLineBreakMarkerStyle(to textView: UITextView) {
        ZoneForcedLineBreak.applyMarkerStyle(
            to: textView.textStorage,
            baseAttributes: textAttributes,
            markerColor: forcedLineBreakTintColor
        )
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textView?.textAlignment ?? .left
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = max(lineSpacing, 0)

        return [
            .font: font,
            .foregroundColor: textView?.textColor ?? UIColor.label,
            .paragraphStyle: paragraphStyle
        ]
    }
}

// MARK: - Zone Text View Representable

struct ZoneTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    let font: UIFont
    let textColor: UIColor
    let textAlignment: NSTextAlignment
    let isBold: Bool
    let isItalic: Bool
    var lineSpacing: CGFloat = 0
    var contentInset: UIEdgeInsets = .zero
    var maximumVisibleHeight: CGFloat?
    var cursorTintColor: UIColor = .systemPurple
    var forcedLineBreakTintColor: UIColor = .systemPurple
    let zoneID: UUID
    let isFirstResponder: Bool
    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((NSRange, String) -> Void)?
    var onFocusLineChange: ((Int, Int) -> Void)?
    var onCaretGeometryChange: ((CGFloat, CGRect) -> Void)?
    var onCommit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    
    func makeUIView(context: Context) -> UITextView {
        // Use custom class that detects tap everywhere
        let textView = FullHitTextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.zoneID = zoneID
        context.coordinator.font = font
        context.coordinator.lineSpacing = lineSpacing
        context.coordinator.contentInset = contentInset
        context.coordinator.maximumVisibleHeight = maximumVisibleHeight
        context.coordinator.forcedLineBreakTintColor = forcedLineBreakTintColor
        
        textView.font = font
        textView.textColor = textColor
        textView.textAlignment = textAlignment
        textView.tintColor = cursorTintColor
        textView.backgroundColor = .clear
        textView.adjustsFontForContentSizeCategory = true
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.keyboardType = .default
        textView.returnKeyType = .default
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = contentInset
        textView.allowsEditingTextAttributes = false
        textView.usesCompactCaret = true
        
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let doubleTapRecognizer = UITapGestureRecognizer()
        doubleTapRecognizer.name = ZoneTextViewCoordinator.doubleTapPassthroughRecognizerName
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.cancelsTouchesInView = false
        doubleTapRecognizer.delegate = context.coordinator

        let selectionCollapseTapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(ZoneTextViewCoordinator.handleSelectionCollapseTap(_:))
        )
        selectionCollapseTapRecognizer.name = ZoneTextViewCoordinator.selectionCollapseTapRecognizerName
        selectionCollapseTapRecognizer.numberOfTapsRequired = 1
        selectionCollapseTapRecognizer.cancelsTouchesInView = false
        selectionCollapseTapRecognizer.delegate = context.coordinator
        selectionCollapseTapRecognizer.require(toFail: doubleTapRecognizer)

        textView.addGestureRecognizer(doubleTapRecognizer)
        textView.addGestureRecognizer(selectionCollapseTapRecognizer)

        textView.text = ZoneTextViewEmptyCaret.displayText(for: text)
        textView.selectedRange = ZoneTextViewEmptyCaret.displayRange(
            fromModelRange: textView.selectedRange,
            modelText: text
        )
        context.coordinator.rememberAcceptedText(text, selectedRange: textView.selectedRange)
        updateStyling(of: textView)
        context.coordinator.lastAppliedStylingSignature = stylingSignatureForCurrentState
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.zoneID = zoneID
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onFocusLineChange = onFocusLineChange
        context.coordinator.onCaretGeometryChange = onCaretGeometryChange
        context.coordinator.onCommit = onCommit
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.font = font
        context.coordinator.lineSpacing = lineSpacing
        context.coordinator.contentInset = contentInset
        context.coordinator.maximumVisibleHeight = maximumVisibleHeight
        context.coordinator.forcedLineBreakTintColor = forcedLineBreakTintColor
        (textView as? FullHitTextView)?.usesCompactCaret = true
        if AppFeatures.current.showsVisualDebugOverlays {
            ZoneEditorDebugStore.shared.updateTextView(
                zoneID: zoneID,
                mountedFocused: isFirstResponder,
                textViewFirstResponder: textView.isFirstResponder,
                uiViewFirstResponder: textView.isFirstResponder,
                requestedFirstResponder: isFirstResponder,
                textLength: (ZoneTextViewEmptyCaret.modelText(from: textView.text ?? "") as NSString).length
            )
        }

        let displayText = ZoneTextViewEmptyCaret.displayText(for: text)
        let stylingSignature = stylingSignatureForCurrentState
        let needsStylingUpdate = context.coordinator.lastAppliedStylingSignature != stylingSignature

        guard textView.text != displayText else {
            if needsStylingUpdate {
                updateStyling(of: textView)
                context.coordinator.lastAppliedStylingSignature = stylingSignature
            }
            context.coordinator.rememberAcceptedText(text, selectedRange: textView.selectedRange)
            syncFocus(textView: textView, isFirstResponder: isFirstResponder, context: context)
            return
        }

        let selectedRange = ZoneTextViewEmptyCaret.modelRange(
            from: textView.selectedRange,
            displayText: textView.text ?? ""
        )
        context.coordinator.isUpdating = true
        textView.text = displayText
        context.coordinator.isUpdating = false

        let displayRange = ZoneTextViewEmptyCaret.displayRange(
            fromModelRange: selectedRange,
            modelText: text
        )
        if selectedRange.location != NSNotFound &&
           displayRange.location <= (displayText as NSString).length &&
           textView.selectedRange != displayRange {
            textView.selectedRange = displayRange
        }

        if needsStylingUpdate || displayText.contains(ZoneForcedLineBreak.marker) {
            updateStyling(of: textView)
            context.coordinator.lastAppliedStylingSignature = stylingSignature
        }
        context.coordinator.rememberAcceptedText(text, selectedRange: textView.selectedRange)
        syncFocus(textView: textView, isFirstResponder: isFirstResponder, context: context)
    }
    
    private func syncFocus(textView: UITextView, isFirstResponder: Bool, context: Context) {
        if isFirstResponder && !textView.isFirstResponder {
            guard context.coordinator.focusSyncState != .becomingFirstResponder else { return }
            context.coordinator.focusSyncState = .becomingFirstResponder
            DispatchQueue.main.async {
                let manager = ZoneFocusManager.shared
                defer { context.coordinator.focusSyncState = .idle }
                guard manager.focusedZoneID == self.zoneID || manager.pendingFocusZoneID == self.zoneID else {
                    return
                }
                NotificationCenter.default.post(
                    name: .zoneEditorWillFocusTextView,
                    object: self.zoneID
                )
                _ = textView.becomeFirstResponder()
            }
            return
        }

        if !isFirstResponder && textView.isFirstResponder {
            guard context.coordinator.focusSyncState != .resigningFirstResponder else { return }
            context.coordinator.focusSyncState = .resigningFirstResponder
            DispatchQueue.main.async {
                let manager = ZoneFocusManager.shared
                defer { context.coordinator.focusSyncState = .idle }
                guard !manager.shouldRetainKeyboard,
                      manager.focusedZoneID != self.zoneID,
                      manager.pendingFocusZoneID != self.zoneID else {
                    return
                }
                if manager.focusedZoneID != self.zoneID {
                    textView.resignFirstResponder()
                }
            }
        }
    }
    
    func makeCoordinator() -> ZoneTextViewCoordinator {
        let coordinator = ZoneTextViewCoordinator()
        coordinator.zoneID = zoneID
        return coordinator
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let targetSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let calculatedSize = uiView.sizeThatFits(targetSize)

        return CGSize(
            width: width,
            height: max(ceil(calculatedSize.height), ceil(font.lineHeight))
        )
    }
    
    private func updateStyling(of textView: UITextView) {
        if textView.font != font {
            textView.font = font
        }
        if textView.textColor != textColor {
            textView.textColor = textColor
        }
        if textView.tintColor != cursorTintColor {
            textView.tintColor = cursorTintColor
        }
        textView.typingAttributes = textAttributes
        if textView.textContainerInset != contentInset {
            textView.textContainerInset = contentInset
        }
        if textView.textAlignment != textAlignment {
            textView.textAlignment = textAlignment
        }

        let fullRange = NSRange(location: 0, length: textView.textStorage.length)
        if fullRange.length > 0 {
            var attributes = textAttributes
            if ZoneTextViewEmptyCaret.isPlaceholderDisplay(textView.text) {
                attributes[.foregroundColor] = UIColor.clear
            }
            textView.textStorage.setAttributes(attributes, range: fullRange)
            ZoneForcedLineBreak.applyMarkerStyle(
                to: textView.textStorage,
                baseAttributes: textAttributes,
                markerColor: forcedLineBreakTintColor
            )
        }
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = max(lineSpacing, 0)

        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private var stylingSignatureForCurrentState: ZoneTextViewStylingSignature {
        ZoneTextViewStylingSignature(
            fontName: font.fontName,
            fontSize: font.pointSize,
            fontTraits: font.fontDescriptor.symbolicTraits.rawValue,
            textAlignment: textAlignment.rawValue,
            lineSpacing: lineSpacing,
            contentInsetTop: contentInset.top,
            contentInsetLeft: contentInset.left,
            contentInsetBottom: contentInset.bottom,
            contentInsetRight: contentInset.right,
            isPlaceholderDisplay: text.isEmpty
        )
    }
}

fileprivate enum FocusSyncState {
    case idle
    case becomingFirstResponder
    case resigningFirstResponder
}

fileprivate struct ZoneTextViewStylingSignature: Equatable {
    let fontName: String
    let fontSize: CGFloat
    let fontTraits: UInt32
    let textAlignment: Int
    let lineSpacing: CGFloat
    let contentInsetTop: CGFloat
    let contentInsetLeft: CGFloat
    let contentInsetBottom: CGFloat
    let contentInsetRight: CGFloat
    let isPlaceholderDisplay: Bool
}

private extension CGRect {
    func isNearlyEqual(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance
            && abs(size.height - other.size.height) <= tolerance
    }
}

// MARK: - Zone Plain Text Preview

/// Read-only text renderer used by the raw zone preview.
/// It intentionally mirrors `ZoneTextViewRepresentable` so focusing a zone does
/// not change text metrics, wrapping, or insets.
struct ZonePlainTextViewRepresentable: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let textAlignment: NSTextAlignment
    var lineSpacing: CGFloat = 0
    var contentInset: UIEdgeInsets = .zero
    var forcedLineBreakTintColor: UIColor = .systemPurple

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = contentInset
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.maximumNumberOfLines = 0
        textView.layoutManager.usesFontLeading = true
        textView.contentInset = .zero
        textView.scrollIndicatorInsets = .zero
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        apply(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        apply(textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize {
        let width = max(proposal.width ?? UIView.layoutFittingExpandedSize.width, 1)
        let targetSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let calculatedSize = uiView.sizeThatFits(targetSize)

        return CGSize(
            width: width,
            height: max(ceil(calculatedSize.height), ceil(font.lineHeight + contentInset.top + contentInset.bottom))
        )
    }

    private func apply(_ textView: UITextView) {
        textView.font = font
        textView.textColor = textColor
        textView.textAlignment = textAlignment
        textView.textContainerInset = contentInset

        if textView.text != text {
            textView.text = text
        }

        let fullRange = NSRange(location: 0, length: textView.textStorage.length)
        if fullRange.length > 0 {
            textView.textStorage.setAttributes(textAttributes, range: fullRange)
            ZoneForcedLineBreak.applyMarkerStyle(
                to: textView.textStorage,
                baseAttributes: textAttributes,
                markerColor: forcedLineBreakTintColor
            )
        }
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = max(lineSpacing, 0)

        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
    }
}

// MARK: - String Extensions

extension String {
    func line(at index: Int) -> String? {
        let lines = components(separatedBy: "\n")
        guard index >= 0 && index < lines.count else { return nil }
        return lines[index]
    }
    
    var lines: [String] {
        components(separatedBy: "\n")
    }
    
    func lineIndex(for characterOffset: Int) -> Int {
        guard characterOffset >= 0 else { return 0 }
        
        var currentIndex = 0
        let linesArray = lines
        
        for (index, line) in linesArray.enumerated() {
            let lineLength = line.count + 1
            if characterOffset < currentIndex + lineLength {
                return index
            }
            currentIndex += lineLength
        }
        
        return max(0, linesArray.count - 1)
    }
    
    func splitAtLine(_ lineIndex: Int) -> (before: String, after: String) {
        let linesArray = lines
        guard lineIndex >= 0 && lineIndex < linesArray.count else {
            return (self, "")
        }
        
        let before = linesArray[0...lineIndex].joined(separator: "\n")
        let after = lineIndex < linesArray.count - 1 
            ? linesArray[(lineIndex + 1)...].joined(separator: "\n")
            : ""
        
        return (before, after)
    }
}
