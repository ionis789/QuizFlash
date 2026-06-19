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
    private static let terminalBuffer = "\n" + placeholder

    static func displayText(for modelText: String) -> String {
        // Keep one final editor-only line after every editable position. The
        // selection is clamped before it, so TextKit never has to place a
        // terminal caret on the last physical line of an expanding zone.
        ZoneForcedLineBreak.editorDisplayText(modelText) + terminalBuffer
    }

    static func modelText(from displayText: String) -> String {
        let editableText = stripTerminalBuffer(from: displayText)
        return ZoneForcedLineBreak.editorModelText(editableText)
            .replacingOccurrences(of: placeholder, with: "")
    }

    static func isPlaceholderDisplay(_ displayText: String?) -> Bool {
        displayText == placeholder
    }

    static func editableDisplayLength(in displayText: String) -> Int {
        (stripTerminalBuffer(from: displayText) as NSString).length
    }

    static func hasTerminalBuffer(_ displayText: String) -> Bool {
        displayText.hasSuffix(terminalBuffer)
    }

    static func modelRange(from displayRange: NSRange, displayText: String) -> NSRange {
        let editableText = stripTerminalBuffer(from: displayText)
        let nsText = editableText as NSString
        let clampedLocation = min(max(displayRange.location, 0), nsText.length)
        let clampedEnd = min(max(displayRange.location + displayRange.length, clampedLocation), nsText.length)
        let prefix = nsText.substring(to: clampedLocation)
        let selectedText = nsText.substring(with: NSRange(location: clampedLocation, length: clampedEnd - clampedLocation))
        let placeholdersBefore = placeholderCount(in: prefix)
        let placeholdersInSelection = placeholderCount(in: selectedText)
        let visualBreaksBefore = visualLineBreakCount(in: prefix)
        let visualBreaksInSelection = visualLineBreakCount(in: selectedText)

        return NSRange(
            location: max(clampedLocation - placeholdersBefore - visualBreaksBefore, 0),
            length: max((clampedEnd - clampedLocation) - placeholdersInSelection - visualBreaksInSelection, 0)
        )
    }

    static func displayRange(fromModelRange range: NSRange, modelText: String) -> NSRange {
        let nsText = modelText as NSString
        let clampedLocation = min(max(range.location, 0), nsText.length)
        let clampedEnd = min(max(range.location + range.length, clampedLocation), nsText.length)
        let prefix = nsText.substring(to: clampedLocation)
        let selectedText = nsText.substring(with: NSRange(location: clampedLocation, length: clampedEnd - clampedLocation))
        let markersBefore = markerCount(in: prefix)
        let markersInSelection = markerCount(in: selectedText)
        return NSRange(
            location: clampedLocation + markersBefore,
            length: (clampedEnd - clampedLocation) + markersInSelection
        )
    }

    private static func stripTerminalBuffer(from displayText: String) -> String {
        guard displayText.hasSuffix(terminalBuffer) else { return displayText }
        return String(displayText.dropLast(terminalBuffer.count))
    }

    private static func placeholderCount(in text: String) -> Int {
        text.components(separatedBy: placeholder).count - 1
    }

    private static func visualLineBreakCount(in text: String) -> Int {
        text.components(separatedBy: ZoneForcedLineBreak.marker + "\n").count - 1
    }

    private static func markerCount(in text: String) -> Int {
        text.components(separatedBy: ZoneForcedLineBreak.marker).count - 1
    }
}

// MARK: - Full Hit Text View
/// Custom UITextView that keeps selection stable inside the editor surface.
final class FullHitTextView: UITextView {
    var usesCompactCaret: Bool = true
    var debugZoneID: UUID?
    private var lastStableCaretRect: CGRect?

    override func caretRect(for position: UITextPosition) -> CGRect {
        let proposedRect = super.caretRect(for: position)
        var rect = proposedRect
        guard usesCompactCaret else { return proposedRect }

        rect.size.width = 2.1
        if let invalidReason = unstableCaretRectReason(proposedRect) {
            if let lastStableCaretRect {
                if AppFeatures.current.showsVisualDebugOverlays {
                    ZoneEditorDebugStore.shared.recordLayoutEvent(
                        "caret.invalid-rect-reused",
                        zoneID: debugZoneID,
                        details: "reason=\(invalidReason) selected=\(selectedRange.location):\(selectedRange.length) textLen=\(((text ?? "") as NSString).length) proposed=\(debugRect(proposedRect)) reused=\(debugRect(lastStableCaretRect)) bounds=\(debugSize(bounds.size)) content=\(debugSize(contentSize))"
                    )
                }
                var stableRect = lastStableCaretRect
                stableRect.size.width = 2.1
                return stableRect
            }

            if AppFeatures.current.showsVisualDebugOverlays {
                ZoneEditorDebugStore.shared.recordLayoutEvent(
                    "caret.invalid-rect-no-stable",
                    zoneID: debugZoneID,
                    details: "reason=\(invalidReason) selected=\(selectedRange.location):\(selectedRange.length) textLen=\(((text ?? "") as NSString).length) proposed=\(debugRect(proposedRect)) bounds=\(debugSize(bounds.size)) content=\(debugSize(contentSize))"
                )
            }
            return rect
        }

        lastStableCaretRect = rect
        return rect
    }

    private func isStableCaretRect(_ rect: CGRect) -> Bool {
        let minimumHeight = max(4, (font?.lineHeight ?? 0) * 0.2)
        guard rect.minX.isFinite,
              rect.minY.isFinite,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.height >= minimumHeight,
              rect.minY >= textContainerInset.top - 1 else {
            return false
        }

        let maximumY = max(bounds.height, contentSize.height) + textContainerInset.bottom + 1
        return rect.maxY <= maximumY
    }

    private func unstableCaretRectReason(_ rect: CGRect) -> String? {
        guard isStableCaretRect(rect) else { return "geometry" }
        guard isTransientTailResetCaretRect(rect) else { return nil }
        return "tail-reset"
    }

