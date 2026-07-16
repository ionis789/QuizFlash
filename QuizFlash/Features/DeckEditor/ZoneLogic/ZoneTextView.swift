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
    static let terminalBufferUTF16Length = (terminalBuffer as NSString).length

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
        let displayLength = (displayText as NSString).length
        guard hasTerminalBuffer(displayText) else { return displayLength }
        return max(displayLength - terminalBufferUTF16Length, 0)
    }

    static func hasTerminalBuffer(_ displayText: String) -> Bool {
        displayText.hasSuffix(terminalBuffer)
    }

    static func modelRange(from displayRange: NSRange, displayText: String) -> NSRange {
        let nsText = displayText as NSString
        let editableLength = editableDisplayLength(in: displayText)
        let clampedLocation = min(max(displayRange.location, 0), editableLength)
        let clampedEnd = min(max(displayRange.location + displayRange.length, clampedLocation), editableLength)
        let prefixRange = NSRange(location: 0, length: clampedLocation)
        let selectionRange = NSRange(location: clampedLocation, length: clampedEnd - clampedLocation)
        let placeholdersBefore = occurrenceCount(of: placeholder, in: nsText, range: prefixRange)
        let placeholdersInSelection = occurrenceCount(of: placeholder, in: nsText, range: selectionRange)
        let visualBreak = ZoneForcedLineBreak.marker + "\n"
        let visualBreaksBefore = occurrenceCount(of: visualBreak, in: nsText, range: prefixRange)
        let visualBreaksInSelection = occurrenceCount(of: visualBreak, in: nsText, range: selectionRange)

        return NSRange(
            location: max(clampedLocation - placeholdersBefore - visualBreaksBefore, 0),
            length: max((clampedEnd - clampedLocation) - placeholdersInSelection - visualBreaksInSelection, 0)
        )
    }

    static func displayRange(fromModelRange range: NSRange, modelText: String) -> NSRange {
        let nsText = modelText as NSString
        let clampedLocation = min(max(range.location, 0), nsText.length)
        let clampedEnd = min(max(range.location + range.length, clampedLocation), nsText.length)
        let markersBefore = occurrenceCount(
            of: ZoneForcedLineBreak.marker,
            in: nsText,
            range: NSRange(location: 0, length: clampedLocation)
        )
        let markersInSelection = occurrenceCount(
            of: ZoneForcedLineBreak.marker,
            in: nsText,
            range: NSRange(location: clampedLocation, length: clampedEnd - clampedLocation)
        )
        return NSRange(
            location: clampedLocation + markersBefore,
            length: (clampedEnd - clampedLocation) + markersInSelection
        )
    }

    private static func stripTerminalBuffer(from displayText: String) -> String {
        guard displayText.hasSuffix(terminalBuffer) else { return displayText }
        return String(displayText.dropLast(terminalBuffer.count))
    }

    private static func occurrenceCount(
        of needle: String,
        in text: NSString,
        range: NSRange
    ) -> Int {
        guard !needle.isEmpty, range.length > 0 else { return 0 }

        var count = 0
        var searchRange = range
        while searchRange.length > 0 {
            let match = text.range(of: needle, options: [], range: searchRange)
            guard match.location != NSNotFound else { break }
            count += 1
            let nextLocation = match.location + match.length
            let searchEnd = NSMaxRange(range)
            searchRange = NSRange(
                location: nextLocation,
                length: max(searchEnd - nextLocation, 0)
            )
        }
        return count
    }
}

// MARK: - Full Hit Text View
/// Custom UITextView that keeps selection stable inside the editor surface.
final class FullHitTextView: UITextView {
    var usesCompactCaret: Bool = true
    var debugZoneID: UUID?
    var debugPathID: String?
    var estimatedLineAdvanceY: CGFloat = 0
    private var lastStableCaretRect: CGRect?
    private var transientTailCaretSynthesisDeadline: CFTimeInterval = 0
    private var transientTailCaretAdvanceY: CGFloat?

    override func caretRect(for position: UITextPosition) -> CGRect {
        let proposedRect = super.caretRect(for: position)
        var rect = proposedRect
        guard usesCompactCaret else { return proposedRect }

        rect.size.width = 2.1
        if let invalidReason = unstableCaretRectReason(proposedRect) {
            if let synthesizedRect = synthesizedTailCaretRect(for: proposedRect) {
                lastStableCaretRect = synthesizedRect
                if AppFeatures.current.showsVisualDebugOverlays {
                    ZoneEditorDebugStore.shared.recordLayoutEvent(
                        "caret.invalid-rect-synthesized",
                        zoneID: debugZoneID,
                        details: "reason=\(invalidReason) selected=\(selectedRange.location):\(selectedRange.length) textLen=\(((text ?? "") as NSString).length) proposed=\(debugRect(proposedRect)) synthesized=\(debugRect(synthesizedRect)) bounds=\(debugSize(bounds.size)) content=\(debugSize(contentSize))"
                    )
                }
                return synthesizedRect
            }

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
        transientTailCaretSynthesisDeadline = 0
        transientTailCaretAdvanceY = nil
        return rect
    }

    func beginTransientTailCaretSynthesis(advanceY: CGFloat) {
        transientTailCaretAdvanceY = max(advanceY, 1)
        transientTailCaretSynthesisDeadline = CACurrentMediaTime() + 0.25
    }

    func refineTransientTailCaretSynthesis(advanceY: CGFloat) {
        guard transientTailCaretSynthesisDeadline > CACurrentMediaTime() else { return }
        transientTailCaretAdvanceY = max(advanceY, 1)
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

    private func synthesizedTailCaretRect(for proposedRect: CGRect) -> CGRect? {
        guard transientTailCaretSynthesisDeadline > CACurrentMediaTime(),
              let lastStableCaretRect,
              selectedRange.length == 0,
              isSelectionNearEditableTail(),
              proposedRect.maxY <= textContainerInset.top + 4 else {
            return nil
        }

        let advanceY = transientTailCaretAdvanceY ?? estimatedLineAdvanceY
        guard advanceY > 1 else { return nil }

        var rect = lastStableCaretRect
        rect.origin.x = textContainerInset.left
        rect.origin.y = lastStableCaretRect.minY + advanceY
        rect.size.width = 2.1
        return rect
    }

    private func isSelectionNearEditableTail() -> Bool {
        let editableLength = max(
            textStorage.length - ZoneTextViewEmptyCaret.terminalBufferUTF16Length,
            0
        )
        guard editableLength > 0 else { return false }
        return selectedRange.location >= max(editableLength - 2, 0)
    }

    private func isTransientTailResetCaretRect(_ rect: CGRect) -> Bool {
        guard lastStableCaretRect != nil else { return false }
        let textLength = textStorage.length
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
        let hitView = bounds.contains(point) ? self : super.hitTest(point, with: event)
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.hit-test",
            zoneID: debugZoneID,
            pathID: debugPathID,
            textView: self,
            details: "point=\(debugPoint(point)) hit=\(hitView.map { String(describing: type(of: $0)) } ?? "nil") boundsContains=\(bounds.contains(point) ? 1 : 0)"
        )
        if self.bounds.contains(point) {
            return self
        }
        return hitView
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let editableLength = max(
            textStorage.length - ZoneTextViewEmptyCaret.terminalBufferUTF16Length,
            0
        )
        let hasSelection = selectedRange.length > 0
        let result: Bool

        switch action {
        case #selector(UIResponderStandardEditActions.copy(_:)):
            result = hasSelection
        case #selector(UIResponderStandardEditActions.cut(_:)),
             #selector(UIResponderStandardEditActions.delete(_:)):
            result = isEditable && hasSelection
        case #selector(UIResponderStandardEditActions.paste(_:)):
            result = isEditable && UIPasteboard.general.hasStrings
        case #selector(UIResponderStandardEditActions.select(_:)):
            result = editableLength > 0 && selectedRange.length == 0
        case #selector(UIResponderStandardEditActions.selectAll(_:)):
            result = editableLength > 0 && selectedRange.length < editableLength
        default:
            result = super.canPerformAction(action, withSender: sender)
        }
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.can-perform-action",
            zoneID: debugZoneID,
            pathID: debugPathID,
            textView: self,
            details: "selector=\(NSStringFromSelector(action)) result=\(result ? 1 : 0) editableLen=\(editableLength) hasSelection=\(hasSelection ? 1 : 0) pasteboardStrings=\(UIPasteboard.general.hasStrings ? 1 : 0)"
        )
        return result
    }

