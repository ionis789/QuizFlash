//
//  CardZoneLayoutEngine.swift
//  QuizFlash
//
//  Shared deterministic layout rules for zone-based card rendering.
//

import CoreGraphics
import Foundation

// MARK: - Card Zone Layout Spec

/// Input values used to resolve one zone's card-local rectangle.
struct CardZoneLayoutSpec: Equatable {
    let availableWidth: CGFloat
    let fontScale: CGFloat
    let minimumAutoWidth: CGFloat

    init(
        availableWidth: CGFloat,
        fontScale: CGFloat,
        minimumAutoWidth: CGFloat = 1
    ) {
        self.availableWidth = max(availableWidth, 1)
        self.fontScale = fontScale
        self.minimumAutoWidth = max(minimumAutoWidth, 1)
    }
}

// MARK: - Card Zone Layout Result

/// Resolved layout values for one leaf zone.
struct CardZoneLayoutResult: Equatable {
    let estimatedContentSize: CGSize
    let measuredContentSize: CGSize
    let blockSize: CGSize
    let leadingInset: CGFloat
    let contentLayoutWidth: CGFloat
    let textWidthLimit: CGFloat?
    let textHorizontalInsets: CGFloat
    let bulletHorizontalInset: CGFloat
    let usesIntrinsicTextMeasurement: Bool
    let usesAutoBlockCentering: Bool
    let resolvedTextAlignment: TextBlockAlignment

    var blockFrame: CGRect {
        CGRect(
            x: leadingInset,
            y: 0,
            width: blockSize.width,
            height: blockSize.height
        )
    }
}

// MARK: - Card Zone Layout Engine

/// Resolves zone rectangles for editor, preview, and play-mode rendering.
enum CardZoneLayoutEngine {
    static func leafLayout(
        for zone: ZoneModel,
        spec: CardZoneLayoutSpec,
        measuredContentSize: CGSize
    ) -> CardZoneLayoutResult {
        let estimatedSize = FlashcardGridContentEstimator.estimatedSize(
            for: zone,
            fontScale: spec.fontScale,
            availableWidth: spec.availableWidth
        )
        let textHorizontalInsets = horizontalTextInsets(for: zone)
        let bulletHorizontalInset = bulletInset(for: zone)
        let intrinsicMeasurement = usesIntrinsicTextMeasurement(for: zone)
        let usesMediaIntrinsicLayout = usesMediaIntrinsicLayout(for: zone)
        let measuredWidth: CGFloat = {
            if usesMediaIntrinsicLayout {
                return estimatedSize.width
            }
            return measuredContentSize.width > 0
                ? measuredContentSize.width
                : estimatedSize.width
        }()
        let measuredHeight: CGFloat = {
            if usesMediaIntrinsicLayout {
                return estimatedSize.height
            }
            return measuredContentSize.height > 0
                ? measuredContentSize.height
                : estimatedSize.height
        }()
        let naturalWidth = min(
            max(ceil(measuredWidth), minimumAutoWidth(for: zone, spec: spec)),
            spec.availableWidth
        )
        let resolvedWidth = blockWidth(
            for: zone,
            naturalWidth: naturalWidth,
            availableWidth: spec.availableWidth
        )
        let resolvedHeight = blockHeight(
            for: zone,
            measuredHeight: measuredHeight,
            availableWidth: spec.availableWidth
        )
        let blockSize = CGSize(width: resolvedWidth, height: resolvedHeight)
        let leadingInset = leadingInset(
            for: zone,
            blockWidth: resolvedWidth,
            availableWidth: spec.availableWidth
        )
        let contentLayoutWidth = max(resolvedWidth, 1)
        let textWidthLimit = intrinsicMeasurement
            ? max(contentLayoutWidth - textHorizontalInsets - bulletHorizontalInset, 1)
            : nil

        return CardZoneLayoutResult(
            estimatedContentSize: roundedSize(estimatedSize),
            measuredContentSize: roundedSize(measuredContentSize),
            blockSize: roundedSize(blockSize),
            leadingInset: ceil(leadingInset),
            contentLayoutWidth: ceil(contentLayoutWidth),
            textWidthLimit: textWidthLimit.map(ceil),
            textHorizontalInsets: ceil(textHorizontalInsets),
            bulletHorizontalInset: ceil(bulletHorizontalInset),
            usesIntrinsicTextMeasurement: intrinsicMeasurement,
            usesAutoBlockCentering: zone.blockAlignment == .auto,
            resolvedTextAlignment: zone.textAlignment
        )
    }

    private static func blockWidth(
        for zone: ZoneModel,
        naturalWidth: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        if usesMediaIntrinsicLayout(for: zone) {
            return min(max(ceil(naturalWidth), 1), availableWidth)
        }

        switch zone.sizeMode {
        case .auto:
            return min(max(ceil(naturalWidth), 1), availableWidth)
        case .fillWidth:
            return availableWidth
        case .fixed:
            return min(max(ceil(zone.fixedWidth ?? naturalWidth), 1), availableWidth)
        }
    }

    private static func blockHeight(
        for zone: ZoneModel,
        measuredHeight: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        let contentHeight = max(ceil(measuredHeight), 1)

        if usesMediaIntrinsicLayout(for: zone) {
            return contentHeight
        }

        switch zone.sizeMode {
        case .auto, .fillWidth:
            return contentHeight
        case .fixed:
            let fixedHeight = max(ceil(zone.fixedHeight ?? measuredHeight), 1)
            let resolvedHeight = fixedHeightCanScaleContent(for: zone)
                ? fixedHeight
                : max(fixedHeight, contentHeight)
            return min(resolvedHeight, maximumFixedHeight(forAvailableWidth: availableWidth))
        }
    }

    private static func maximumFixedHeight(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        max(ceil(availableWidth * 1.75), 520)
    }

    private static func fixedHeightCanScaleContent(for zone: ZoneModel) -> Bool {
        switch zone.contentType {
        case .image, .sketch, .empty:
            return true
        case .text, .code:
            return false
        }
    }

    private static func usesMediaIntrinsicLayout(for zone: ZoneModel) -> Bool {
        switch zone.contentType {
        case .image, .sketch:
            return true
        case .empty, .text, .code:
            return false
        }
    }

    private static func leadingInset(
        for zone: ZoneModel,
        blockWidth: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        switch zone.blockAlignment {
        case .leading:
            return 0
        case .center, .auto:
            return max((availableWidth - blockWidth) / 2, 0)
        case .trailing:
            return max(availableWidth - blockWidth, 0)
        }
    }

    private static func usesIntrinsicTextMeasurement(for zone: ZoneModel) -> Bool {
        guard zone.contentType == .text else { return false }
        let previewText = MathTextSanitizer.stripTerminalZonePeriod(zone.text)
        return !previewText.isEmpty && !previewText.hasPrefix("```")
    }

    private static func horizontalTextInsets(for zone: ZoneModel) -> CGFloat {
        zone.highlightColor != .none ? CardZoneContentMetrics.highlightedHorizontalPadding : 0
    }

    private static func bulletInset(for zone: ZoneModel) -> CGFloat {
        zone.hasBullet
            ? CardZoneContentMetrics.bulletWidth + CardZoneContentMetrics.bulletSpacing
            : 0
    }

    private static func minimumAutoWidth(
        for zone: ZoneModel,
        spec: CardZoneLayoutSpec
    ) -> CGFloat {
        guard !zone.hasContent else { return 1 }
        return spec.minimumAutoWidth
    }

    private static func roundedSize(_ size: CGSize) -> CGSize {
        CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}
