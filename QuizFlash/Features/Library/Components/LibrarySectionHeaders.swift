//
//  LibrarySectionHeaders.swift
//  QuizFlash
//
//  Section header views and metrics for grouped Library timelines.
//

import SwiftUI

// MARK: - Section Header

struct LibrarySectionHeaderFrame: Equatable {
    let id: String
    let title: String
    let minY: CGFloat
    let maxY: CGFloat
}

struct LibrarySectionHeaderFramePreferenceKey: PreferenceKey {
    static var defaultValue: [LibrarySectionHeaderFrame] = []

    static func reduce(value: inout [LibrarySectionHeaderFrame], nextValue: () -> [LibrarySectionHeaderFrame]) {
        value.append(contentsOf: nextValue())
    }
}

/// Header for grouped library sections.
struct LibrarySectionHeader: View {
    let id: String
    let title: String
    var isHidden: Bool = false
    var isRecoveryVisible = true
    var animateVisibility = true
    var visibilityAnimation: Animation? = nil

    var body: some View {
        let containerOpacity = isRecoveryVisible ? 1.0 : 0.0

        LibrarySectionHeaderLabel(
            title: title,
            isHidden: isHidden,
            isRecoveryVisible: isRecoveryVisible,
            animateVisibility: animateVisibility,
            visibilityAnimation: visibilityAnimation
        )
            .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LibrarySectionHeaderFramePreferenceKey.self,
                    value: [
                        LibrarySectionHeaderFrame(
                            id: id,
                            title: title,
                            minY: proxy.frame(in: .named(kLibraryChromeSpace)).minY,
                            maxY: proxy.frame(in: .named(kLibraryChromeSpace)).maxY
                        )
                    ]
                )
            }
        }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, LibrarySectionHeaderMetrics.inlineOuterVerticalPadding)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .opacity(containerOpacity)
            .animation(animateVisibility ? visibilityAnimation : nil, value: isRecoveryVisible)
            .textCase(nil)
    }
}

struct LibrarySectionHeaderLabel: View {
    let title: String
    var isHidden = false
    var isRecoveryVisible = true
    var animateVisibility = true
    var visibilityAnimation: Animation? = nil

    var body: some View {
        let labelScale =
            if !isRecoveryVisible {
            CollapsibleTitleChromeMetrics.hiddenScale
        } else {
            isHidden ? LibraryStickyBehavior.Handoff.compactDateCapsuleHiddenScale : 1
        }
        let labelOpacity =
            if !isRecoveryVisible {
            1.0
        } else {
            isHidden ? 0.0 : 1.0
        }

        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.76))
            .lineLimit(1)
            .minimumScaleFactor(0.88)
            .padding(.vertical, LibrarySectionHeaderMetrics.labelVerticalPadding + 1)
            .opacity(labelOpacity)
            .scaleEffect(labelScale, anchor: .top)
            .animation(animateVisibility ? visibilityAnimation : nil, value: isRecoveryVisible)
            .animation(
            animateVisibility
                ? .easeInOut(
                duration: LibraryStickyBehavior.Handoff.compactDateCapsuleScrollAnimationDuration
            )
            : nil,
            value: isHidden
        )
            .shadow(color: .black.opacity(0.98), radius: 24, x: 0, y: 0)
            .shadow(color: .black.opacity(0.94), radius: 11, x: 0, y: 1)
            .shadow(color: .black.opacity(0.86), radius: 4, x: 0, y: 0)
            .shadow(color: .black.opacity(0.64), radius: 1.2, x: 0, y: 0)
    }
}

enum LibrarySectionHeaderMetrics {
    static let defaultHeight = LibraryStickyBehavior.SectionHeader.defaultHeight
    static let inlineOuterVerticalPadding = LibraryStickyBehavior.SectionHeader.inlineOuterVerticalPadding
    static let labelVerticalPadding = LibraryStickyBehavior.SectionHeader.labelVerticalPadding
    static let firstDeckTopPadding = LibraryStickyBehavior.SectionHeader.firstDeckTopPadding
    static let regularDeckTopPadding = LibraryStickyBehavior.SectionHeader.regularDeckTopPadding
}
