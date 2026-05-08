//
//  ZoneTextView.swift
//  QuizFlash
//

import SwiftUI
import UIKit
import Observation
import Foundation

// MARK: - Full Hit Text View
/// Custom UITextView that keeps selection stable inside the editor surface.
final class FullHitTextView: UITextView {
    var usesCompactCaret: Bool = true

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        guard usesCompactCaret else { return rect }

        let targetHeight = min(max((font?.lineHeight ?? rect.height) * 0.48, 14), 26)
        rect.origin.y += max((rect.height - targetHeight) / 2, 0)
        rect.size.height = targetHeight
        rect.size.width = 1.8
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

@Observable
@MainActor
final class ZoneEditorDebugStore {
    static let shared = ZoneEditorDebugStore()

    private(set) var eventIndex: Int = 0
    private(set) var lastEvent: String = "idle"
    private(set) var focusLine: String = "focus idle"
    private(set) var textViewLine: String = "textview idle"
    private(set) var selectedZoneLine: String = "zone idle"
    private(set) var selectedLayoutLine: String = "layout idle"
    private(set) var resizeHandleLine: String = "handle idle"
    private(set) var resizeTouchLine: String = "touch idle"
    private(set) var resizeCalcLine: String = "resize idle"
    private(set) var canvasLine: String = "canvas idle"
    private(set) var tapLine: String = "tap idle"
    private(set) var caretLine: String = "caret idle"

    private var resizeBeginCount = 0
    private var resizeMoveCount = 0
    private var resizeEndCount = 0
    private var lastResizeMovePublishTime: TimeInterval = 0

    private init() { }

    var hudLines: [String] {
        [
            "#\(eventIndex) \(lastEvent)",
            focusLine,
            textViewLine,
            selectedZoneLine,
            selectedLayoutLine,
            resizeHandleLine,
            resizeTouchLine,
            resizeCalcLine,
            canvasLine,
            tapLine,
            caretLine
        ]
    }

    func recordEvent(_ value: String) {
        eventIndex += 1
        lastEvent = value
    }

    func updateFocusManager(focusedZoneID: UUID?, pendingZoneID: UUID?, retainKeyboard: Bool) {
        focusLine = "focus manager focused=\(shortID(focusedZoneID)) pending=\(shortID(pendingZoneID)) retain=\(retainKeyboard ? "1" : "0")"
    }

    func updateTextView(
        zoneID: UUID?,
        mountedFocused: Bool,
        textViewFirstResponder: Bool,
        uiViewFirstResponder: Bool,
        requestedFirstResponder: Bool,
        textLength: Int
    ) {
        textViewLine = "text mounted=\(flag(mountedFocused)) swiftFR=\(flag(textViewFirstResponder)) uiFR=\(flag(uiViewFirstResponder)) request=\(flag(requestedFirstResponder)) len=\(textLength) zone=\(shortID(zoneID))"
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
        selectedZoneLine = "zone path=\(pathID) id=\(shortID(zoneID)) type=\(contentType) size=\(sizeMode) block=\(blockAlignment) text=\(textAlignment) y=\(verticalAlignment) fixed=\(format(fixedWidth))x\(format(fixedHeight))"
    }

    func updateSelectedLayout(
        blockSize: CGSize,
        contentWidth: CGFloat,
        leadingInset: CGFloat,
        renderedSize: CGSize,
        isSelected: Bool,
        isResizing: Bool
    ) {
        selectedLayoutLine = "layout block=\(format(blockSize.width))x\(format(blockSize.height)) contentW=\(format(contentWidth)) lead=\(format(leadingInset)) measured=\(format(renderedSize.width))x\(format(renderedSize.height)) selected=\(flag(isSelected)) resizing=\(flag(isResizing))"
    }

    func updateResizeHandle(blockSize: CGSize, hitSize: CGSize, glyphSize: CGFloat, selected: Bool) {
        resizeHandleLine = "handle selected=\(flag(selected)) block=\(format(blockSize.width))x\(format(blockSize.height)) hit=\(format(hitSize.width))x\(format(hitSize.height)) glyph=\(format(glyphSize))"
    }

