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
        let capsuleScale =
            if !isRecoveryVisible {
            CollapsibleTitleChromeMetrics.hiddenScale
        } else {
            isHidden ? LibraryStickyBehavior.Handoff.compactDateCapsuleHiddenScale : 1
        }
        let capsuleOpacity =
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
            .padding(.horizontal, 12)
            .padding(.vertical, LibrarySectionHeaderMetrics.labelVerticalPadding + 1)
            .background {
            Capsule(style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.13).opacity(0.9))
        }
            .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.7)
        }
            .opacity(capsuleOpacity)
            .scaleEffect(capsuleScale, anchor: .top)
            .animation(animateVisibility ? visibilityAnimation : nil, value: isRecoveryVisible)
            .animation(
            animateVisibility
                ? .easeInOut(
                duration: LibraryStickyBehavior.Handoff.compactDateCapsuleScrollAnimationDuration
            )
            : nil,
            value: isHidden
        )
            .shadow(color: .black.opacity(0.92), radius: 18, x: 0, y: 0)
            .shadow(color: .black.opacity(0.85), radius: 7, x: 0, y: 1)
            .shadow(color: .black.opacity(0.7), radius: 1.5, x: 0, y: 0)
    }
}

enum LibrarySectionHeaderMetrics {
    static let defaultHeight = LibraryStickyBehavior.SectionHeader.defaultHeight
    static let inlineOuterVerticalPadding = LibraryStickyBehavior.SectionHeader.inlineOuterVerticalPadding
    static let labelVerticalPadding = LibraryStickyBehavior.SectionHeader.labelVerticalPadding
    static let firstDeckTopPadding = LibraryStickyBehavior.SectionHeader.firstDeckTopPadding
    static let regularDeckTopPadding = LibraryStickyBehavior.SectionHeader.regularDeckTopPadding
}
