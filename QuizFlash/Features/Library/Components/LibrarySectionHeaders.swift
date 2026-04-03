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

    var body: some View {
        LibrarySectionHeaderLabel(title: title)
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
            .opacity(isHidden ? 0 : 1)
            .animation(.circularProgressSpring, value: isHidden)
            .textCase(nil)
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
    static let defaultHeight = LibraryStickyBehavior.SectionHeader.defaultHeight
    static let inlineOuterVerticalPadding = LibraryStickyBehavior.SectionHeader.inlineOuterVerticalPadding
    static let labelVerticalPadding = LibraryStickyBehavior.SectionHeader.labelVerticalPadding
    static let firstDeckTopPadding = LibraryStickyBehavior.SectionHeader.firstDeckTopPadding
    static let regularDeckTopPadding = LibraryStickyBehavior.SectionHeader.regularDeckTopPadding
}