    private func isTransientTailResetCaretRect(_ rect: CGRect) -> Bool {
        guard lastStableCaretRect != nil else { return false }
        let textLength = ((text ?? "") as NSString).length
        guard textLength >= 8 else { return false }
        guard selectedRange.length == 0,
              selectedRange.location >= max(textLength - 6, 0) else {
            return false
        }

        let resetTopLimit = textContainerInset.top + 2
        let resetLeadingLimit = textContainerInset.left + 2
        return rect.minY <= resetTopLimit && rect.minX <= resetLeadingLimit
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.bounds.contains(point) {
            return self
        }
        return super.hitTest(point, with: event)
    }

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        recordNativeScrollRequest(
            "text.scroll-rect-to-visible",
            details: "rect=\(debugRect(rect)) animated=\(animated ? 1 : 0)"
        )
        guard isScrollEnabled else { return }
        super.scrollRectToVisible(rect, animated: animated)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        recordNativeScrollRequest(
            "text.scroll-range-to-visible",
            details: "range=\(range.location):\(range.length)"
        )
        guard isScrollEnabled else { return }
        super.scrollRangeToVisible(range)
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        if AppFeatures.current.showsVisualDebugOverlays,
           abs(contentOffset.y - self.contentOffset.y) > 0.5 {
            recordNativeScrollRequest(
                "text.set-content-offset",
                details: "from=\(debugPoint(self.contentOffset)) to=\(debugPoint(contentOffset)) animated=\(animated ? 1 : 0)"
            )
        }
        super.setContentOffset(contentOffset, animated: animated)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard AppFeatures.current.showsVisualDebugOverlays else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        ZoneEditorDebugStore.shared.recordLayoutEvent(
            "ui-layout",
            zoneID: debugZoneID,
            details: "frame=\(debugRect(frame)) bounds=\(debugSize(bounds.size)) containerW=\(debugValue(textContainer.size.width)) used=\(debugSize(usedRect.size)) inset=\(debugInsets(textContainerInset)) len=\((text as NSString?)?.length ?? 0) fr=\(isFirstResponder ? 1 : 0)"
        )
    }

    private func recordNativeScrollRequest(_ stage: String, details: String) {
        guard AppFeatures.current.showsVisualDebugOverlays else { return }
        let parentScroll = nearestParentScrollView()
        let parentType = parentScroll.map { String(describing: type(of: $0)) } ?? "nil"
        let parentOffset = parentScroll.map { debugPoint($0.contentOffset) } ?? "nil"
        ZoneEditorDebugStore.shared.recordLayoutEvent(
            stage,
            zoneID: debugZoneID,
            details: "\(details) ownOffset=\(debugPoint(contentOffset)) ownBounds=\(debugRect(bounds)) ownContent=\(debugSize(contentSize)) scrollEnabled=\(isScrollEnabled ? 1 : 0) parent=\(parentType) parentOffset=\(parentOffset)"
        )
    }

    private func nearestParentScrollView() -> UIScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }

    private func debugRect(_ rect: CGRect) -> String {
        "\(debugValue(rect.minX)),\(debugValue(rect.minY)),\(debugValue(rect.width))x\(debugValue(rect.height))"
    }

    private func debugSize(_ size: CGSize) -> String {
        "\(debugValue(size.width))x\(debugValue(size.height))"
    }

    private func debugPoint(_ point: CGPoint) -> String {
        "\(debugValue(point.x)),\(debugValue(point.y))"
    }

    private func debugInsets(_ insets: UIEdgeInsets) -> String {
        "\(debugValue(insets.top)),\(debugValue(insets.left)),\(debugValue(insets.bottom)),\(debugValue(insets.right))"
    }

    private func debugValue(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
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
    private(set) var layoutEvents: [String] = []
    private(set) var toolbarLifecycleEvents: [String] = []
    private var layoutEventIndex = 0
    private var toolbarLifecycleEventIndex = 0
    private var eventCounters: [String: Int] = [:]
    private var skippedEventCounters: [String: Int] = [:]
    private var isRecordingEnabled = false
    private let startedAt = Date()

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

    var compactHudLines: [String] {
        [
            "#\(eventIndex) \(lastEvent)",
            focusLine,
            textViewLine,
            canvasLine,
            toolbarLine,
            caretLine,
            "rates \(counterSummary)"
        ]
    }

    func recordEvent(_ value: String) {
        eventIndex += 1
        lastEvent = value
    }

    func setLayoutRecordingEnabled(_ isEnabled: Bool) {
        isRecordingEnabled = isEnabled
    }

    func recordLayoutEvent(
        _ stage: String,
        zoneID: UUID?,
        pathID: String? = nil,
        details: String
    ) {
        guard AppFeatures.current.showsVisualDebugOverlays, isRecordingEnabled else { return }

        eventCounters[stage, default: 0] += 1
        if shouldThrottleLayoutEvent(stage) {
            let count = eventCounters[stage, default: 0]
            if count > 3 && !count.isMultiple(of: 20) {
                skippedEventCounters[stage, default: 0] += 1
                return
            }
        }

        layoutEventIndex += 1
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let path = pathID.map { " path=\($0)" } ?? ""
        let line = "L\(layoutEventIndex) +\(elapsedMS)ms \(stage) zone=\(shortID(zoneID))\(path) \(details)"
        layoutEvents.append(line)
        if layoutEvents.count > 900 {
            layoutEvents.removeFirst(layoutEvents.count - 900)
        }
    }

    var layoutTraceReport: String {
        let counters = counterReport
        let events = layoutEvents.isEmpty ? "<none>" : layoutEvents.joined(separator: "\n")
        let toolbarEvents = toolbarLifecycleEvents.isEmpty ? "<none>" : toolbarLifecycleEvents.joined(separator: "\n")
        return """
        COUNTERS
        \(counters)

        KEYBOARD / TOOLBAR LIFECYCLE
        \(toolbarEvents)

        EVENTS
        \(events)
        """
    }

    var latestLayoutLines: [String] {
        Array(layoutEvents.suffix(4))
    }

    private var counterSummary: String {
        let hot = eventCounters
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(4)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return hot.isEmpty ? "none" : hot
    }

    private var counterReport: String {
        guard !eventCounters.isEmpty else { return "<none>" }
        return eventCounters
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map { key, value in
                let skipped = skippedEventCounters[key, default: 0]
                return skipped > 0 ? "\(key): \(value) skipped=\(skipped)" : "\(key): \(value)"
            }
            .joined(separator: "\n")
    }

    private func shouldThrottleLayoutEvent(_ stage: String) -> Bool {
        switch stage {
        case "ui-update",
             "ui-sync",
             "ui-sizeThatFits",
             "layout block",
             "group-layout",
             "group-preference-ignored",
             "editor-body",
             "scroll-skip",
             "scroll-schedule-skip":
            return true
        default:
            return false
        }
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
        verticalAlignment: String,
        fixedWidth: CGFloat?,
        fixedHeight: CGFloat?
    ) {
        setLine(
            &selectedZoneLine,
            "zone path=\(pathID) id=\(shortID(zoneID)) type=\(contentType) size=\(sizeMode) y=\(verticalAlignment) fixed=\(format(fixedWidth))x\(format(fixedHeight))"
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
        recordLayoutEvent(
            "caret-geometry",
            zoneID: zoneID,
            details: "range=\(selectedRange.location):\(selectedRange.length) anchorY=\(format(anchorY)) rect=\(format(windowRect.minX)),\(format(windowRect.minY)),\(format(windowRect.width))x\(format(windowRect.height))"
        )
    }

    func recordTextSync(
        _ stage: String,
        zoneID: UUID?,
        modelLength: Int,
        uiLength: Int,
        lastAcceptedLength: Int,
        isUpdating: Bool,
        isFirstResponder: Bool,
        selectedRange: NSRange,
        action: String
    ) {
        recordLayoutEvent(
            stage,
            zoneID: zoneID,
            details: "modelLen=\(modelLength) uiLen=\(uiLength) acceptedLen=\(lastAcceptedLength) updating=\(flag(isUpdating)) fr=\(flag(isFirstResponder)) selected=\(selectedRange.location):\(selectedRange.length) action=\(action)"
        )
    }

    func recordScrollDecision(
        _ stage: String,
        zoneID: UUID?,
        details: String
    ) {
        recordLayoutEvent(stage, zoneID: zoneID, details: details)
    }

    func recordToolbarLifecycle(
        editor: String,
        stage: String,
        zoneID: UUID?,
        pathID: String?,
        details: String
    ) {
        guard AppFeatures.current.showsVisualDebugOverlays else { return }

        toolbarLifecycleEventIndex += 1
        eventCounters["toolbar.\(stage)", default: 0] += 1
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let path = pathID.map { " path=\($0)" } ?? ""
        let line = "T\(toolbarLifecycleEventIndex) +\(elapsedMS)ms \(editor).\(stage) zone=\(shortID(zoneID))\(path) \(details)"
        toolbarLifecycleEvents.append(line)
        if toolbarLifecycleEvents.count > 160 {
            toolbarLifecycleEvents.removeFirst(toolbarLifecycleEvents.count - 160)
        }
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
    var onCaretGeometryChange: ((CGFloat, CGRect, CGFloat, ZoneEditorCaretScrollSource, String) -> Void)?
    var onCommit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textColor: UIColor = .label
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
    private var pendingTextEditCaretSource: ZoneEditorCaretScrollSource?
    private var settlingTextEditCaretSource: ZoneEditorCaretScrollSource?
    private var lastTextChangeWasRejected = false
    private var forcedLineBreakDebugSequence = 0
    private var caretTraceSequence = 0
    private var lastForcedLineBreakTrace: (id: Int, timestamp: CFTimeInterval)?
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

    fileprivate func recordCaretProbe(
        _ stage: String,
        textView: UITextView,
        changedRange: NSRange? = nil,
        replacementText: String? = nil,
        extra: String = ""
    ) {
        guard AppFeatures.current.showsVisualDebugOverlays else { return }

        let displayText = textView.text ?? ""
        let modelText = ZoneTextViewEmptyCaret.modelText(from: displayText)
        let displayRange = textView.selectedRange
        let modelRange = ZoneTextViewEmptyCaret.modelRange(
            from: displayRange,
            displayText: displayText
        )
        let usedRect = textView.layoutManager.usedRect(for: textView.textContainer)
        let caretRects = caretDebugRects(in: textView)
        let changed = changedRange.map { "\($0.location):\($0.length)" } ?? "nil"
        let replacement = replacementText.map(debugReplacementText) ?? "nil"
        let tail = debugTextWindow(around: displayRange.location, in: displayText)
        let details = [
            "displaySel=\(displayRange.location):\(displayRange.length)",
            "modelSel=\(modelRange.location):\(modelRange.length)",
            "change=\(changed)",
            "repl=\(replacement)",
            "displayLen=\((displayText as NSString).length)",
            "modelLen=\((modelText as NSString).length)",
            "storageLen=\(textView.textStorage.length)",
            "markers=\(markerCount(in: displayText))",
            "newlines=\(newlineCount(in: displayText))",
            "fr=\(textView.isFirstResponder ? 1 : 0)",
            "scroll=\(textView.isScrollEnabled ? 1 : 0)",
            "updating=\(isUpdating ? 1 : 0)",
            "waiting=\(waitsForSettledTextLayoutCaret ? 1 : 0)",
            "marked=\(textView.markedTextRange == nil ? 0 : 1)",
            "bounds=\(debugRect(textView.bounds))",
            "content=\(debugSize(textView.contentSize))",
            "offset=\(debugPoint(textView.contentOffset))",
            "inset=\(debugInsets(textView.textContainerInset))",
            "container=\(debugSize(textView.textContainer.size))",
            "used=\(debugRect(usedRect))",
            "extraLine=\(debugRect(textView.layoutManager.extraLineFragmentRect))",
            "caret=\(caretRects.local)",
            "caretWin=\(caretRects.window)",
            "first=\(caretRects.first)",
            "tail=\(tail)",
            extra
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")

        ZoneEditorDebugStore.shared.recordLayoutEvent(
            stage,
            zoneID: zoneID,
            details: details
        )
    }

    private func caretDebugRects(in textView: UITextView) -> (local: String, window: String, first: String) {
        guard let caretRect = textKitCaretRect(in: textView) else {
            return ("nil", "nil", "nil")
        }

        let caretWindowRect = textView.convert(caretRect, to: nil)
        return (
            debugRect(caretRect),
            debugRect(caretWindowRect),
            "textKit=\(debugRect(caretRect))"
        )
    }

    /// Computes the insertion line directly from TextKit. Querying UITextView's
    /// selection rect for a terminal marker can ask the ancestor scroll view to
    /// reveal the zone's top edge before that line has finished laying out.
    private func textKitCaretRect(in textView: UITextView) -> CGRect? {
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let storageLength = textView.textStorage.length
        guard storageLength > 0 else { return nil }

        layoutManager.ensureLayout(for: textContainer)

        let selectedLocation = min(max(textView.selectedRange.location, 0), storageLength)
        let glyphIndex: Int
        let insertionAtEnd = selectedLocation >= storageLength

        if insertionAtEnd {
            glyphIndex = max(layoutManager.numberOfGlyphs - 1, 0)
        } else {
            glyphIndex = layoutManager.glyphIndexForCharacter(at: selectedLocation)
        }

        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        let glyphRange = NSRange(location: glyphIndex, length: 1)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )
        let height = max(lineRect.height, textView.font?.lineHeight ?? 0)
        let x = insertionAtEnd ? glyphRect.maxX : glyphRect.minX

        return CGRect(
            x: textView.textContainerInset.left + x,
            y: textView.textContainerInset.top + lineRect.minY,
            width: 2.1,
            height: height
        )
    }

    private func markerCount(in text: String) -> Int {
        text.components(separatedBy: ZoneForcedLineBreak.marker).count - 1
    }

    private func newlineCount(in text: String) -> Int {
        text.components(separatedBy: "\n").count - 1
    }

    private func debugReplacementText(_ text: String) -> String {
        if text == "\n" { return "\\n" }
        if text.isEmpty { return "<delete>" }
        return debugEscaped(text)
    }

    private func debugTextWindow(around location: Int, in text: String) -> String {
        let nsText = text as NSString
        guard nsText.length > 0 else { return "\"\"" }

        let clamped = min(max(location, 0), nsText.length)
        let start = max(clamped - 8, 0)
        let end = min(clamped + 8, nsText.length)
        let snippet = nsText.substring(with: NSRange(location: start, length: end - start))
        return "\"\(debugEscaped(snippet))\"@\(start)-\(end)"
    }

    private func debugEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ZoneForcedLineBreak.marker, with: "<marker>")
            .replacingOccurrences(of: ZoneTextViewEmptyCaret.placeholder, with: "<zwsp>")
    }

    private func debugRect(_ rect: CGRect) -> String {
        "\(debugValue(rect.minX)),\(debugValue(rect.minY)),\(debugValue(rect.width))x\(debugValue(rect.height))"
    }

    private func debugSize(_ size: CGSize) -> String {
        "\(debugValue(size.width))x\(debugValue(size.height))"
    }

    private func debugPoint(_ point: CGPoint) -> String {
        "\(debugValue(point.x)),\(debugValue(point.y))"
    }

    private func debugInsets(_ insets: UIEdgeInsets) -> String {
        "\(debugValue(insets.top)),\(debugValue(insets.left)),\(debugValue(insets.bottom)),\(debugValue(insets.right))"
    }

    private func debugValue(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        guard !ZoneFocusManager.shared.isSuppressingFocusRequests else {
            ZoneEditorDebugStore.shared.recordFocusEvent("textView shouldBegin ignored", zoneID: zoneID)
            return false
        }
        if let zoneID {
            postWillFocusNotification(for: zoneID)
        }
        return true
    }

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        recordCaretProbe(
            "caret.should-change",
            textView: textView,
            changedRange: range,
            replacementText: text
        )

        if text.isEmpty,
           handleForcedLineBreakBackspace(in: textView, range: range) {
            recordCaretProbe(
                "caret.backspace-forced-break-handled",
                textView: textView,
                changedRange: range,
                replacementText: text
            )
            return false
        }

        guard text == "\n" else {
            pendingTextEditCaretSource = .textInput
            return true
        }

        insertForcedLineBreak(in: textView)
        return false
    }

    func textViewDidChange(_ textView: UITextView) {
        recordCaretProbe("caret.did-change-start", textView: textView)
        normalizePlaceholderIfNeeded(in: textView)
        guard let displayText = textView.text else { return }
        guard !isUpdating else { return }

        lastTextChangeWasRejected = false
        let modelText = ZoneTextViewEmptyCaret.modelText(from: displayText)
        let overflowDecision = textOverflowRejectionDetails(modelText, in: textView)
        recordCaretProbe(
            "caret.overflow-decision",
            textView: textView,
            extra: overflowDecision.details
        )
        if overflowDecision.rejects {
            lastTextChangeWasRejected = true
            pendingTextEditCaretSource = nil
            settlingTextEditCaretSource = nil
            waitsForSettledTextLayoutCaret = false
            recordCaretProbe(
                "caret.reject-overflow-before-restore",
                textView: textView,
                extra: overflowDecision.details
            )
            restoreLastAcceptedText(in: textView)
            recordCaretProbe(
                "caret.reject-overflow-after-restore",
                textView: textView,
                extra: overflowDecision.details
            )
            reportCursorPosition(
                from: textView,
                includeCaretAnchor: true,
                forceCaretGeometry: true,
                source: .rejectedTextEdit
            )
            return
        }

        lastText = modelText
        rememberAcceptedText(modelText, selectedRange: textView.selectedRange)
        resetTextStyling(in: textView)
        recordCaretProbe("caret.did-change-after-style", textView: textView)
        waitsForSettledTextLayoutCaret = true
        let caretSource = pendingTextEditCaretSource ?? .textInput
        settlingTextEditCaretSource = caretSource
        pendingTextEditCaretSource = nil
        onTextChange?(modelText)
        reportCursorPosition(from: textView, includeCaretAnchor: false, source: caretSource)
        scheduleSettledCaretReport(from: textView, source: caretSource)
    }
    
    func textViewDidChangeSelection(_ textView: UITextView) {
        recordCaretProbe("caret.selection-change-start", textView: textView)
        guard !isUpdating else { return }
        guard textView.isFirstResponder else { return }
        guard !clampSelectionToEditableContent(in: textView) else { return }
        normalizeTypingAttributes(in: textView)

        if let caretSource = pendingTextEditCaretSource {
            recordCaretProbe("caret.selection-change-pending-text-edit", textView: textView)
            reportCursorPosition(from: textView, includeCaretAnchor: false, source: caretSource)
            return
        }

        guard !waitsForSettledTextLayoutCaret else {
            let caretSource = settlingTextEditCaretSource ?? pendingTextEditCaretSource ?? .textInput
            recordCaretProbe("caret.selection-change-waiting-layout", textView: textView)
            reportCursorPosition(from: textView, includeCaretAnchor: false, source: caretSource)
            scheduleSettledCaretReport(from: textView, source: caretSource)
            return
        }

        reportCursorPosition(from: textView, includeCaretAnchor: true, source: .selectionTap)
        scheduleSettledCaretReport(from: textView, source: .selectionTap)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        focusSyncState = .idle
        ZoneEditorDebugStore.shared.recordFocusEvent("textView didBegin", zoneID: zoneID)
        recordCaretProbe("caret.did-begin-editing", textView: textView)
        _ = clampSelectionToEditableContent(in: textView)
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
        reportCursorPosition(from: textView, includeCaretAnchor: true, source: .focus)
        scheduleSettledCaretReport(from: textView, source: .focus)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        focusSyncState = .idle
        ZoneEditorDebugStore.shared.recordFocusEvent("textView didEnd", zoneID: zoneID)
        recordCaretProbe("caret.did-end-editing", textView: textView)
        onFocusChange?(false)
    }

    private func postWillFocusNotification(for zoneID: UUID) {
        guard ZoneFocusManager.shared.retainKeyboardForTextFocusTransfer(to: zoneID) else { return }
        NotificationCenter.default.post(
            name: .zoneEditorWillFocusTextView,
            object: zoneID
        )
    }
    
    private func reportCursorPosition(
        from textView: UITextView,
        includeCaretAnchor: Bool,
        forceCaretGeometry: Bool = false,
        source: ZoneEditorCaretScrollSource
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

        if textView.selectedTextRange != nil {
            recordCaretProbe(
                "caret.geometry-before-layout",
                textView: textView,
                extra: "force=\(forceCaretGeometry ? 1 : 0)"
            )
            textView.layoutIfNeeded()
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            recordCaretProbe(
                "caret.geometry-after-layout",
                textView: textView,
                extra: "force=\(forceCaretGeometry ? 1 : 0)"
            )
            guard let caretRect = textKitCaretRect(in: textView) else { return }
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
                recordCaretProbe(
                    "caret.geometry-skip-same",
                    textView: textView,
                    extra: "anchor=\(debugValue(anchorY)) lastAnchor=\(debugValue(lastReportedCaretAnchorY))"
                )
                return
            }

            lastReportedCaretAnchorY = anchorY
            lastReportedCaretWindowRect = caretRectInWindow
            let traceID = nextCaretTraceID(source: source)
            ZoneEditorDebugStore.shared.recordCaret(
                zoneID: zoneID,
                selectedRange: nsRange,
                anchorY: anchorY,
                windowRect: caretRectInWindow
            )
            recordCaretProbe(
                "caret.geometry-emit",
                textView: textView,
                extra: "trace=\(traceID) source=\(source.rawValue) anchor=\(debugValue(anchorY)) windowMaxY=\(debugValue(caretRectInWindow.maxY))"
            )
            onCaretGeometryChange?(anchorY, caretRectInWindow, textView.bounds.height, source, traceID)
        }
    }

    private func nextCaretTraceID(source: ZoneEditorCaretScrollSource) -> String {
        caretTraceSequence += 1
        let zone = zoneID.map { String($0.uuidString.prefix(6)) } ?? "none"
        let forcedBreak: String
        if let trace = lastForcedLineBreakTrace,
           CACurrentMediaTime() - trace.timestamp <= 1.5 {
            forcedBreak = "forced-\(trace.id)"
        } else {
            forcedBreak = "none"
        }
        return "\(zone)-\(caretTraceSequence)-\(source.rawValue)-\(forcedBreak)"
    }

    func rememberAcceptedText(_ modelText: String, selectedRange: NSRange) {
        lastAcceptedText = modelText
        lastAcceptedSelectedRange = ZoneTextViewEmptyCaret.modelRange(
            from: selectedRange,
            displayText: ZoneTextViewEmptyCaret.displayText(for: modelText)
        )
        lastText = modelText
    }

    func shouldDeferModelSync(modelText: String, uiModelText: String, textView: UITextView) -> Bool {
        guard textView.isFirstResponder,
              !isUpdating,
              uiModelText != modelText,
              lastAcceptedText == uiModelText,
              lastAcceptedText != modelText else {
            return false
        }

        return true
    }

    var lastAcceptedTextLength: Int {
        (lastAcceptedText as NSString).length
    }

    private func normalizePlaceholderIfNeeded(in textView: UITextView) {
        guard let displayText = textView.text,
              !ZoneTextViewEmptyCaret.hasTerminalBuffer(displayText),
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

    private func textOverflowRejectionDetails(_ modelText: String, in textView: UITextView) -> (rejects: Bool, details: String) {
        guard let maximumVisibleHeight,
              maximumVisibleHeight > 0,
              textView.bounds.width > 1,
              (modelText as NSString).length > (lastAcceptedText as NSString).length else {
            let maximumVisibleHeightText = maximumVisibleHeight.map(debugValue) ?? "nil"
            return (
                false,
                "overflowCheck=skipped max=\(maximumVisibleHeightText) boundsW=\(debugValue(textView.bounds.width)) lastAcceptedLen=\((lastAcceptedText as NSString).length) newLen=\((modelText as NSString).length)"
            )
        }

        textView.layoutIfNeeded()
        let targetSize = CGSize(
            width: textView.bounds.width,
            height: UIView.layoutFittingCompressedSize.height
        )
        let requiredHeight = ceil(textView.sizeThatFits(targetSize).height)
        let wouldOverflow = requiredHeight > ceil(maximumVisibleHeight) + 0.5
        let details = "overflowCheck=\(wouldOverflow ? "allow-scroll" : "accept") required=\(debugValue(requiredHeight)) max=\(debugValue(maximumVisibleHeight)) bounds=\(debugSize(textView.bounds.size)) content=\(debugSize(textView.contentSize)) used=\(debugRect(textView.layoutManager.usedRect(for: textView.textContainer))) lastAcceptedLen=\((lastAcceptedText as NSString).length) newLen=\((modelText as NSString).length)"
        return (false, details)
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

    private func scheduleSettledCaretReport(from textView: UITextView, source: ZoneEditorCaretScrollSource) {
        guard textView.isFirstResponder else { return }
        caretReportGeneration += 1
        let generation = caretReportGeneration
        recordCaretProbe(
            "caret.settled-schedule",
            textView: textView,
            extra: "generation=\(generation)"
        )

        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self,
                  let textView,
                  self.caretReportGeneration == generation,
                  textView.window != nil else { return }

            self.recordCaretProbe(
                "caret.settled-runloop-before-layout",
                textView: textView,
                extra: "generation=\(generation)"
            )
            textView.window?.layoutIfNeeded()
            textView.superview?.layoutIfNeeded()
            self.waitsForSettledTextLayoutCaret = false
            self.settlingTextEditCaretSource = nil
            self.recordCaretProbe(
                "caret.settled-runloop-after-layout",
                textView: textView,
                extra: "generation=\(generation)"
            )
            self.reportCursorPosition(
                from: textView,
                includeCaretAnchor: true,
                forceCaretGeometry: true,
                source: source
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak textView] in
                guard let self,
                      let textView,
                      self.caretReportGeneration == generation,
                      textView.window != nil else { return }

                self.recordCaretProbe(
                    "caret.settled-80ms-before-layout",
                    textView: textView,
                    extra: "generation=\(generation)"
                )
                textView.window?.layoutIfNeeded()
                textView.superview?.layoutIfNeeded()
                self.recordCaretProbe(
                    "caret.settled-80ms-after-layout",
                    textView: textView,
                    extra: "generation=\(generation)"
                )
                self.reportCursorPosition(
                    from: textView,
                    includeCaretAnchor: true,
                    forceCaretGeometry: true,
                    source: source
                )
            }
        }
    }

    private func placeCaret(at point: CGPoint, in textView: UITextView) {
        guard let position = textView.closestPosition(to: point) else { return }

        let location = textView.offset(from: textView.beginningOfDocument, to: position)
        let textLength = ZoneTextViewEmptyCaret.editableDisplayLength(in: textView.text ?? "")
        let clampedLocation = min(max(location, 0), textLength)
        let range = NSRange(location: clampedLocation, length: 0)
        textView.selectedRange = ZoneTextViewEmptyCaret.isPlaceholderDisplay(textView.text)
            ? NSRange(location: 0, length: 0)
            : range
        reportCursorPosition(from: textView, includeCaretAnchor: true, source: .selectionTap)
        scheduleSettledCaretReport(from: textView, source: .selectionTap)
    }

    private func clampSelectionToEditableContent(in textView: UITextView) -> Bool {
        let editableLength = ZoneTextViewEmptyCaret.editableDisplayLength(in: textView.text ?? "")
        let selection = textView.selectedRange
        let location = min(max(selection.location, 0), editableLength)
        let length = min(max(selection.length, 0), editableLength - location)
        let clampedRange = NSRange(location: location, length: length)
        guard clampedRange != selection else { return false }

        isUpdating = true
        textView.selectedRange = clampedRange
        isUpdating = false
        return true
    }

    private func insertForcedLineBreak(in textView: UITextView) {
        forcedLineBreakDebugSequence += 1
        let forcedBreakID = forcedLineBreakDebugSequence
        lastForcedLineBreakTrace = (id: forcedBreakID, timestamp: CACurrentMediaTime())
        recordCaretProbe(
            "caret.forced-break-start",
            textView: textView,
            extra: "forcedBreakID=\(forcedBreakID)"
        )
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
        let currentModelText = ZoneTextViewEmptyCaret.modelText(from: currentText)
        let currentDisplayText = ZoneTextViewEmptyCaret.displayText(for: currentModelText)
        let textLength = ZoneTextViewEmptyCaret.editableDisplayLength(in: currentDisplayText)
        let selectedRange = ZoneTextViewEmptyCaret.isPlaceholderDisplay(textView.text)
            ? NSRange(location: 0, length: 0)
            : NSRange(
                location: min(max(textView.selectedRange.location, 0), textLength),
                length: min(max(textView.selectedRange.length, 0), max(textLength - min(max(textView.selectedRange.location, 0), textLength), 0))
            )
        let selectedModelRange = ZoneTextViewEmptyCaret.modelRange(
            from: selectedRange,
            displayText: currentDisplayText
        )
        guard canInsertForcedLineBreak(
            in: currentModelText,
            selectedRange: selectedModelRange
        ) else {
            recordCaretProbe(
                "caret.forced-break-rejected-adjacent-marker",
                textView: textView,
                changedRange: selectedRange,
                replacementText: "\n",
                extra: "modelRange=\(selectedModelRange.location):\(selectedModelRange.length)"
            )
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            recordCaretProbe("caret.forced-break-report-skipped-adjacent-marker", textView: textView)
            return
        }

        let mutable = NSMutableString(string: currentModelText)
        mutable.replaceCharacters(in: selectedModelRange, with: ZoneForcedLineBreak.marker)
        let modelText = mutable as String
        let displayText = ZoneTextViewEmptyCaret.displayText(for: modelText)
        let modelCaretRange = NSRange(
            location: selectedModelRange.location + (ZoneForcedLineBreak.marker as NSString).length,
            length: 0
        )

        recordCaretProbe(
            "caret.forced-break-before-apply",
            textView: textView,
            changedRange: selectedRange,
            replacementText: "\n",
            extra: "forcedBreakID=\(forcedBreakID) modelRange=\(selectedModelRange.location):\(selectedModelRange.length) nextModelCaret=\(modelCaretRange.location):\(modelCaretRange.length)"
        )
        let previousMeasuredHeight = measuredTextHeight(in: textView)
        let preChangeCaretWindowRect = textKitCaretRect(in: textView).map { textView.convert($0, to: nil) }
        let nextDisplayRange = ZoneTextViewEmptyCaret.displayRange(
            fromModelRange: modelCaretRange,
            modelText: modelText
        )
        isUpdating = true
        replaceDisplayTextIncrementally(
            in: textView,
            with: displayText,
            selectedRange: nextDisplayRange
        )
        isUpdating = false
        recordCaretProbe(
            "caret.forced-break-after-text-set",
            textView: textView,
            changedRange: selectedRange,
            replacementText: "\n",
            extra: "forcedBreakID=\(forcedBreakID) modelRange=\(selectedModelRange.location):\(selectedModelRange.length) nextModelCaret=\(modelCaretRange.location):\(modelCaretRange.length)"
        )

        applyForcedLineBreakMarkerStyle(to: textView)
        let nextMeasuredHeight = measuredTextHeight(in: textView)
        postNewlineLayoutShiftIfNeeded(
            deltaY: max(nextMeasuredHeight - previousMeasuredHeight, 0),
            caretRectInWindow: preChangeCaretWindowRect,
            forcedBreakID: forcedBreakID
        )
        recordCaretProbe(
            "caret.forced-break-after-marker-style",
            textView: textView,
            extra: "forcedBreakID=\(forcedBreakID)"
        )
        pendingTextEditCaretSource = .newline
        textViewDidChange(textView)
        recordCaretProbe(
            "caret.forced-break-after-did-change",
            textView: textView,
            extra: "forcedBreakID=\(forcedBreakID) rejected=\(lastTextChangeWasRejected ? 1 : 0)"
        )
        guard !lastTextChangeWasRejected else {
            recordCaretProbe(
                "caret.forced-break-report-skipped-rejected",
                textView: textView,
                extra: "forcedBreakID=\(forcedBreakID)"
            )
            lastTextChangeWasRejected = false
            return
        }
        recordCaretProbe(
            "caret.forced-break-awaiting-settled-layout",
            textView: textView,
            extra: "forcedBreakID=\(forcedBreakID)"
        )
    }

    private func measuredTextHeight(in textView: UITextView) -> CGFloat {
        let width = textView.bounds.width > 1
            ? textView.bounds.width
            : textView.textContainer.size.width
                + textView.textContainerInset.left
                + textView.textContainerInset.right
        let targetSize = CGSize(
            width: max(width, 1),
            height: UIView.layoutFittingCompressedSize.height
        )
        return ceil(textView.sizeThatFits(targetSize).height)
    }

    private func postNewlineLayoutShiftIfNeeded(
        deltaY: CGFloat,
        caretRectInWindow: CGRect?,
        forcedBreakID: Int
    ) {
        guard let zoneID else { return }

        if AppFeatures.current.showsVisualDebugOverlays {
            ZoneEditorDebugStore.shared.recordLayoutEvent(
                "caret.forced-break-prelayout-shift",
                zoneID: zoneID,
                details: "forcedBreakID=\(forcedBreakID) delta=\(debugValue(deltaY)) caretWin=\(caretRectInWindow.map(debugRect) ?? "nil")"
            )
        }

        guard deltaY > 1 else { return }

        var userInfo: [String: Any] = [
            ZoneEditorNewlineLayoutShiftNotification.layoutDeltaYKey: deltaY,
            ZoneEditorNewlineLayoutShiftNotification.forcedBreakIDKey: forcedBreakID
        ]
        if let caretRectInWindow {
            userInfo[ZoneEditorNewlineLayoutShiftNotification.caretRectInWindowKey] = NSValue(cgRect: caretRectInWindow)
        }
        NotificationCenter.default.post(
            name: .zoneEditorWillApplyNewlineLayoutShift,
            object: zoneID,
            userInfo: userInfo
        )
    }

    private func replaceDisplayTextIncrementally(
        in textView: UITextView,
        with displayText: String,
        selectedRange: NSRange
    ) {
        let currentText = textView.text ?? ""
        let currentNSString = currentText as NSString
        let nextNSString = displayText as NSString
        let sharedLength = min(currentNSString.length, nextNSString.length)
        var prefixLength = 0

        while prefixLength < sharedLength,
              currentNSString.character(at: prefixLength) == nextNSString.character(at: prefixLength) {
            prefixLength += 1
        }

        var currentEnd = currentNSString.length
        var nextEnd = nextNSString.length
        while currentEnd > prefixLength,
              nextEnd > prefixLength,
              currentNSString.character(at: currentEnd - 1) == nextNSString.character(at: nextEnd - 1) {
            currentEnd -= 1
            nextEnd -= 1
        }

        let changedRange = NSRange(location: prefixLength, length: currentEnd - prefixLength)
        let replacementRange = NSRange(location: prefixLength, length: nextEnd - prefixLength)
        let replacement = nextNSString.substring(with: replacementRange)

        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(
            in: changedRange,
            with: NSAttributedString(string: replacement, attributes: textAttributes)
        )
        ZoneForcedLineBreak.applyMarkerStyle(
            to: textView.textStorage,
            baseAttributes: textAttributes,
            markerColor: forcedLineBreakTintColor
        )
        textView.textStorage.endEditing()

        let clampedLocation = min(max(selectedRange.location, 0), textView.textStorage.length)
        let clampedLength = min(
            max(selectedRange.length, 0),
            textView.textStorage.length - clampedLocation
        )
        textView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
    }

    private func canInsertForcedLineBreak(in text: String, selectedRange: NSRange) -> Bool {
        let marker = ZoneForcedLineBreak.marker as NSString
        let nsText = text as NSString
        let location = min(max(selectedRange.location, 0), nsText.length)
        let end = min(max(selectedRange.location + selectedRange.length, location), nsText.length)

        if location >= marker.length {
            let previousRange = NSRange(location: location - marker.length, length: marker.length)
            if nsText.substring(with: previousRange) == marker as String {
                return false
            }
        }

        if end + marker.length <= nsText.length {
            let nextRange = NSRange(location: end, length: marker.length)
            if nsText.substring(with: nextRange) == marker as String {
                return false
            }
        }

        return true
    }

    private func handleForcedLineBreakBackspace(in textView: UITextView, range: NSRange) -> Bool {
        guard range.length == 1,
              !ZoneTextViewEmptyCaret.isPlaceholderDisplay(textView.text),
              let displayText = textView.text else {
            return false
        }

        let nsText = displayText as NSString
        guard range.location >= 0,
              range.location + range.length <= nsText.length else {
            return false
        }

        let marker = ZoneForcedLineBreak.marker as NSString
        let deletedText = nsText.substring(with: range)

        if deletedText == "\n",
           range.location >= marker.length,
           nsText.substring(with: NSRange(location: range.location - marker.length, length: marker.length)) == marker as String {
            textView.selectedRange = NSRange(location: range.location, length: 0)
            reportCursorPosition(
                from: textView,
                includeCaretAnchor: true,
                forceCaretGeometry: true,
                source: .textInput
            )
            return true
        }

        if deletedText == marker as String,
           range.location + marker.length < nsText.length,
           nsText.substring(with: NSRange(location: range.location + marker.length, length: 1)) == "\n" {
            let mutable = NSMutableString(string: displayText)
            mutable.deleteCharacters(in: NSRange(location: range.location, length: marker.length + 1))
            let nextDisplayText = mutable as String

            isUpdating = true
            textView.text = nextDisplayText.isEmpty ? ZoneTextViewEmptyCaret.placeholder : nextDisplayText
            textView.selectedRange = NSRange(location: min(range.location, (textView.text as NSString?)?.length ?? 0), length: 0)
            isUpdating = false

            recordCaretProbe(
                "caret.forced-break-backspace-after-text-set",
                textView: textView,
                changedRange: range,
                replacementText: ""
            )
            resetTextStyling(in: textView)
            textViewDidChange(textView)
            reportCursorPosition(
                from: textView,
                includeCaretAnchor: true,
                forceCaretGeometry: true,
                source: .textInput
            )
            return true
        }

        return false
    }

    private func normalizeTypingAttributes(in textView: UITextView) {
        textView.typingAttributes = textAttributes
    }

    private func resetTextStyling(in textView: UITextView) {
        textView.typingAttributes = textAttributes
        let fullRange = NSRange(location: 0, length: textView.textStorage.length)
        guard fullRange.length > 0 else { return }

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
        recordCaretProbe("caret.marker-style-before", textView: textView)
        ZoneForcedLineBreak.applyMarkerStyle(
            to: textView.textStorage,
            baseAttributes: textAttributes,
            markerColor: forcedLineBreakTintColor
        )
        recordCaretProbe("caret.marker-style-after", textView: textView)
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textView?.textAlignment ?? .left
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = max(lineSpacing, 0)

        return [
            .font: font,
            .foregroundColor: textColor,
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
    var onCaretGeometryChange: ((CGFloat, CGRect, CGFloat, ZoneEditorCaretScrollSource, String) -> Void)?
    var onCommit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    
    func makeUIView(context: Context) -> UITextView {
        // Use custom class that detects tap everywhere
        let textView = FullHitTextView()
        textView.delegate = context.coordinator
        textView.debugZoneID = zoneID
        context.coordinator.textView = textView
        context.coordinator.zoneID = zoneID
        textView.debugZoneID = zoneID
        context.coordinator.font = font
        context.coordinator.textColor = textColor
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
        updateScrollBehavior(of: textView)
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
        context.coordinator.textColor = textColor
        context.coordinator.lineSpacing = lineSpacing
        context.coordinator.contentInset = contentInset
        context.coordinator.maximumVisibleHeight = maximumVisibleHeight
        context.coordinator.forcedLineBreakTintColor = forcedLineBreakTintColor
        (textView as? FullHitTextView)?.usesCompactCaret = true
        if AppFeatures.current.showsVisualDebugOverlays {
            let modelText = ZoneTextViewEmptyCaret.modelText(from: textView.text ?? "")
            let textLength = (modelText as NSString).length
            ZoneEditorDebugStore.shared.recordLayoutEvent(
                "ui-update",
                zoneID: zoneID,
                details: "frame=\(debugRect(textView.frame)) bounds=\(debugSize(textView.bounds.size)) containerW=\(debugValue(textView.textContainer.size.width)) requestFR=\(isFirstResponder ? 1 : 0) actualFR=\(textView.isFirstResponder ? 1 : 0) len=\(textLength)"
            )
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
        let uiModelText = ZoneTextViewEmptyCaret.modelText(from: textView.text ?? "")

        guard textView.text != displayText else {
            if needsStylingUpdate {
                updateStyling(of: textView)
                context.coordinator.lastAppliedStylingSignature = stylingSignature
            }
            updateScrollBehavior(of: textView)
            context.coordinator.recordCaretProbe(
                "caret.ui-update-unchanged",
                textView: textView,
                extra: "needsStyle=\(needsStylingUpdate ? 1 : 0)"
            )
            ZoneEditorDebugStore.shared.recordTextSync(
                "ui-sync",
                zoneID: zoneID,
                modelLength: (text as NSString).length,
                uiLength: (uiModelText as NSString).length,
                lastAcceptedLength: context.coordinator.lastAcceptedTextLength,
                isUpdating: context.coordinator.isUpdating,
                isFirstResponder: textView.isFirstResponder,
                selectedRange: textView.selectedRange,
                action: "unchanged"
            )
            context.coordinator.rememberAcceptedText(text, selectedRange: textView.selectedRange)
            syncFocus(textView: textView, isFirstResponder: isFirstResponder, context: context)
            return
        }

        if context.coordinator.shouldDeferModelSync(
            modelText: text,
            uiModelText: uiModelText,
            textView: textView
        ) {
            if needsStylingUpdate {
                updateStyling(of: textView)
                context.coordinator.lastAppliedStylingSignature = stylingSignature
            }
            updateScrollBehavior(of: textView)
            context.coordinator.recordCaretProbe(
                "caret.ui-update-defer-live-ui",
                textView: textView,
                extra: "needsStyle=\(needsStylingUpdate ? 1 : 0)"
            )
            ZoneEditorDebugStore.shared.recordTextSync(
                "ui-sync",
                zoneID: zoneID,
                modelLength: (text as NSString).length,
                uiLength: (uiModelText as NSString).length,
                lastAcceptedLength: context.coordinator.lastAcceptedTextLength,
                isUpdating: context.coordinator.isUpdating,
                isFirstResponder: textView.isFirstResponder,
                selectedRange: textView.selectedRange,
                action: "defer-live-ui"
            )
            syncFocus(textView: textView, isFirstResponder: isFirstResponder, context: context)
            return
        }

        let selectedRange = ZoneTextViewEmptyCaret.modelRange(
            from: textView.selectedRange,
            displayText: textView.text ?? ""
        )
        context.coordinator.recordCaretProbe(
            "caret.ui-update-before-apply-model",
            textView: textView,
            extra: "incomingModelLen=\((text as NSString).length) selectedModel=\(selectedRange.location):\(selectedRange.length)"
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
        context.coordinator.recordCaretProbe(
            "caret.ui-update-after-apply-model",
            textView: textView,
            extra: "incomingModelLen=\((text as NSString).length) appliedDisplay=\(displayRange.location):\(displayRange.length)"
        )

        if needsStylingUpdate || displayText.contains(ZoneForcedLineBreak.marker) {
            updateStyling(of: textView)
            context.coordinator.lastAppliedStylingSignature = stylingSignature
        }
        updateScrollBehavior(of: textView)
        context.coordinator.recordCaretProbe(
            "caret.ui-update-after-style",
            textView: textView,
            extra: "needsStyle=\(needsStylingUpdate ? 1 : 0) containsMarker=\(displayText.contains(ZoneForcedLineBreak.marker) ? 1 : 0)"
        )
        ZoneEditorDebugStore.shared.recordTextSync(
            "ui-sync",
            zoneID: zoneID,
            modelLength: (text as NSString).length,
            uiLength: (uiModelText as NSString).length,
            lastAcceptedLength: context.coordinator.lastAcceptedTextLength,
            isUpdating: context.coordinator.isUpdating,
            isFirstResponder: textView.isFirstResponder,
            selectedRange: textView.selectedRange,
            action: "apply-model"
        )
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
                guard !manager.isSuppressingFocusRequests else {
                    ZoneEditorDebugStore.shared.recordFocusEvent("sync become ignored", zoneID: zoneID)
                    return
                }
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
            let manager = ZoneFocusManager.shared
            guard !manager.shouldRetainKeyboard,
                  manager.focusedZoneID == nil,
                  manager.pendingFocusZoneID == nil else {
                ZoneEditorDebugStore.shared.recordFocusEvent("sync keepFR for transfer", zoneID: zoneID)
                return
            }
            guard context.coordinator.focusSyncState != .resigningFirstResponder else { return }
            context.coordinator.focusSyncState = .resigningFirstResponder
            DispatchQueue.main.async {
                defer { context.coordinator.focusSyncState = .idle }
                guard ZoneFocusManager.shared.focusedZoneID == nil,
                      ZoneFocusManager.shared.pendingFocusZoneID == nil,
                      !ZoneFocusManager.shared.shouldRetainKeyboard,
                      textView.isFirstResponder else {
                    return
                }
                ZoneEditorDebugStore.shared.recordFocusEvent("sync resign explicit", zoneID: zoneID)
                textView.resignFirstResponder()
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
        let measuredHeight = max(ceil(calculatedSize.height), ceil(font.lineHeight))
        let cappedHeight = maximumVisibleHeight
            .map { min(measuredHeight, max(ceil($0), ceil(font.lineHeight))) }
            ?? measuredHeight
        let result = CGSize(
            width: width,
            height: cappedHeight
        )

        if AppFeatures.current.showsVisualDebugOverlays {
            ZoneEditorDebugStore.shared.recordLayoutEvent(
                "ui-sizeThatFits",
                zoneID: zoneID,
                details: "proposal=\(debugOptionalValue(proposal.width))x\(debugOptionalValue(proposal.height)) target=\(debugSize(targetSize)) calculated=\(debugSize(calculatedSize)) result=\(debugSize(result)) frame=\(debugRect(uiView.frame))"
            )
        }

        return result
    }

    private func updateScrollBehavior(of textView: UITextView) {
        guard let maximumVisibleHeight,
              maximumVisibleHeight > 0,
              textView.bounds.width > 1 else {
            if textView.isScrollEnabled {
                textView.isScrollEnabled = false
            }
            return
        }

        textView.layoutIfNeeded()
        let targetSize = CGSize(
            width: textView.bounds.width,
            height: UIView.layoutFittingCompressedSize.height
        )
        let requiredHeight = ceil(textView.sizeThatFits(targetSize).height)
        let shouldScroll = requiredHeight > ceil(maximumVisibleHeight) + 0.5
        if textView.isScrollEnabled != shouldScroll {
            textView.isScrollEnabled = shouldScroll
        }
    }

    private func debugRect(_ rect: CGRect) -> String {
        "\(debugValue(rect.minX)),\(debugValue(rect.minY)),\(debugValue(rect.width))x\(debugValue(rect.height))"
    }

    private func debugSize(_ size: CGSize) -> String {
        "\(debugValue(size.width))x\(debugValue(size.height))"
    }

    private func debugOptionalValue(_ value: CGFloat?) -> String {
        value.map(debugValue) ?? "nil"
    }

    private func debugValue(_ value: CGFloat) -> String {
        guard value.isFinite else { return value.description }
        return String(format: "%.1f", Double(value))
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
            textColorSignature: colorSignature(textColor),
            markerColorSignature: colorSignature(forcedLineBreakTintColor),
            textAlignment: textAlignment.rawValue,
            lineSpacing: lineSpacing,
            contentInsetTop: contentInset.top,
            contentInsetLeft: contentInset.left,
            contentInsetBottom: contentInset.bottom,
            contentInsetRight: contentInset.right,
            isPlaceholderDisplay: text.isEmpty
        )
    }

    private func colorSignature(_ color: UIColor) -> String {
        let resolved = color.resolvedColor(with: UITraitCollection.current)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return "\(red):\(green):\(blue):\(alpha)"
        }
        return resolved.description
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
    let textColorSignature: String
    let markerColorSignature: String
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
