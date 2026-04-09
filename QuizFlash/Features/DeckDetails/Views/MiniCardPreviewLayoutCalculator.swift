//
//  MiniCardPreviewLayoutCalculator.swift
//  QuizFlash
//
//  Pure layout helpers for centering text inside deck-grid mini previews.
//

import CoreGraphics

// MARK: - Mini Card Preview Layout Calculator

struct MiniCardPreviewLayoutCalculator {
    let containerSize: CGSize
    let contentPadding: CGFloat

    var availableTextWidth: CGFloat {
        max(containerSize.width - (contentPadding * 2), 1)
    }

    func resolvedTextBlockSize(
        renderedTextSize: CGSize,
        estimatedTextSize: CGSize
    ) -> CGSize {
        if renderedTextSize.width > 0, renderedTextSize.height > 0 {
            return CGSize(
                width: min(renderedTextSize.width, availableTextWidth),
                height: renderedTextSize.height
            )
        }

        return CGSize(
            width: min(estimatedTextSize.width, availableTextWidth),
            height: estimatedTextSize.height
        )
    }

    func centeredTextTopInset(textHeight: CGFloat) -> CGFloat {
        let availableHeight = max(containerSize.height - (contentPadding * 2), 1)
        let remainingHeight = availableHeight - textHeight
        let centeredInset = remainingHeight / 2

        return centeredInset >= 6 ? centeredInset : 0
    }

    func centeredTextLeadingInset(textWidth: CGFloat) -> CGFloat {
        max((availableTextWidth - textWidth) / 2, 0)
    }
}
