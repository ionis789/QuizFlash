//
//  BottomChromeContainer.swift
//  QuizFlash
//
//  Shared floating bottom chrome container used by the custom tab bar and
//  contextual selection toolbars.
//

import SwiftUI

private struct BottomChromeHitShape: Shape {
    let horizontalInset: CGFloat
    let bottomInset: CGFloat

    func path(in rect: CGRect) -> Path {
        let hitRect = CGRect(
            x: horizontalInset,
            y: 0,
            width: max(0, rect.width - (horizontalInset * 2)),
            height: max(0, rect.height - bottomInset)
        )
        return Capsule(style: .continuous).path(in: hitRect)
    }
}

// MARK: - BottomChromeKind

/// Semantic modes for the shared floating bottom chrome surface.
enum BottomChromeKind: Equatable {
    case persistent
    case selection
}

// MARK: - BottomChromeInsets

/// Shared bottom-inset helpers for floating chrome.
enum BottomChromeInsets {
    /// Bottom padding used by the persistent custom tab bar in the root chrome layer.
    static var persistent: CGFloat {
        UIConstants.Layout.bottomChromeBottomPadding
    }

    /// Resolves the shared physical-screen anchoring for selection chrome.
    static func selection(physicalSafeBottom: CGFloat) -> CGFloat {
        physicalSafeBottom + UIConstants.Layout.bottomChromeBottomPadding
    }

    /// Resolves the external vertical correction for selection chrome hosted inside a root TabView screen.
    static func rootTabOffset(
        viewSafeBottom: CGFloat,
        physicalSafeBottom: CGFloat
    ) -> CGFloat {
        -max(0, viewSafeBottom - physicalSafeBottom)
    }

    /// Legacy root-tab correction helper kept temporarily while older callers are migrated.
    /// New bottom chrome should prefer `selection(physicalSafeBottom:)`.
    static func selectionInEditor(
        viewSafeBottom: CGFloat,
        physicalSafeBottom: CGFloat,
        isPresentedInFullScreenSheet: Bool
    ) -> CGFloat {
        if isPresentedInFullScreenSheet {
            return selection(physicalSafeBottom: physicalSafeBottom)
        }
        return persistent
    }
}

// MARK: - BottomChromeContainer

/// Shared floating chrome surface that standardizes glass styling, radius,
/// spacing, and safe-area anchoring for both the custom tab bar and selection bars.
struct BottomChromeContainer<Content: View>: View {
    let kind: BottomChromeKind
    var bottomPadding: CGFloat = BottomChromeInsets.persistent
    var horizontalInset: CGFloat = UIConstants.Layout.bottomChromeSideInset
    var isVisible: Bool = true
    var hiddenOffset: CGFloat = 80
    var ignoresBottomSafeArea: Bool = false
    @ViewBuilder let content: () -> Content

    private var shape: AnyShape {
        AnyShape(Capsule(style: .continuous))
    }

    private var minimumHeight: CGFloat {
        switch kind {
        case .persistent:
            return UIConstants.Size.bottomChromeBarHeight
        case .selection:
            return UIConstants.Size.selectionToolbarBarHeight
        }
    }

    private var innerHorizontalPadding: CGFloat {
        switch kind {
        case .persistent:
            return UIConstants.Layout.bottomChromeInnerHorizontalPadding / 2
        case .selection:
            return UIConstants.Layout.selectionToolbarInnerHorizontalPadding
        }
    }

    private var innerVerticalPadding: CGFloat {
        switch kind {
        case .persistent:
            return UIConstants.Layout.bottomChromeInnerVerticalPadding
        case .selection:
            return UIConstants.Layout.selectionToolbarInnerVerticalPadding
        }
    }

    private var borderOpacity: Double {
        switch kind {
        case .persistent:
            return 0.07
        case .selection:
            return 0.06
        }
    }

    var body: some View {
        content()
            .padding(.horizontal, innerHorizontalPadding)
            .padding(.vertical, innerVerticalPadding)
            .frame(minHeight: minimumHeight)
            .background {
                if kind == .persistent {
                    persistentSurface
                } else {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            shape
                                .fill(Color.white.opacity(0.02))
                        }
                }
            }
            .clipShape(shape)
            .overlay {
                shape
                    .stroke(Color.white.opacity(borderOpacity), lineWidth: 0.75)
            }
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, bottomPadding)
            .contentShape(
                BottomChromeHitShape(
                    horizontalInset: horizontalInset,
                    bottomInset: bottomPadding
                )
            )
            .modifier(BottomChromeBottomSafeAreaModifier(ignoresBottomSafeArea: ignoresBottomSafeArea))
            .bottomChromeVisibility(isVisible, hiddenOffset: hiddenOffset)
    }

    @ViewBuilder
    private var persistentSurface: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape
                    .fill(Color.white.opacity(0.32))
                    .blur(radius: 12)
                    .mask(shape.stroke(lineWidth: 4))
                    .blendMode(.overlay)
            }
    }
}

private struct BottomChromeBottomSafeAreaModifier: ViewModifier {
    let ignoresBottomSafeArea: Bool

    func body(content: Content) -> some View {
        if ignoresBottomSafeArea {
            content.ignoresSafeArea(.container, edges: .bottom)
        } else {
            content
        }
    }
}
