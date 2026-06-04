//
//  CodeSnippetView.swift
//  QuizFlash
//
//  Created by Ion Socol on 21.02.2026.
//

import Foundation
import ObjectiveC.runtime
import SwiftUI
import UIKit

enum CodeSnippetMetrics {
    static let backgroundUIColor = UIColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)
    static let cornerRadius: CGFloat = 26
    static let contentPadding: CGFloat = 14
    static let relativeFontScale: CGFloat = 0.86
}

private var quizFlashCodeScrollCardHandoffAssociationKey: UInt8 = 0

extension UIScrollView {
    var quizflashAllowsCardSwipeEdgeHandoff: Bool {
        get {
            (objc_getAssociatedObject(
                self,
                &quizFlashCodeScrollCardHandoffAssociationKey
            ) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &quizFlashCodeScrollCardHandoffAssociationKey,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    func quizflashCanScrollHorizontally(fingerDirection direction: CGFloat) -> Bool {
        guard direction != 0 else { return false }
        layoutIfNeeded()

        let leadingOffset = -adjustedContentInset.left
        let trailingOffset = max(
            contentSize.width - bounds.width + adjustedContentInset.right,
            leadingOffset
        )
        let tolerance: CGFloat = 0.5

        guard trailingOffset > leadingOffset + tolerance else { return false }
        if direction > 0 {
            return contentOffset.x > leadingOffset + tolerance
        }
        return contentOffset.x < trailingOffset - tolerance
    }
}

// MARK: - Code Snippet View (Block Code)
struct CodeSnippetView: View {
    let rawText: String
    let fontSize: CGFloat
    let cornerRadius: CGFloat
    @State private var overflowState = CodeOverflowState()

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
            cornerRadius: cornerRadius,
            overflowState: $overflowState
        )
        .frame(height: codeBlockHeight(for: code))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            CodeOverflowIndicator(
                canScrollLeft: overflowState.canScrollLeft,
                canScrollRight: overflowState.canScrollRight
            )
            .allowsHitTesting(false)
        }
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

private struct CodeOverflowState: Equatable {
    var canScrollLeft = false
    var canScrollRight = false
}

private struct CodeOverflowIndicator: View {
    let canScrollLeft: Bool
    let canScrollRight: Bool
    private let horizontalOffset: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if canScrollLeft {
                    edgeCue(direction: .leading)
                        .position(x: 0, y: proxy.size.height / 2)
                        .offset(x: -horizontalOffset)
                }
                if canScrollRight {
                    edgeCue(direction: .trailing)
                        .position(x: proxy.size.width, y: proxy.size.height / 2)
                        .offset(x: horizontalOffset)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
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

// MARK: - Edge-Aware Code Scroll View

private struct EdgeAwareCodeScrollView: UIViewRepresentable {
    let code: String
    let fontSize: CGFloat
    let cornerRadius: CGFloat
    @Binding var overflowState: CodeOverflowState

    func makeUIView(context _: Context) -> EdgeAwareCodeUIScrollView {
        let scrollView = EdgeAwareCodeUIScrollView()
        scrollView.onOverflowStateChange = { overflowState = $0 }
        scrollView.configure(code: code, fontSize: fontSize, cornerRadius: cornerRadius)
        return scrollView
    }

    func updateUIView(_ scrollView: EdgeAwareCodeUIScrollView, context _: Context) {
        scrollView.onOverflowStateChange = { overflowState = $0 }
        scrollView.configure(code: code, fontSize: fontSize, cornerRadius: cornerRadius)
    }
}

private final class EdgeAwareCodeUIScrollView: UIScrollView {
    private let codeLabel = UILabel()
    var onOverflowStateChange: ((CodeOverflowState) -> Void)?
    private var lastOverflowState = CodeOverflowState()

    override var contentOffset: CGPoint {
        didSet {
            reportOverflowStateIfNeeded()
        }
    }

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
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportOverflowStateIfNeeded()
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
        quizflashAllowsCardSwipeEdgeHandoff = true
        backgroundColor = CodeSnippetMetrics.backgroundUIColor
        clipsToBounds = true
        bounces = true
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

    private func reportOverflowStateIfNeeded() {
        let leadingOffset = -adjustedContentInset.left
        let trailingOffset = max(
            contentSize.width - bounds.width + adjustedContentInset.right,
            leadingOffset
        )
        let tolerance: CGFloat = 0.5
        let hasOverflow = trailingOffset > leadingOffset + tolerance
        let state = CodeOverflowState(
            canScrollLeft: hasOverflow && contentOffset.x > leadingOffset + tolerance,
            canScrollRight: hasOverflow && contentOffset.x < trailingOffset - tolerance
        )

        guard state != lastOverflowState else { return }
        lastOverflowState = state
        onOverflowStateChange?(state)
    }
}