    override func target(forAction action: Selector, withSender sender: Any?) -> Any? {
        let target = super.target(forAction: action, withSender: sender)
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.target-for-action",
            zoneID: debugZoneID,
            pathID: debugPathID,
            textView: self,
            details: "selector=\(NSStringFromSelector(action)) target=\(target.map { String(describing: type(of: $0 as AnyObject)) } ?? "nil")"
        )
        return target
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.build-menu-before",
            zoneID: debugZoneID,
            pathID: debugPathID,
            textView: self,
            details: "builder=\(String(describing: type(of: builder)))"
        )
        super.buildMenu(with: builder)
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.build-menu-after",
            zoneID: debugZoneID,
            pathID: debugPathID,
            textView: self,
            details: "builder=\(String(describing: type(of: builder)))"
        )
    }

    override func copy(_ sender: Any?) {
        recordEditAction("copy")
        super.copy(sender)
    }

    override func cut(_ sender: Any?) {
        recordEditAction("cut")
        super.cut(sender)
    }

    override func paste(_ sender: Any?) {
        recordEditAction("paste")
        super.paste(sender)
    }

    override func select(_ sender: Any?) {
        recordEditAction("select")
        super.select(sender)
    }

    override func selectAll(_ sender: Any?) {
        recordEditAction("selectAll")
        super.selectAll(sender)
    }

    override func delete(_ sender: Any?) {
        recordEditAction("delete")
        super.delete(sender)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        recordTouches("text.touches-began", touches: touches, event: event)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        recordTouches("text.touches-moved", touches: touches, event: event)
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        recordTouches("text.touches-ended", touches: touches, event: event)
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        recordTouches("text.touches-cancelled", touches: touches, event: event)
        super.touchesCancelled(touches, with: event)
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
        ZoneEditorDebugStore.shared.recordLayoutEvent(
            "ui-layout",
            zoneID: debugZoneID,
            details: "frame=\(debugRect(frame)) bounds=\(debugSize(bounds.size)) containerW=\(debugValue(textContainer.size.width)) content=\(debugSize(contentSize)) inset=\(debugInsets(textContainerInset)) len=\(textStorage.length) fr=\(isFirstResponder ? 1 : 0)"
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

    private func recordEditAction(_ name: String) {
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.action-\(name)",
            zoneID: debugZoneID,
            pathID: debugPathID,
            textView: self,
            details: "pasteboardStrings=\(UIPasteboard.general.hasStrings ? 1 : 0)"
        )
    }

    private func recordTouches(_ stage: String, touches: Set<UITouch>, event: UIEvent?) {
        guard AppFeatures.current.showsVisualDebugOverlays else { return }
        let descriptions = touches.map { touch in
            let location = touch.location(in: self)
            let previous = touch.previousLocation(in: self)
            return "phase=\(touchPhaseName(touch.phase)) taps=\(touch.tapCount) loc=\(debugPoint(location)) prev=\(debugPoint(previous)) type=\(touchTypeName(touch.type))"
        }
        .joined(separator: " | ")
        let gestureSummary = (gestureRecognizers ?? [])
            .map { "\(String(describing: type(of: $0))):\(gestureStateName($0.state)):\($0.isEnabled ? "E" : "-")\($0.cancelsTouchesInView ? "C" : "-")" }
            .joined(separator: ",")
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            stage,
            zoneID: debugZoneID,
            pathID: debugPathID,
            textView: self,
            details: "touches=[\(descriptions)] eventType=\(event.map { String(describing: $0.type) } ?? "nil") gestures=\(gestureSummary.isEmpty ? "none" : gestureSummary)"
        )
    }

    private func touchPhaseName(_ phase: UITouch.Phase) -> String {
        switch phase {
        case .began: "began"
        case .moved: "moved"
        case .stationary: "stationary"
        case .ended: "ended"
        case .cancelled: "cancelled"
        case .regionEntered: "regionEntered"
        case .regionMoved: "regionMoved"
        case .regionExited: "regionExited"
        @unknown default: "unknown"
        }
    }

    private func touchTypeName(_ type: UITouch.TouchType) -> String {
        switch type {
        case .direct: "direct"
        case .indirect: "indirect"
        case .pencil: "pencil"
        case .indirectPointer: "indirectPointer"
        @unknown default: "unknown"
        }
    }

    private func gestureStateName(_ state: UIGestureRecognizer.State) -> String {
        switch state {
        case .possible: "possible"
        case .began: "began"
        case .changed: "changed"
        case .ended: "ended"
        case .cancelled: "cancelled"
        case .failed: "failed"
        @unknown default: "unknown"
        }
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

    private struct SheetDismissTraceSession {
        let id: Int
        let title: String
        let startedAt: Date
        let startedAtElapsedMS: Int
        var events: [String]

        var summary: String {
            "#\(id) \(title) events=\(events.count) +\(startedAtElapsedMS)ms"
        }
    }

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
    private(set) var dismissLine: String = "dismiss idle"
    private(set) var layoutEvents: [String] = []
    private(set) var toolbarLifecycleEvents: [String] = []
    private(set) var dismissFlowEvents: [String] = []
    private(set) var sheetDismissTraceEvents: [String] = []
    private(set) var editorStateEvents: [String] = []
    private(set) var nativeTextEvents: [String] = []
    private var layoutEventIndex = 0
    private var toolbarLifecycleEventIndex = 0
    private var dismissFlowEventIndex = 0
    private var sheetDismissTraceEventIndex = 0
    private var editorStateEventIndex = 0
    private var nativeTextEventIndex = 0
    private var sheetDismissTraceActiveUntil: Date?
    private var activeSheetDismissTraceSessionID: Int?
    private var sheetDismissTraceSessionIndex = 0
    private var sheetDismissTraceSessions: [SheetDismissTraceSession] = []
    private var eventCounters: [String: Int] = [:]
    private var skippedEventCounters: [String: Int] = [:]
    private var cachedCounterSummary = "none"
    private var isRecordingEnabled = false
    private let startedAt = Date()

    private init() {}

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
            caretLine,
            dismissLine,
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
            dismissLine,
            "rates \(counterSummary)",
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
        details: @autoclosure () -> String
    ) {
        guard AppFeatures.current.showsVisualDebugOverlays, isRecordingEnabled else { return }

        eventCounters[stage, default: 0] += 1
        refreshCounterSummaryIfNeeded(for: stage)
        if let sampleInterval = layoutEventSampleInterval(for: stage) {
            let count = eventCounters[stage, default: 0]
            if count > 3 && !count.isMultiple(of: sampleInterval) {
                skippedEventCounters[stage, default: 0] += 1
                return
            }
        }

        layoutEventIndex += 1
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let path = pathID.map { " path=\($0)" } ?? ""
        let line = "L\(layoutEventIndex) +\(elapsedMS)ms \(stage) zone=\(shortID(zoneID))\(path) \(details())"
        layoutEvents.append(line)
        if layoutEvents.count > 900 {
            layoutEvents.removeFirst(layoutEvents.count - 900)
        }
    }

    func recordDismissFlow(
        _ stage: String,
        details: @autoclosure () -> String = ""
    ) {
        guard AppFeatures.current.showsVisualDebugOverlays else { return }

        dismissFlowEventIndex += 1
        eventCounters["dismiss.\(stage)", default: 0] += 1
        refreshCounterSummaryIfNeeded(for: "dismiss.\(stage)")

        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let detailText = details()
        let line = detailText.isEmpty
            ? "D\(dismissFlowEventIndex) +\(elapsedMS)ms \(stage)"
            : "D\(dismissFlowEventIndex) +\(elapsedMS)ms \(stage) \(detailText)"
        dismissFlowEvents.append(line)
        if dismissFlowEvents.count > 240 {
            dismissFlowEvents.removeFirst(dismissFlowEvents.count - 240)
        }

        setLine(&dismissLine, line)
        recordEvent("dismiss.\(stage)")
    }

    var isSheetDismissTraceActive: Bool {
        guard let sheetDismissTraceActiveUntil else { return false }
        return sheetDismissTraceActiveUntil > Date()
    }

    func beginSheetDismissTrace(
        _ stage: String,
        details: @autoclosure () -> String = ""
    ) {
        guard AppFeatures.current.showsVisualDebugOverlays else { return }
        sheetDismissTraceActiveUntil = Date().addingTimeInterval(8)
        sheetDismissTraceSessionIndex += 1
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let session = SheetDismissTraceSession(
            id: sheetDismissTraceSessionIndex,
            title: stage,
            startedAt: Date(),
            startedAtElapsedMS: elapsedMS,
            events: []
        )
        sheetDismissTraceSessions.append(session)
        if sheetDismissTraceSessions.count > 8 {
            sheetDismissTraceSessions.removeFirst(sheetDismissTraceSessions.count - 8)
        }
        activeSheetDismissTraceSessionID = session.id
        recordSheetDismissTrace(stage, details: details())
    }

    func recordSheetDismissTrace(
        _ stage: String,
        details: @autoclosure () -> String = ""
    ) {
        guard AppFeatures.current.showsVisualDebugOverlays else { return }
        guard isSheetDismissTraceActive || stage.contains("begin") || stage.contains("start") else { return }

        sheetDismissTraceEventIndex += 1
        eventCounters["sheet-dismiss.\(stage)", default: 0] += 1
        refreshCounterSummaryIfNeeded(for: "sheet-dismiss.\(stage)")

        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let detailText = details()
        let snapshot = "canvas{\(canvasLine)} toolbar{\(toolbarLine)} caret{\(caretLine)}"
        let line = detailText.isEmpty
            ? "SD\(sheetDismissTraceEventIndex) +\(elapsedMS)ms \(stage) \(snapshot)"
            : "SD\(sheetDismissTraceEventIndex) +\(elapsedMS)ms \(stage) \(detailText) \(snapshot)"
        sheetDismissTraceEvents.append(line)
        if sheetDismissTraceEvents.count > 320 {
            sheetDismissTraceEvents.removeFirst(sheetDismissTraceEvents.count - 320)
        }
        appendToActiveSheetDismissTraceSession(line)

        setLine(&dismissLine, line)
        recordEvent("sheet-dismiss.\(stage)")
    }

    var hasSheetDismissTraceHistory: Bool {
        !sheetDismissTraceSessions.isEmpty
    }

    var latestSheetDismissTraceSummary: String {
        sheetDismissTraceSessions.last?.summary ?? "none"
    }

    var latestSheetDismissTraceReport: String {
        guard let latest = sheetDismissTraceSessions.last else {
            return sheetDismissTraceReportHeader(title: "QuizFlash Last Sheet Dismiss Trace") + "\n\n<none>"
        }

        return """
        \(sheetDismissTraceReportHeader(title: "QuizFlash Last Sheet Dismiss Trace"))
        latest: \(latest.summary)
        startedAt: \(ISO8601DateFormatter().string(from: latest.startedAt))

        SESSION #\(latest.id)
        \(latest.events.isEmpty ? "<none>" : latest.events.joined(separator: "\n"))
        """
    }

    var sheetDismissTraceHistoryReport: String {
        guard !sheetDismissTraceSessions.isEmpty else {
            return sheetDismissTraceReportHeader(title: "QuizFlash Sheet Dismiss Trace History") + "\n\n<none>"
        }

        let summary = sheetDismissTraceSessions
            .reversed()
            .map { "\($0.summary) started=\(ISO8601DateFormatter().string(from: $0.startedAt))" }
            .joined(separator: "\n")
        let sessions = sheetDismissTraceSessions
            .reversed()
            .map { session in
                """
                SESSION #\(session.id) \(session.title)
                \(session.events.isEmpty ? "<none>" : session.events.joined(separator: "\n"))
                """
            }
            .joined(separator: "\n\n")

        return """
        \(sheetDismissTraceReportHeader(title: "QuizFlash Sheet Dismiss Trace History"))

        RECENT SESSIONS
        \(summary)

        \(sessions)
        """
    }

    func recordEditorState(
        _ stage: String,
        details: @autoclosure () -> String = ""
    ) {
        guard AppFeatures.current.showsVisualDebugOverlays else { return }

        editorStateEventIndex += 1
        eventCounters["state.\(stage)", default: 0] += 1
        refreshCounterSummaryIfNeeded(for: "state.\(stage)")

        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let detailText = details()
        let line = detailText.isEmpty
            ? "S\(editorStateEventIndex) +\(elapsedMS)ms \(stage)"
            : "S\(editorStateEventIndex) +\(elapsedMS)ms \(stage) \(detailText)"
        editorStateEvents.append(line)
        if editorStateEvents.count > 360 {
            editorStateEvents.removeFirst(editorStateEvents.count - 360)
        }

        recordEvent("state.\(stage)")
    }

    var layoutTraceReport: String {
        let counters = counterReport
        let events = layoutEvents.isEmpty ? "<none>" : layoutEvents.joined(separator: "\n")
        let toolbarEvents = toolbarLifecycleEvents.isEmpty ? "<none>" : toolbarLifecycleEvents.joined(separator: "\n")
        let dismissEvents = dismissFlowEvents.isEmpty ? "<none>" : dismissFlowEvents.joined(separator: "\n")
        let sheetDismissEvents = sheetDismissTraceSessions.isEmpty ? "<none>" : sheetDismissTraceHistoryReport
        let stateEvents = editorStateEvents.isEmpty ? "<none>" : editorStateEvents.joined(separator: "\n")
        let nativeEvents = nativeTextEvents.isEmpty ? "<none>" : nativeTextEvents.joined(separator: "\n")
        return """
        LIVE SNAPSHOT
        \(hudLines.joined(separator: "\n"))

        COUNTERS
        \(counters)

        EDITOR DISMISS FLOW
        \(dismissEvents)

        SHEET DISMISS TRACE
        \(sheetDismissEvents)

        EDITOR STATE FLOW
        \(stateEvents)

        NATIVE TEXT INTERACTION FLOW
        \(nativeEvents)

        KEYBOARD / TOOLBAR LIFECYCLE
        \(toolbarEvents)

        EVENTS
        \(events)
        """
    }

    var report: String {
        """
        QuizFlash Zone Editor Debug
        timestamp: \(ISO8601DateFormatter().string(from: Date()))

        \(layoutTraceReport)
        """
    }

    var eventCount: Int {
        layoutEvents.count + toolbarLifecycleEvents.count + dismissFlowEvents.count + sheetDismissTraceEvents.count + editorStateEvents.count + nativeTextEvents.count
    }

    var latestLayoutLines: [String] {
        Array(layoutEvents.suffix(4))
    }

    private var counterSummary: String {
        cachedCounterSummary
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

    private func appendToActiveSheetDismissTraceSession(_ line: String) {
        guard let activeSheetDismissTraceSessionID,
              let index = sheetDismissTraceSessions.lastIndex(where: { $0.id == activeSheetDismissTraceSessionID }) else {
            return
        }

        sheetDismissTraceSessions[index].events.append(line)
        if sheetDismissTraceSessions[index].events.count > 120 {
            sheetDismissTraceSessions[index].events.removeFirst(sheetDismissTraceSessions[index].events.count - 120)
        }
    }

    private func sheetDismissTraceReportHeader(title: String) -> String {
        """
        \(title)
        timestamp: \(ISO8601DateFormatter().string(from: Date()))
        totalSessions: \(sheetDismissTraceSessions.count)
        active: \(isSheetDismissTraceActive ? "1" : "0")
        """
    }

    private func layoutEventSampleInterval(for stage: String) -> Int? {
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
            return 20
        case "leaf-layout",
             "zone-content-init",
             "zone-content-update",
             "zone-content-update-root",
             "card-editor-body",
             "caret.geometry-before-layout",
             "caret.geometry-after-layout",
             "caret.geometry-emit",
             "caret.geometry-skip-same",
             "caret.selection-change-start",
             "caret.selection-change-pending-text-edit",
             "caret.selection-change-waiting-layout",
             "caret.should-change",
             "caret.did-change-start",
             "caret.did-change-after-style",
             "caret.overflow-decision",
             "caret.settled-schedule",
             "caret.settled-runloop-before-layout",
             "caret.settled-runloop-after-layout",
             "caret.settled-followup-before-layout",
             "caret.settled-followup-after-layout",
             "caret-geometry",
             "scroll-native-rect-request",
             "scroll-apply",
             "scroll-set-offset-start",
             "scroll-offset-observed":
            return 80
        default:
            return nil
        }
    }

    private func refreshCounterSummaryIfNeeded(for stage: String) {
        let count = eventCounters[stage, default: 0]
        guard count <= 3 || count.isMultiple(of: 25) else { return }

        let hot = eventCounters
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(4)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        cachedCounterSummary = hot.isEmpty ? "none" : hot
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

    func recordNativeTextEvent(
        _ stage: String,
        zoneID: UUID?,
        pathID: String?,
        textView: UITextView?,
        details: @autoclosure () -> String = ""
    ) {
        guard AppFeatures.current.showsVisualDebugOverlays else { return }

        nativeTextEventIndex += 1
        eventCounters["native.\(stage)", default: 0] += 1
        refreshCounterSummaryIfNeeded(for: "native.\(stage)")

        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let snapshot = nativeTextSnapshot(textView)
        let path = pathID.map { " path=\($0)" } ?? ""
        let detailText = details()
        let line = detailText.isEmpty
            ? "N\(nativeTextEventIndex) +\(elapsedMS)ms \(stage) zone=\(shortID(zoneID))\(path) \(snapshot)"
            : "N\(nativeTextEventIndex) +\(elapsedMS)ms \(stage) zone=\(shortID(zoneID))\(path) \(snapshot) \(detailText)"
        nativeTextEvents.append(line)
        if nativeTextEvents.count > 900 {
            nativeTextEvents.removeFirst(nativeTextEvents.count - 900)
        }
        recordEvent("native.\(stage)")
    }

    func recordScrollDecision(
        _ stage: String,
        zoneID: UUID?,
        details: @autoclosure () -> String
    ) {
        recordLayoutEvent(stage, zoneID: zoneID, details: details())
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

    private func nativeTextSnapshot(_ textView: UITextView?) -> String {
        let focus = ZoneFocusManager.shared
        guard let textView else {
            return "fr=nil selected=nil len=nil focus=\(shortID(focus.focusedZoneID)) pending=\(shortID(focus.pendingFocusZoneID)) retain=\(flag(focus.shouldRetainKeyboard))"
        }

        let displayLength = textView.textStorage.length
        let editableLength = max(
            displayLength - ZoneTextViewEmptyCaret.terminalBufferUTF16Length,
            0
        )
        let windowName = textView.window.map { String(describing: type(of: $0)) } ?? "nil"
        return "fr=\(flag(textView.isFirstResponder)) editable=\(flag(textView.isEditable)) selectable=\(flag(textView.isSelectable)) selected=\(textView.selectedRange.location):\(textView.selectedRange.length) len=\(displayLength)/editable=\(editableLength) marked=\(textView.markedTextRange == nil ? "0" : "1") window=\(windowName) focus=\(shortID(focus.focusedZoneID)) pending=\(shortID(focus.pendingFocusZoneID)) retain=\(flag(focus.shouldRetainKeyboard)) suppress=\(flag(focus.isSuppressingFocusRequests))"
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
    var pathID: String?
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
    private var lastAcceptedTextUsesForcedLineBreakMarkers = false
    private var lastAcceptedSelectedRange: NSRange = NSRange(location: 0, length: 0)
    var isUpdating: Bool = false
    weak var textView: UITextView?
    private var focusObserver: NSObjectProtocol?
    private var forcedLineBreakObserver: NSObjectProtocol?
    private var lastReportedCursorRange: NSRange?
    private var lastReportedText: String?
    private var lastReportedLineInfo: (zoneID: UUID?, lineIndex: Int, totalLines: Int)?
    private var lineInfoText: String?
    private var newlineUTF16Offsets: [Int] = []
    private var measurementRevision = 0
    private var cachedMeasurement: (width: CGFloat, revision: Int, size: CGSize)?
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
        if gestureRecognizer.name == Self.doubleTapPassthroughRecognizerName {
            return true
        }

        guard gestureRecognizer.name == Self.selectionCollapseTapRecognizerName,
              let textView,
              textView.isFirstResponder,
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
              textView.isFirstResponder,
              textView.selectedRange.length > 0 else {
            return
        }

        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.selection-collapse-tap",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "point=\(debugPoint(recognizer.location(in: textView)))"
        )
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

        ZoneEditorDebugStore.shared.recordLayoutEvent(
            stage,
            zoneID: zoneID,
            details: caretProbeDetails(
                textView: textView,
                changedRange: changedRange,
                replacementText: replacementText,
                extra: extra
            )
        )
    }

    private func caretProbeDetails(
        textView: UITextView,
        changedRange: NSRange?,
        replacementText: String?,
        extra: String
    ) -> String {
        let displayRange = textView.selectedRange
        let displayLength = textView.textStorage.length
        if displayLength >= ZoneTextPerformancePolicy.oversizedUTF16Threshold {
            let changed = changedRange.map { "\($0.location):\($0.length)" } ?? "nil"
            let replacement = replacementText.map(debugReplacementText) ?? "nil"
            return [
                "displaySel=\(displayRange.location):\(displayRange.length)",
                "modelSel=deferred-large-text",
                "change=\(changed)",
                "repl=\(replacement)",
                "displayLen=\(displayLength)",
                "modelLen=\((lastAcceptedText as NSString).length)",
                "storageLen=\(textView.textStorage.length)",
                "fr=\(textView.isFirstResponder ? 1 : 0)",
                "updating=\(isUpdating ? 1 : 0)",
                "bounds=\(debugRect(textView.bounds))",
                "offset=\(debugPoint(textView.contentOffset))",
                extra,
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        }

        let displayText = textView.text ?? ""
        let modelText = ZoneTextViewEmptyCaret.modelText(from: displayText)
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
            extra,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        return details
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
        if storageLength >= ZoneTextPerformancePolicy.oversizedUTF16Threshold {
            layoutManager.ensureLayout(forGlyphRange: glyphRange)
        } else {
            layoutManager.ensureLayout(for: textContainer)
        }
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

    private func menuElementSummary(_ elements: [UIMenuElement], depth: Int = 0) -> String {
        guard !elements.isEmpty else { return "[]" }

        return elements
            .prefix(18)
            .map { element in
                let typeName = String(describing: type(of: element))
                let title = debugEscaped(element.title)
                let indent = depth > 0 ? String(repeating: ".", count: depth) : ""

                if let action = element as? UIAction {
                    return "\(indent)\(typeName)(title=\"\(title)\",id=\(action.identifier.rawValue),attr=\(action.attributes.rawValue),state=\(action.state.rawValue))"
                }

                if let menu = element as? UIMenu {
                    let children = menuElementSummary(menu.children, depth: depth + 1)
                    return "\(indent)\(typeName)(title=\"\(title)\",id=\(menu.identifier.rawValue),children=\(children))"
                }

                return "\(indent)\(typeName)(title=\"\(title)\")"
            }
            .joined(separator: " | ")
    }

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        guard !ZoneFocusManager.shared.isSuppressingFocusRequests else {
            ZoneEditorDebugStore.shared.recordFocusEvent("textView shouldBegin ignored", zoneID: zoneID)
            ZoneEditorDebugStore.shared.recordNativeTextEvent(
                "text.should-begin-editing",
                zoneID: zoneID,
                pathID: pathID,
                textView: textView,
                details: "result=0 reason=suppressingFocus"
            )
            return false
        }
        if let zoneID {
            postWillFocusNotification(for: zoneID)
        }
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.should-begin-editing",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "result=1"
        )
        return true
    }

    func textView(
        _ textView: UITextView,
        editMenuForTextIn range: NSRange,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.edit-menu-request",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "range=\(range.location):\(range.length) suggestedCount=\(suggestedActions.count) suggested=\(menuElementSummary(suggestedActions)) result=default"
        )
        return nil
    }

    @available(iOS 26.0, *)
    func textView(
        _ textView: UITextView,
        editMenuForTextInRanges ranges: [NSValue],
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        let rangeList = ranges
            .map(\.rangeValue)
            .map { "\($0.location):\($0.length)" }
            .joined(separator: ",")
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.edit-menu-request-ranges",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "ranges=\(rangeList) suggestedCount=\(suggestedActions.count) suggested=\(menuElementSummary(suggestedActions)) result=default"
        )
        return nil
    }

    func textView(
        _ textView: UITextView,
        willPresentEditMenuWith animator: UIEditMenuInteractionAnimating
    ) {
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.edit-menu-will-present",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "animator=\(String(describing: type(of: animator)))"
        )
    }

    func textView(
        _ textView: UITextView,
        willDismissEditMenuWith animator: UIEditMenuInteractionAnimating
    ) {
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.edit-menu-will-dismiss",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "animator=\(String(describing: type(of: animator)))"
        )
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

        let projectedLength = max(
            textView.textStorage.length - range.length + (text as NSString).length,
            0
        )
        if projectedLength >= ZoneTextPerformancePolicy.oversizedUTF16Threshold,
           !textView.layoutManager.allowsNonContiguousLayout {
            textView.layoutManager.allowsNonContiguousLayout = true
            ZoneEditorDebugStore.shared.recordNativeTextEvent(
                "text.layout-policy-promote-before-edit",
                zoneID: zoneID,
                pathID: pathID,
                textView: textView,
                details: "projectedLen=\(projectedLength) nonContiguous=1"
            )
        }

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
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.did-change",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "isUpdating=\(isUpdating ? 1 : 0)"
        )
        recordCaretProbe("caret.did-change-start", textView: textView)
        normalizePlaceholderIfNeeded(in: textView)
        guard let displayText = textView.text else { return }
        guard !isUpdating else { return }
        invalidateMeasurement()

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
        let beforeClamp = textView.selectedRange
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.did-change-selection",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "beforeClamp=\(beforeClamp.location):\(beforeClamp.length) isUpdating=\(isUpdating ? 1 : 0)"
        )
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
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.did-begin-editing",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView
        )
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
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.did-end-editing",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView
        )
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
        let text = lastAcceptedText
        let nsRange: NSRange
        if lastAcceptedTextUsesForcedLineBreakMarkers {
            guard let displayText = textView.text else { return }
            nsRange = ZoneTextViewEmptyCaret.modelRange(
                from: textView.selectedRange,
                displayText: displayText
            )
        } else {
            let modelLength = (text as NSString).length
            let location = min(max(textView.selectedRange.location, 0), modelLength)
            let end = min(
                max(textView.selectedRange.location + textView.selectedRange.length, location),
                modelLength
            )
            nsRange = NSRange(location: location, length: end - location)
        }
        if lastReportedCursorRange != nsRange || lastReportedText != text {
            lastReportedCursorRange = nsRange
            lastReportedText = text
            onCursorChange?(nsRange, text)
        }

        let (focusedLineIndex, totalLines) = lineInfo(from: text, location: nsRange.location)
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
            if textView.textStorage.length < ZoneTextPerformancePolicy.oversizedUTF16Threshold {
                textView.layoutManager.ensureLayout(for: textView.textContainer)
            }
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
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.remember-accepted",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "modelLen=\((modelText as NSString).length) selectedDisplay=\(selectedRange.location):\(selectedRange.length)"
        )
        lastAcceptedText = modelText
        lastAcceptedTextUsesForcedLineBreakMarkers = modelText.contains(ZoneForcedLineBreak.marker)
        if lastAcceptedTextUsesForcedLineBreakMarkers {
            let currentDisplayText = textView?.text ?? ZoneTextViewEmptyCaret.displayText(for: modelText)
            lastAcceptedSelectedRange = ZoneTextViewEmptyCaret.modelRange(
                from: selectedRange,
                displayText: currentDisplayText
            )
        } else {
            let modelLength = (modelText as NSString).length
            let location = min(max(selectedRange.location, 0), modelLength)
            let end = min(max(selectedRange.location + selectedRange.length, location), modelLength)
            lastAcceptedSelectedRange = NSRange(location: location, length: end - location)
        }
        lastText = modelText
    }

    func hasAcceptedModelText(_ modelText: String) -> Bool {
        lastAcceptedText == modelText
    }

    func invalidateMeasurement() {
        measurementRevision &+= 1
        cachedMeasurement = nil
    }

    func measuredSize(width: CGFloat, calculate: () -> CGSize) -> CGSize {
        if let cachedMeasurement,
           cachedMeasurement.revision == measurementRevision,
           abs(cachedMeasurement.width - width) <= 0.5 {
            return cachedMeasurement.size
        }

        let size = calculate()
        cachedMeasurement = (width, measurementRevision, size)
        return size
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
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.normalize-placeholder",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "original=\(originalRange.location):\(originalRange.length) applied=\(displayRange.location):\(displayRange.length)"
        )
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
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.restore-last-accepted",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "restoredLen=\((lastAcceptedText as NSString).length) applied=\(displayRange.location):\(displayRange.length)"
        )
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.024) { [weak self, weak textView] in
                guard let self,
                      let textView,
                      self.caretReportGeneration == generation,
                      textView.window != nil else { return }

                self.recordCaretProbe(
                    "caret.settled-followup-before-layout",
                    textView: textView,
                    extra: "generation=\(generation)"
                )
                textView.window?.layoutIfNeeded()
                textView.superview?.layoutIfNeeded()
                self.recordCaretProbe(
                    "caret.settled-followup-after-layout",
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

    private func clampSelectionToEditableContent(in textView: UITextView) -> Bool {
        let editableLength = max(
            textView.textStorage.length - ZoneTextViewEmptyCaret.terminalBufferUTF16Length,
            0
        )
        let selection = textView.selectedRange
        let location = min(max(selection.location, 0), editableLength)
        let length = min(max(selection.length, 0), editableLength - location)
        let clampedRange = NSRange(location: location, length: length)
        guard clampedRange != selection else { return false }

        isUpdating = true
        textView.selectedRange = clampedRange
        isUpdating = false
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.selection-clamped",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "from=\(selection.location):\(selection.length) to=\(clampedRange.location):\(clampedRange.length) editableLen=\(editableLength)"
        )
        return true
    }

    private func placeCaret(at point: CGPoint, in textView: UITextView) {
        guard let position = textView.closestPosition(to: point) else { return }

        let insertionIndex = textView.offset(
            from: textView.beginningOfDocument,
            to: position
        )
        let editableLength = max(
            textView.textStorage.length - ZoneTextViewEmptyCaret.terminalBufferUTF16Length,
            0
        )
        let clampedLocation = min(max(insertionIndex, 0), editableLength)
        textView.selectedRange = NSRange(location: clampedLocation, length: 0)
        reportCursorPosition(from: textView, includeCaretAnchor: true, source: .selectionTap)
        scheduleSettledCaretReport(from: textView, source: .selectionTap)
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
        (textView as? FullHitTextView)?.beginTransientTailCaretSynthesis(
            advanceY: font.lineHeight + max(lineSpacing, 0)
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
        (textView as? FullHitTextView)?.refineTransientTailCaretSynthesis(
            advanceY: max(nextMeasuredHeight - previousMeasuredHeight, 0)
        )
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
            ZoneEditorNewlineLayoutShiftNotification.forcedBreakIDKey: forcedBreakID,
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
        if textView.textStorage.length <= 4,
           ZoneTextViewEmptyCaret.isPlaceholderDisplay(textView.text) {
            attributes[.foregroundColor] = UIColor.clear
        }
        textView.textStorage.setAttributes(attributes, range: fullRange)
        ZoneForcedLineBreak.applyMarkerStyle(
            to: textView.textStorage,
            baseAttributes: textAttributes,
            markerColor: forcedLineBreakTintColor
        )
    }

    private func lineInfo(from text: String, location: Int) -> (lineIndex: Int, totalLines: Int) {
        if lineInfoText != text {
            lineInfoText = text
            newlineUTF16Offsets.removeAll(keepingCapacity: true)
            let nsText = text as NSString
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.length > 0 {
                let match = nsText.range(of: "\n", options: [], range: searchRange)
                guard match.location != NSNotFound else { break }
                newlineUTF16Offsets.append(match.location)
                let nextLocation = match.location + match.length
                searchRange = NSRange(
                    location: nextLocation,
                    length: max(nsText.length - nextLocation, 0)
                )
            }
        }

        let clampedLocation = max(location, 0)
        var lowerBound = 0
        var upperBound = newlineUTF16Offsets.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if newlineUTF16Offsets[middle] < clampedLocation {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        let lineIndex = lowerBound
        return (lineIndex, newlineUTF16Offsets.count + 1)
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
            .paragraphStyle: paragraphStyle,
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
    let pathID: String
    let isFirstResponder: Bool
    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((NSRange, String) -> Void)?
    var onFocusLineChange: ((Int, Int) -> Void)?
    var onCaretGeometryChange: ((CGFloat, CGRect, CGFloat, ZoneEditorCaretScrollSource, String) -> Void)?
    var onCommit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    func makeUIView(context: Context) -> UITextView {
        // This editor relies on TextKit 1 layout metrics throughout its caret,
        // overflow, and forced-line-break paths. Start in TextKit 1 so UIKit's
        // selection interactions are not invalidated by a later fallback.
        let textView = FullHitTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.debugZoneID = zoneID
        textView.debugPathID = pathID
        context.coordinator.textView = textView
        context.coordinator.zoneID = zoneID
        context.coordinator.pathID = pathID
        textView.debugZoneID = zoneID
        textView.debugPathID = pathID
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
        updateLayoutPolicy(of: textView, modelText: text)
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

        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.selection-collapse-gesture-installed",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "scope=existingSelectionOnly textKit=\(textView.textLayoutManager == nil ? 1 : 2) nonContiguous=\(textView.layoutManager.allowsNonContiguousLayout ? 1 : 0) textDragEnabled=\(textView.textDragInteraction?.isEnabled == true ? 1 : 0)"
        )
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.interactions-installed",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "interactions=\(textView.interactions.map { String(describing: type(of: $0)) }.joined(separator: "|"))"
        )

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
        context.coordinator.pathID = pathID
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
        if let fullHitTextView = textView as? FullHitTextView {
            fullHitTextView.debugZoneID = zoneID
            fullHitTextView.debugPathID = pathID
        }
        (textView as? FullHitTextView)?.usesCompactCaret = true
        updateLayoutPolicy(of: textView, modelText: text)

        let stylingSignature = stylingSignatureForCurrentState
        let needsStylingUpdate = context.coordinator.lastAppliedStylingSignature != stylingSignature
        let needsFocusSync = textView.isFirstResponder != isFirstResponder
        let alreadyHasModelText = context.coordinator.hasAcceptedModelText(text)

        if alreadyHasModelText {
            if needsStylingUpdate {
                context.coordinator.invalidateMeasurement()
                updateStyling(of: textView)
                context.coordinator.lastAppliedStylingSignature = stylingSignature
            }
            updateScrollBehavior(of: textView)
            syncFocus(textView: textView, isFirstResponder: isFirstResponder, context: context)
            ZoneEditorDebugStore.shared.recordNativeTextEvent(
                "text.updateUIView-skip",
                zoneID: zoneID,
                pathID: pathID,
                textView: textView,
                details: "reason=accepted-model needsStyle=\(needsStylingUpdate ? 1 : 0) needsFocus=\(needsFocusSync ? 1 : 0)"
            )
            return
        }

        let displayText = ZoneTextViewEmptyCaret.displayText(for: text)
        let uiModelText = ZoneTextViewEmptyCaret.modelText(from: textView.text ?? "")
        if AppFeatures.current.showsVisualDebugOverlays {
            let textLength = (uiModelText as NSString).length
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
                textLength: textLength
            )
        }

        guard textView.text != displayText else {
            ZoneEditorDebugStore.shared.recordNativeTextEvent(
                "text.updateUIView-unchanged",
                zoneID: zoneID,
                pathID: pathID,
                textView: textView,
                details: "needsStyle=\(needsStylingUpdate ? 1 : 0) needsFocus=\(needsFocusSync ? 1 : 0)"
            )
            if needsStylingUpdate {
                context.coordinator.invalidateMeasurement()
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
            ZoneEditorDebugStore.shared.recordNativeTextEvent(
                "text.updateUIView-defer-live-ui",
                zoneID: zoneID,
                pathID: pathID,
                textView: textView,
                details: "incomingModelLen=\((text as NSString).length) uiModelLen=\((uiModelText as NSString).length) needsStyle=\(needsStylingUpdate ? 1 : 0) needsFocus=\(needsFocusSync ? 1 : 0)"
            )
            if needsStylingUpdate {
                context.coordinator.invalidateMeasurement()
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
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.updateUIView-before-apply-model",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "incomingModelLen=\((text as NSString).length) uiModelLen=\((uiModelText as NSString).length) selectedModel=\(selectedRange.location):\(selectedRange.length)"
        )
        context.coordinator.invalidateMeasurement()
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
            ZoneEditorDebugStore.shared.recordNativeTextEvent(
                "text.updateUIView-restore-selection",
                zoneID: zoneID,
                pathID: pathID,
                textView: textView,
                details: "appliedDisplay=\(displayRange.location):\(displayRange.length)"
            )
        }
        context.coordinator.recordCaretProbe(
            "caret.ui-update-after-apply-model",
            textView: textView,
            extra: "incomingModelLen=\((text as NSString).length) appliedDisplay=\(displayRange.location):\(displayRange.length)"
        )
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.updateUIView-after-apply-model",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "incomingModelLen=\((text as NSString).length) appliedDisplay=\(displayRange.location):\(displayRange.length)"
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
            ZoneEditorDebugStore.shared.recordNativeTextEvent(
                "text.sync-focus-schedule-become",
                zoneID: zoneID,
                pathID: pathID,
                textView: textView
            )
            DispatchQueue.main.async {
                let manager = ZoneFocusManager.shared
                defer { context.coordinator.focusSyncState = .idle }
                guard !manager.isSuppressingFocusRequests else {
                    ZoneEditorDebugStore.shared.recordFocusEvent("sync become ignored", zoneID: zoneID)
                    ZoneEditorDebugStore.shared.recordNativeTextEvent(
                        "text.sync-focus-become-ignored",
                        zoneID: zoneID,
                        pathID: pathID,
                        textView: textView,
                        details: "reason=suppressingFocus"
                    )
                    return
                }
                guard manager.focusedZoneID == self.zoneID || manager.pendingFocusZoneID == self.zoneID else {
                    ZoneEditorDebugStore.shared.recordNativeTextEvent(
                        "text.sync-focus-become-ignored",
                        zoneID: zoneID,
                        pathID: pathID,
                        textView: textView,
                        details: "reason=managerTargetMismatch focused=\(manager.focusedZoneID?.uuidString.prefix(6) ?? "nil") pending=\(manager.pendingFocusZoneID?.uuidString.prefix(6) ?? "nil")"
                    )
                    return
                }
                NotificationCenter.default.post(
                    name: .zoneEditorWillFocusTextView,
                    object: self.zoneID
                )
                let result = textView.becomeFirstResponder()
                ZoneEditorDebugStore.shared.recordNativeTextEvent(
                    "text.sync-focus-become",
                    zoneID: zoneID,
                    pathID: pathID,
                    textView: textView,
                    details: "result=\(result ? 1 : 0)"
                )
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
            ZoneEditorDebugStore.shared.recordNativeTextEvent(
                "text.sync-focus-schedule-resign",
                zoneID: zoneID,
                pathID: pathID,
                textView: textView
            )
            DispatchQueue.main.async {
                defer { context.coordinator.focusSyncState = .idle }
                guard ZoneFocusManager.shared.focusedZoneID == nil,
                      ZoneFocusManager.shared.pendingFocusZoneID == nil,
                      !ZoneFocusManager.shared.shouldRetainKeyboard,
                      textView.isFirstResponder else {
                    ZoneEditorDebugStore.shared.recordNativeTextEvent(
                        "text.sync-focus-resign-ignored",
                        zoneID: zoneID,
                        pathID: pathID,
                        textView: textView
                    )
                    return
                }
                ZoneEditorDebugStore.shared.recordFocusEvent("sync resign explicit", zoneID: zoneID)
                let result = textView.resignFirstResponder()
                ZoneEditorDebugStore.shared.recordNativeTextEvent(
                    "text.sync-focus-resign",
                    zoneID: zoneID,
                    pathID: pathID,
                    textView: textView,
                    details: "result=\(result ? 1 : 0)"
                )
            }
        }
    }

    func makeCoordinator() -> ZoneTextViewCoordinator {
        let coordinator = ZoneTextViewCoordinator()
        coordinator.zoneID = zoneID
        coordinator.pathID = pathID
        return coordinator
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let result: CGSize
        if let proposedHeight = proposal.height, proposedHeight > 0 {
            result = CGSize(width: width, height: proposedHeight)
        } else {
            result = context.coordinator.measuredSize(width: width) {
                let targetSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
                let calculatedSize = uiView.sizeThatFits(targetSize)
                let measuredHeight = max(ceil(calculatedSize.height), ceil(font.lineHeight))
                return CGSize(
                    width: width,
                    height: measuredHeight
                )
            }
        }

        if AppFeatures.current.showsVisualDebugOverlays {
            ZoneEditorDebugStore.shared.recordLayoutEvent(
                "ui-sizeThatFits",
                zoneID: zoneID,
                details: "proposal=\(debugOptionalValue(proposal.width))x\(debugOptionalValue(proposal.height)) result=\(debugSize(result)) frame=\(debugRect(uiView.frame))"
            )
        }

        return result
    }

    private func updateScrollBehavior(of textView: UITextView) {
        if textView.isScrollEnabled {
            textView.isScrollEnabled = false
        }
    }

    private func updateLayoutPolicy(of textView: UITextView, modelText: String) {
        let usesNonContiguousLayout = ZoneTextPerformancePolicy.isOversized(modelText)
        guard textView.layoutManager.allowsNonContiguousLayout != usesNonContiguousLayout else {
            return
        }

        textView.layoutManager.allowsNonContiguousLayout = usesNonContiguousLayout
        ZoneEditorDebugStore.shared.recordNativeTextEvent(
            "text.layout-policy-update",
            zoneID: zoneID,
            pathID: pathID,
            textView: textView,
            details: "modelLen=\((modelText as NSString).length) nonContiguous=\(usesNonContiguousLayout ? 1 : 0)"
        )
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
        if let textView = textView as? FullHitTextView {
            textView.estimatedLineAdvanceY = font.lineHeight + max(lineSpacing, 0)
        }
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
            .paragraphStyle: paragraphStyle,
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
            .paragraphStyle: paragraphStyle,
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

        let before = linesArray[0 ... lineIndex].joined(separator: "\n")
        let after = lineIndex < linesArray.count - 1
            ? linesArray[(lineIndex + 1)...].joined(separator: "\n")
            : ""

        return (before, after)
    }
}
