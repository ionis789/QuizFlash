//
//  ZoneTextView.swift
//  QuizFlash
//

import SwiftUI
import UIKit

// MARK: - Full Hit Text View
/// Custom UITextView that keeps selection stable inside the editor surface.
final class FullHitTextView: UITextView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.bounds.contains(point) {
            return self
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Zone Text View Coordinator

final class ZoneTextViewCoordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    var zoneID: UUID?
    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((NSRange, String) -> Void)?
    var onFocusLineChange: ((Int, Int) -> Void)?
    var onCommit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    
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
                    self.textView?.becomeFirstResponder()
                }
            }
        }
    }
    
    deinit {
        if let observer = focusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
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
        onFocusChange?(true)
        reportCursorPosition(from: textView)
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        onFocusChange?(false)
    }
    
    private func reportCursorPosition(from textView: UITextView) {
        guard let text = textView.text else { return }
        let nsRange = textView.selectedRange
        onCursorChange?(nsRange, text)
        let (focusedLineIndex, totalLines) = calculateLineInfo(from: text, location: nsRange.location)
        onFocusLineChange?(focusedLineIndex, totalLines)
    }
    
    private func calculateLineInfo(from text: String, location: Int) -> (lineIndex: Int, totalLines: Int) {
        let lines = text.components(separatedBy: "\n")
        let totalLines = lines.count
        guard location >= 0 else { return (0, totalLines) }
        
        var currentIndex = 0
        for (index, line) in lines.enumerated() {
            let lineLength = line.count + 1
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
    let zoneID: UUID
    let isFirstResponder: Bool
    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((NSRange, String) -> Void)?
    var onFocusLineChange: ((Int, Int) -> Void)?
    var onCommit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    
    func makeUIView(context: Context) -> UITextView {
        // Use custom class that detects tap everywhere
        let textView = FullHitTextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.zoneID = zoneID
        
        textView.font = font
        textView.textColor = textColor
        textView.textAlignment = textAlignment
        textView.backgroundColor = .clear
        textView.adjustsFontForContentSizeCategory = true
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.keyboardType = .default
        textView.returnKeyType = .default
        textView.isScrollEnabled = false
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.allowsEditingTextAttributes = false
        
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        textView.text = text
        updateStyling(of: textView)
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.zoneID = zoneID
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onFocusLineChange = onFocusLineChange
        context.coordinator.onCommit = onCommit
        context.coordinator.onFocusChange = onFocusChange
        
        guard textView.text != text else {
            updateStyling(of: textView)
            syncFocus(textView: textView, isFirstResponder: isFirstResponder, context: context)
            return
        }
        
        let selectedRange = textView.selectedRange
        
        context.coordinator.isUpdating = true
        textView.text = text
        context.coordinator.isUpdating = false
        
        if selectedRange.location != NSNotFound && 
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
        textView.typingAttributes = textAttributes

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
