//
//  AdaptiveLayoutContext.swift
//  QuizFlash
//
//  Shared container-width layout helpers for adaptive screen composition.
//

import CoreGraphics

// MARK: - Container Width Class

/// Semantic width buckets resolved from the real width available to a screen container.
enum ContainerWidthClass: Equatable {
    case narrow
    case medium
    case wide
}

// MARK: - Adaptive Layout Width Thresholds

/// Thresholds that map an available content width to a semantic width class.
struct AdaptiveLayoutWidthThresholds: Equatable {
    let medium: CGFloat
    let wide: CGFloat

    /// Resolves a semantic width class from the provided available width.
    func widthClass(for availableWidth: CGFloat) -> ContainerWidthClass {
        if availableWidth >= wide {
            return .wide
        }
        if availableWidth >= medium {
            return .medium
        }
        return .narrow
    }
}

// MARK: - Adaptive Layout Context

/// Shared container-width facts that screen-specific layout models can build upon.
struct AdaptiveLayoutContext: Equatable {
    let containerWidth: CGFloat
    let horizontalInset: CGFloat
    let rawAvailableWidth: CGFloat
    let maxContentWidth: CGFloat?
    let contentWidth: CGFloat
    let widthClass: ContainerWidthClass

    init(
        containerWidth: CGFloat,
        horizontalInset: CGFloat,
        thresholds: AdaptiveLayoutWidthThresholds,
        maxContentWidth: CGFloat? = nil
    ) {
        self.containerWidth = containerWidth
        self.horizontalInset = horizontalInset

        let rawAvailableWidth = max(containerWidth - (horizontalInset * 2), 0)
        self.rawAvailableWidth = rawAvailableWidth
        self.maxContentWidth = maxContentWidth
        contentWidth = maxContentWidth.map { min(rawAvailableWidth, $0) } ?? rawAvailableWidth
        widthClass = thresholds.widthClass(for: rawAvailableWidth)
    }
}
