//
//  ZoneTextView.swift
//  QuizFlash
//
//  UITextView wrapper with line-based focus tracking for split operations.
//

import SwiftUI
import UIKit

// MARK: - Zone Text View Coordinator

/// Coordinator for UITextView that tracks line-based focus
final class ZoneTextViewCoordinator: NSObject, UITextViewDelegate {
    var zoneID: UUID?
    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((NSRange, String) -> Void)?
    var onFocusLineChange: ((Int, Int) -> Void)?  // Reports (focusedLineIndex, totalLines)
    var onCommit: (() -> Void)?
    
    private var lastText: String = ""
    var isUpdating: Bool = false
    
    // MARK: - UITextViewDelegate
    
    func textViewDidChange(_ textView: UITextView) {
        guard let text = textView.text else { return }
        
        // Prevent infinite loop
        guard !isUpdating else { return }
        
        lastText = text
        onTextChange?(text)
        
        // Report cursor position and focused line
        reportCursorPosition(from: textView)
    }
    
    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isUpdating else { return }
        reportCursorPosition(from: textView)
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        reportCursorPosition(from: textView)
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        // Clear focus state
    }
    
    // MARK: - Helper Methods
    
    private func reportCursorPosition(from textView: UITextView) {
        guard let text = textView.text else { return }
        
        let nsRange = textView.selectedRange
        onCursorChange?(nsRange, text)
        
        // Calculate focused line index and total lines
        let (focusedLineIndex, totalLines) = calculateLineInfo(from: text, location: nsRange.location)
        onFocusLineChange?(focusedLineIndex, totalLines)
    }
    
    /// Calculates which line the cursor is on and total line count
    private func calculateLineInfo(from text: String, location: Int) -> (lineIndex: Int, totalLines: Int) {
        let lines = text.components(separatedBy: "\n")
        let totalLines = lines.count
        
        guard location >= 0 else {
            return (0, totalLines)
        }
        
        var currentIndex = 0
        
        for (index, line) in lines.enumerated() {
            let lineLength = line.count + 1  // +1 for newline
            if location < currentIndex + lineLength {
                return (index, totalLines)
            }
            currentIndex += lineLength
        }
        
        // Cursor is at the end, return last line index
        return (max(0, totalLines - 1), totalLines)
    }
}

// MARK: - Zone Text View Representable

/// UITextView wrapper with line-based focus tracking
struct ZoneTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    let font: UIFont
    let textColor: UIColor
    let textAlignment: NSTextAlignment
    let isBold: Bool
    let isItalic: Bool
    let zoneID: UUID
    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((NSRange, String) -> Void)?
    var onFocusLineChange: ((Int, Int) -> Void)?
    var onCommit: (() -> Void)?
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
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
        
        // Set initial text
        textView.text = text
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        // Only update if text actually changed
        guard textView.text != text else {
            updateStyling(of: textView)
            return
        }
        
        // Save cursor position
        let selectedRange = textView.selectedRange
        let hasSelection = selectedRange.length > 0
        
        // Update text with flag to prevent infinite loop
        context.coordinator.isUpdating = true
        textView.text = text
        context.coordinator.isUpdating = false
        
        // Restore cursor position
        if selectedRange.location != NSNotFound && 
           selectedRange.location <= (text as NSString).length {
            textView.selectedRange = selectedRange
        }
        
        // Update styling
        updateStyling(of: textView)
    }
    
    func makeCoordinator() -> ZoneTextViewCoordinator {
        let coordinator = ZoneTextViewCoordinator()
        coordinator.zoneID = zoneID
        coordinator.onTextChange = onTextChange
        coordinator.onCursorChange = onCursorChange
        coordinator.onFocusLineChange = onFocusLineChange
        coordinator.onCommit = onCommit
        return coordinator
    }
    
    private func updateStyling(of textView: UITextView) {
        textView.font = font
        textView.textColor = textColor
        textView.textAlignment = textAlignment
    }
}

// MARK: - String Line Extensions

extension String {
    /// Returns the line at the given index
    func line(at index: Int) -> String? {
        let lines = components(separatedBy: "\n")
        guard index >= 0 && index < lines.count else { return nil }
        return lines[index]
    }
    
    /// Returns all lines as array
    var lines: [String] {
        components(separatedBy: "\n")
    }
    
    /// Returns the line index containing the character at offset
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
    
    /// Splits text at the given line index
    /// - Returns: (linesBeforeAndIncluding, linesAfter) tuple
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
