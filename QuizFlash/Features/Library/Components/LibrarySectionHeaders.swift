//
//  LibrarySectionHeaders.swift
//  QuizFlash
//
//  Section header views and metrics for grouped Library timelines.
//

import SwiftUI

// MARK: - Section Header

/// Header for grouped library sections.
struct LibrarySectionHeader: View {
    let title: String

    var body: some View {
        LibrarySectionHeaderLabel(title: title)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, LibrarySectionHeaderMetrics.inlineOuterVerticalPadding)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .textCase(nil)
            .visualEffect { content, proxy in
                content.opacity(Self.stickyVisibilityOpacity(for: proxy.frame(in: .named("libraryScroll")).minY))
            }
    }

    private nonisolated static func stickyVisibilityOpacity(for minY: CGFloat) -> CGFloat {
        let fadeStart: CGFloat = -2
        let fadeEnd: CGFloat = -18

        guard minY < fadeStart else { return 1 }
        guard minY > fadeEnd else { return 0 }

        let progress = (minY - fadeEnd) / (fadeStart - fadeEnd)
        let eased = progress * progress * (3 - 2 * progress)
        return eased
    }
}

struct LibrarySectionHeaderLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.76))
            .lineLimit(1)
            .minimumScaleFactor(0.88)
            .padding(.horizontal, 8)
            .padding(.vertical, LibrarySectionHeaderMetrics.labelVerticalPadding)
            .shadow(color: .black.opacity(0.92), radius: 18, x: 0, y: 0)
            .shadow(color: .black.opacity(0.85), radius: 7, x: 0, y: 1)
            .shadow(color: .black.opacity(0.7), radius: 1.5, x: 0, y: 0)
    }
}

enum LibrarySectionHeaderMetrics {
    static let defaultHeight: CGFloat = 24
    static let inlineOuterVerticalPadding: CGFloat = 16
    static let labelVerticalPadding: CGFloat = 2
    static let firstDeckTopPadding: CGFloat = 0
    static let regularDeckTopPadding: CGFloat = 14
}