    func recordResizeTouch(phase: String, x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat) {
        let shouldPublish: Bool
        switch phase {
        case "began":
            resizeBeginCount += 1
            shouldPublish = true
        case "moved":
            resizeMoveCount += 1
            let now = Date.timeIntervalSinceReferenceDate
            shouldPublish = now - lastResizeMovePublishTime >= 0.05 || resizeMoveCount % 10 == 0
            if shouldPublish {
                lastResizeMovePublishTime = now
            }
        case "ended", "cancelled":
            resizeEndCount += 1
            shouldPublish = true
        default:
            shouldPublish = true
            break
        }

        guard shouldPublish else { return }

        resizeTouchLine = "touch \(phase) begin=\(resizeBeginCount) move=\(resizeMoveCount) end=\(resizeEndCount) local=\(format(x)),\(format(y)) delta=\(format(dx)),\(format(dy))"
        recordEvent("corner touch \(phase)")
    }

    func updateResizeCalculation(axis: String, startSize: CGSize, nextSize: CGSize, translation: CGSize) {
        resizeCalcLine = "resize axis=\(axis) start=\(format(startSize.width))x\(format(startSize.height)) next=\(format(nextSize.width))x\(format(nextSize.height)) delta=\(format(translation.width)),\(format(translation.height))"
    }

    func updateCanvas(
        cardSize: CGSize,
        contentSize: CGSize,
        selectedFrame: CGRect?,
        keyboardVisible: Bool,
        keyboardHeight: CGFloat
    ) {
        let frameText: String
        if let selectedFrame {
            frameText = "\(format(selectedFrame.width))x\(format(selectedFrame.height)) @\(format(selectedFrame.minX)),\(format(selectedFrame.minY))"
        } else {
            frameText = "nil"
        }
        canvasLine = "canvas card=\(format(cardSize.width))x\(format(cardSize.height)) content=\(format(contentSize.width))x\(format(contentSize.height)) selectedFrame=\(frameText) keyboard=\(flag(keyboardVisible)):\(format(keyboardHeight))"
    }

    func recordTap(_ value: String) {
        tapLine = value
        recordEvent(value)
    }

    func recordFocusEvent(_ value: String, zoneID: UUID?) {
        focusLine = "\(value) zone=\(shortID(zoneID))"
        recordEvent(value)
    }

