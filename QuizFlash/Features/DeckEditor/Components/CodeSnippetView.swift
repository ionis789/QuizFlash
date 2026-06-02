//
//  CodeSnippetView.swift
//  QuizFlash
//
//  Created by Ion Socol on 21.02.2026.
//

import Foundation
import SwiftUI
import UIKit

enum CodeSnippetMetrics {
    static let backgroundUIColor = UIColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)
    static let cornerRadius: CGFloat = 26
    static let contentPadding: CGFloat = 14
    static let relativeFontScale: CGFloat = 0.86
}

// MARK: - Code Snippet View (Block Code)
struct CodeSnippetView: View {
    let rawText: String
    let fontSize: CGFloat
    let cornerRadius: CGFloat

    init(
        rawText: String,
        fontSize: CGFloat = 16,
        cornerRadius: CGFloat = CodeSnippetMetrics.cornerRadius
    ) {
        self.rawText = rawText
        self.fontSize = fontSize
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        let code = parseCode(rawText)

        EdgeAwareCodeScrollView(
            code: code,
            fontSize: fontSize,
            cornerRadius: cornerRadius
        )
        .frame(height: codeBlockHeight(for: code))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parseCode(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: .newlines)
            if lines.first != nil {
                text = lines.dropFirst().joined(separator: "\n")
                if text.hasSuffix("```") {
                    text = String(text.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return text
    }

    private func codeBlockHeight(for code: String) -> CGFloat {
        let measuredText = code.isEmpty ? " " : code
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let rect = (measuredText as NSString).boundingRect(
            with: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height + CodeSnippetMetrics.contentPadding * 2)
    }
}

// MARK: - Edge-Aware Code Scroll View

private struct EdgeAwareCodeScrollView: UIViewRepresentable {
    let code: String
    let fontSize: CGFloat
    let cornerRadius: CGFloat

    func makeUIView(context _: Context) -> EdgeAwareCodeUIScrollView {
        let scrollView = EdgeAwareCodeUIScrollView()
        scrollView.configure(code: code, fontSize: fontSize, cornerRadius: cornerRadius)
        return scrollView
    }

    func updateUIView(_ scrollView: EdgeAwareCodeUIScrollView, context _: Context) {
        scrollView.configure(code: code, fontSize: fontSize, cornerRadius: cornerRadius)
    }
}

private final class EdgeAwareCodeUIScrollView: UIScrollView {
    private let codeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func configure(code: String, fontSize: CGFloat, cornerRadius: CGFloat) {
        backgroundColor = CodeSnippetMetrics.backgroundUIColor
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous

        codeLabel.text = code
        codeLabel.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }

        if shouldHandOffHorizontalPanToParent(pan) {
            return false
        }

        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    private func setUp() {
        backgroundColor = CodeSnippetMetrics.backgroundUIColor
        clipsToBounds = true
        bounces = false
        alwaysBounceHorizontal = false
        alwaysBounceVertical = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        delaysContentTouches = false
        canCancelContentTouches = true

        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byClipping
        codeLabel.textColor = .white
        codeLabel.translatesAutoresizingMaskIntoConstraints = false
        codeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        codeLabel.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(codeLabel)

        let padding = CodeSnippetMetrics.contentPadding
        NSLayoutConstraint.activate([
            codeLabel.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: padding),
            codeLabel.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -padding),
            codeLabel.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: padding),
            codeLabel.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -padding),
        ])
    }

    private func shouldHandOffHorizontalPanToParent(_ pan: UIPanGestureRecognizer) -> Bool {
        layoutIfNeeded()

        let translation = pan.translation(in: self)
        let velocity = pan.velocity(in: self)
        let horizontal = max(abs(translation.x), abs(velocity.x))
        let vertical = max(abs(translation.y), abs(velocity.y))

        guard horizontal > vertical * 1.15 else { return false }
        guard contentSize.width > bounds.width + 1 else { return true }

        let direction = abs(translation.x) > 0 ? translation.x : velocity.x
        guard direction != 0 else { return false }

        let leadingOffset = -adjustedContentInset.left
        let trailingOffset = max(
            contentSize.width - bounds.width + adjustedContentInset.right,
            leadingOffset
        )
        let tolerance: CGFloat = 0.5

        if direction > 0, contentOffset.x <= leadingOffset + tolerance {
            return true
        }
        if direction < 0, contentOffset.x >= trailingOffset - tolerance {
            return true
        }

        return false
    }
}