    func recordCaret(zoneID: UUID?, selectedRange: NSRange, anchorY: CGFloat) {
        caretLine = "caret zone=\(shortID(zoneID)) loc=\(selectedRange.location) len=\(selectedRange.length) anchorY=\(format(anchorY))"
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
    var onCaretAnchorChange: ((CGFloat) -> Void)?
    var onCommit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var lineSpacing: CGFloat = 0
    var contentInset: UIEdgeInsets = .zero
    var extendsTextOnBlankTap: Bool = false
    
    private var lastText: String = ""
    var isUpdating: Bool = false
    weak var textView: UITextView?
    private var focusObserver: NSObjectProtocol?
    
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
                // Prevent glitch: only bring focus if not already here
                if !(self.textView?.isFirstResponder ?? false) {
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
                    }
                } else {
                    Task { @MainActor in
                        ZoneEditorDebugStore.shared.recordFocusEvent("focus notification alreadyFR", zoneID: zoneID)
                    }
                }
                self.applyPendingCursorLocation(for: zoneID)
            }
        }
    }
    
    deinit {
        if let observer = focusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer.name == Self.surfaceTapRecognizerName else {
            return true
        }

        guard extendsTextOnBlankTap,
              let textView,
              !textView.isFirstResponder else {
            return false
        }

        let point = touch.location(in: textView)
        return textView.bounds.contains(point) && isBlankSurfaceTap(at: point, in: textView)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc func handleSurfaceTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              extendsTextOnBlankTap,
              let textView,
              textView.bounds.contains(recognizer.location(in: textView)),
              isBlankSurfaceTap(at: recognizer.location(in: textView), in: textView) else {
            return
        }

        applySurfaceTap(at: recognizer.location(in: textView))
    }

    func applySurfaceTap(at tapPoint: CGPoint) {
        guard extendsTextOnBlankTap,
              let textView,
              textView.bounds.contains(tapPoint) else {
            return
        }

        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }

        setCursor(at: tapPoint, in: textView)
        reportCursorPosition(from: textView)
    }

    private func setCursor(at point: CGPoint, in textView: UITextView) {
        textView.layoutIfNeeded()

        let boundedPoint = CGPoint(
            x: min(max(point.x, 0), max(textView.bounds.width, 0)),
            y: min(max(point.y, 0), max(textView.bounds.height, 0))
        )

        if let position = textView.closestPosition(to: boundedPoint) {
            let location = textView.offset(from: textView.beginningOfDocument, to: position)
            let clampedLocation = min(max(location, 0), (textView.text as NSString).length)
            textView.selectedRange = NSRange(location: clampedLocation, length: 0)
        } else {
            let location = insertionLocation(for: boundedPoint, in: textView)
            textView.selectedRange = NSRange(location: location, length: 0)
        }
    }

    private func insertionLocation(for point: CGPoint, in textView: UITextView) -> Int {
        let nsText = (textView.text ?? "") as NSString
        guard nsText.length > 0 else { return 0 }

        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        layoutManager.ensureLayout(for: textContainer)

        var containerPoint = point
        containerPoint.x -= textView.textContainerInset.left
        containerPoint.y -= textView.textContainerInset.top
        containerPoint.x += textView.contentOffset.x
        containerPoint.y += textView.contentOffset.y

        let usedRect = layoutManager.usedRect(for: textContainer)
        if containerPoint.y >= usedRect.maxY {
            return nsText.length
        }

        var insertionFraction: CGFloat = 0
        let characterIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &insertionFraction
        )
        let insertionIndex = characterIndex + (insertionFraction > 0.5 ? 1 : 0)
        return min(max(insertionIndex, 0), nsText.length)
    }

    private func isBlankSurfaceTap(at point: CGPoint, in textView: UITextView) -> Bool {
        let nsText = (textView.text ?? "") as NSString
        guard nsText.length > 0 else { return true }

        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        layoutManager.ensureLayout(for: textContainer)

        var containerPoint = point
        containerPoint.x -= textView.textContainerInset.left
        containerPoint.y -= textView.textContainerInset.top
        containerPoint.x += textView.contentOffset.x
        containerPoint.y += textView.contentOffset.y

        let usedRect = layoutManager.usedRect(for: textContainer).insetBy(dx: -4, dy: -4)
        guard usedRect.contains(containerPoint) else { return true }

        var fraction: CGFloat = 0
        let characterIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(characterIndex, max(nsText.length - 1, 0)))
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        ).insetBy(dx: -8, dy: -6)

        return !glyphRect.contains(containerPoint)
    }

    static let surfaceTapRecognizerName = "ZoneTextViewSurfaceTapRecognizer"

    private func applyPendingCursorLocation(for zoneID: UUID) {
        guard let textView else {
            return
        }

        if let requestedPoint = ZoneFocusManager.shared.takePendingCursorPoint(for: zoneID) {
            setCursor(at: requestedPoint, in: textView)
            reportCursorPosition(from: textView)
            return
        }

        guard let requestedLocation = ZoneFocusManager.shared.takePendingCursorLocation(for: zoneID) else {
            return
        }

        let clampedLocation = min(max(requestedLocation, 0), (textView.text as NSString).length)
        textView.selectedRange = NSRange(location: clampedLocation, length: 0)
        reportCursorPosition(from: textView)
    }
    
    func textViewDidChange(_ textView: UITextView) {
        guard let text = textView.text else { return }
        guard !isUpdating else { return }
        
        lastText = text
        onTextChange?(text)
        reportCursorPosition(from: textView)
    }
    
    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isUpdating else { return }
        reportCursorPosition(from: textView)
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        ZoneEditorDebugStore.shared.recordFocusEvent("textView didBegin", zoneID: zoneID)
        updateSurfaceTapRecognizer(in: textView, enabled: false)
        onFocusChange?(true)
        reportCursorPosition(from: textView)
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        ZoneEditorDebugStore.shared.recordFocusEvent("textView didEnd", zoneID: zoneID)
        updateSurfaceTapRecognizer(in: textView, enabled: extendsTextOnBlankTap)
        onFocusChange?(false)
    }

    func updateSurfaceTapRecognizer(in textView: UITextView, enabled: Bool) {
        textView.gestureRecognizers?
            .filter { $0.name == Self.surfaceTapRecognizerName }
            .forEach { $0.isEnabled = enabled }
    }
    
    private func reportCursorPosition(from textView: UITextView) {
        guard let text = textView.text else { return }
        let nsRange = textView.selectedRange
        onCursorChange?(nsRange, text)
        let (focusedLineIndex, totalLines) = calculateLineInfo(from: text, location: nsRange.location)
        onFocusLineChange?(focusedLineIndex, totalLines)

        if let selectedTextRange = textView.selectedTextRange {
            let caretRect = textView.caretRect(for: selectedTextRange.start)
            let anchorY = min(
                max(caretRect.midY / max(textView.bounds.height, 1), 0.08),
                0.92
            )
            ZoneEditorDebugStore.shared.recordCaret(
                zoneID: zoneID,
                selectedRange: nsRange,
                anchorY: anchorY
            )
            onCaretAnchorChange?(anchorY)
        }
    }
    
    private func calculateLineInfo(from text: String, location: Int) -> (lineIndex: Int, totalLines: Int) {
        let lines = text.components(separatedBy: "\n")
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
    var cursorTintColor: UIColor = .systemPurple
    var extendsTextOnBlankTap: Bool = false
    let zoneID: UUID
    let isFirstResponder: Bool
    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((NSRange, String) -> Void)?
    var onFocusLineChange: ((Int, Int) -> Void)?
    var onCaretAnchorChange: ((CGFloat) -> Void)?
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
        context.coordinator.extendsTextOnBlankTap = extendsTextOnBlankTap
        
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

        let surfaceTapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(ZoneTextViewCoordinator.handleSurfaceTap(_:))
        )
        surfaceTapRecognizer.name = ZoneTextViewCoordinator.surfaceTapRecognizerName
        surfaceTapRecognizer.cancelsTouchesInView = false
        surfaceTapRecognizer.delegate = context.coordinator
        textView.addGestureRecognizer(surfaceTapRecognizer)
        
        textView.text = text
        updateStyling(of: textView)
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.zoneID = zoneID
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onFocusLineChange = onFocusLineChange
        context.coordinator.onCaretAnchorChange = onCaretAnchorChange
        context.coordinator.onCommit = onCommit
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.font = font
        context.coordinator.lineSpacing = lineSpacing
        context.coordinator.contentInset = contentInset
        context.coordinator.extendsTextOnBlankTap = extendsTextOnBlankTap
        (textView as? FullHitTextView)?.usesCompactCaret = true
        context.coordinator.updateSurfaceTapRecognizer(
            in: textView,
            enabled: extendsTextOnBlankTap && !textView.isFirstResponder
        )
        ZoneEditorDebugStore.shared.updateTextView(
            zoneID: zoneID,
            mountedFocused: isFirstResponder,
            textViewFirstResponder: textView.isFirstResponder,
            uiViewFirstResponder: textView.isFirstResponder,
            requestedFirstResponder: isFirstResponder,
            textLength: ((textView.text ?? "") as NSString).length
        )
        
        guard textView.text != text else {
            updateStyling(of: textView)
            syncFocus(textView: textView, isFirstResponder: isFirstResponder, context: context)
            return
        }
        
        let oldText = textView.text ?? ""
        let selectedRange = textView.selectedRange
        let shouldMoveCursorToEnd = extendsTextOnBlankTap
            && text.hasPrefix(oldText)
            && text.count > oldText.count
            && text.dropFirst(oldText.count).allSatisfy { $0 == "\n" }
        
        context.coordinator.isUpdating = true
        textView.text = text
        context.coordinator.isUpdating = false
        
        if shouldMoveCursorToEnd {
            textView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        } else if selectedRange.location != NSNotFound &&
           selectedRange.location <= (text as NSString).length {
            textView.selectedRange = selectedRange
        }
        
        updateStyling(of: textView)
        syncFocus(textView: textView, isFirstResponder: isFirstResponder, context: context)
    }
    
    private func syncFocus(textView: UITextView, isFirstResponder: Bool, context: Context) {
        // Removed glitch: Don't force "becomeFirstResponder" from SwiftUI to UIKit here.
        // This is done asynchronously via Notification (see Coordinator init).
        // We ONLY execute resignFirstResponder if no other zone intentionally took focus.
        if !isFirstResponder && textView.isFirstResponder {
            DispatchQueue.main.async {
                if ZoneFocusManager.shared.focusedZoneID != self.zoneID {
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
        textView.font = font
        textView.textColor = textColor
        textView.tintColor = cursorTintColor
        textView.typingAttributes = textAttributes
        textView.textContainerInset = contentInset

        if textView.text.isEmpty && textView.textAlignment != textAlignment {
            textView.text = " "
            textView.textAlignment = textAlignment
            textView.text = ""
        } else {
            textView.textAlignment = textAlignment
        }

        let fullRange = NSRange(location: 0, length: textView.textStorage.length)
        if fullRange.length > 0 {
            textView.textStorage.setAttributes(textAttributes, range: fullRange)
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
