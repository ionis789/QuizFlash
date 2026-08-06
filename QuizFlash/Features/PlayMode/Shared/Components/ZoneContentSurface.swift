//
//  ZoneContentSurface.swift
//  QuizFlash
//
//  Reusable host surface for zone content. The parent supplies its layout
//  context; this view owns rendering, measurement, vertical placement, and
//  scroll policy so every playback surface follows the same rules.
//

import SwiftUI
import UIKit

enum ZoneContentVerticalScrollPolicy: Equatable, Sendable {
    case disabled
    case automatic
    case always
}

struct ZoneContentSurfaceLayoutContext: Equatable, Sendable {
    let containerWidth: CGFloat
    let viewportHeight: CGFloat?
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let verticalAlignment: ZoneVerticalAlignment
    let verticalScrollPolicy: ZoneContentVerticalScrollPolicy
    let scrollResetToken: Int

    static func intrinsic(
        width: CGFloat,
        horizontalPadding: CGFloat = 0,
        verticalPadding: CGFloat = 0,
        verticalAlignment: ZoneVerticalAlignment = .top
    ) -> Self {
        Self(
            containerWidth: width,
            viewportHeight: nil,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            verticalAlignment: verticalAlignment,
            verticalScrollPolicy: .disabled,
            scrollResetToken: 0
        )
    }

    static func viewport(
        size: CGSize,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        verticalAlignment: ZoneVerticalAlignment,
        verticalScrollPolicy: ZoneContentVerticalScrollPolicy = .automatic,
        scrollResetToken: Int = 0
    ) -> Self {
        Self(
            containerWidth: size.width,
            viewportHeight: size.height,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            verticalAlignment: verticalAlignment,
            verticalScrollPolicy: verticalScrollPolicy,
            scrollResetToken: scrollResetToken
        )
    }

    var sanitizedContainerWidth: CGFloat {
        max(containerWidth.isFinite ? containerWidth : 1, 1)
    }

    var sanitizedViewportHeight: CGFloat? {
        guard let viewportHeight, viewportHeight.isFinite else { return nil }
        return max(viewportHeight, 1)
    }

    var sanitizedHorizontalPadding: CGFloat {
        max(horizontalPadding.isFinite ? horizontalPadding : 0, 0)
    }

    var sanitizedVerticalPadding: CGFloat {
        max(verticalPadding.isFinite ? verticalPadding : 0, 0)
    }

    var availableContentWidth: CGFloat {
        max(sanitizedContainerWidth - (sanitizedHorizontalPadding * 2), 1)
    }
}

struct ZoneContentSurfaceRenderConfiguration {
    var centersLeafBlocks: Bool
    var alignmentDefaults: ZoneAlignmentDefaults = .standard
    var alignLeafBlocksToGroupLeading = false
    var animatesLayoutChanges = false
    var showsDebugGuides = false
    var showsViewportDebugGuide = false
    var showsZoneSurfaces = true
    var showsCodeBlockZoneSurfaces = false
    var usesBorderOnlyZoneHighlights = false
    var zoneHighlightStrokeStyle = StrokeStyle(lineWidth: 2)
    var debugGuideStyle: ZoneContentDebugGuideStyle = .debug
    var textVerticalPadding = ZoneContentMetrics.textVerticalPadding
    var textHorizontalPaddingOverride: CGFloat?
    var alignmentFeedback: ZoneAlignmentFeedback = .inactive
    var collectsDebugMetrics = false
    var leafTapBehavior: ZoneContentLeafTapBehavior = .all
}

struct ZoneContentSurfaceResolvedLayout: Equatable {
    let availableContentWidth: CGFloat
    let viewportLayout: ZoneContentLayout?
    let isVerticalScrollEnabled: Bool
}

enum ZoneContentSurfaceLayoutResolver {
    static func resolve(
        context: ZoneContentSurfaceLayoutContext,
        estimatedContentSize: CGSize,
        measuredContentSize: CGSize
    ) -> ZoneContentSurfaceResolvedLayout {
        guard let viewportHeight = context.sanitizedViewportHeight else {
            return ZoneContentSurfaceResolvedLayout(
                availableContentWidth: context.availableContentWidth,
                viewportLayout: nil,
                isVerticalScrollEnabled: false
            )
        }

        let layout = ZoneContentLayout(
            containerSize: CGSize(
                width: context.sanitizedContainerWidth,
                height: viewportHeight
            ),
            horizontalPadding: context.sanitizedHorizontalPadding,
            verticalPadding: context.sanitizedVerticalPadding,
            estimatedContentSize: estimatedContentSize,
            measuredContentSize: measuredContentSize,
            verticalAlignment: context.verticalAlignment
        )
        let isVerticalScrollEnabled: Bool
        switch context.verticalScrollPolicy {
        case .disabled:
            isVerticalScrollEnabled = false
        case .automatic:
            isVerticalScrollEnabled = !layout.contentFitsVertically
        case .always:
            isVerticalScrollEnabled = true
        }

        return ZoneContentSurfaceResolvedLayout(
            availableContentWidth: layout.availableContentWidth,
            viewportLayout: layout,
            isVerticalScrollEnabled: isVerticalScrollEnabled
        )
    }
}

struct ZoneContentSurfaceMetrics: Equatable {
    let layout: ZoneContentLayout?
    let rawMeasuredContentSize: CGSize
    let appliedMeasuredContentSize: CGSize
    let measurementSource: String
    let isVerticalScrollEnabled: Bool
}

struct ZoneContentSurfaceDiagnostics: Equatable {
    let metrics: ZoneContentSurfaceMetrics
    let leafSnapshots: [ZoneContentLeafLayoutDebugSnapshot]
}

struct ZoneContentSurface: View {
    let zone: ZoneModel
    let fontScale: CGFloat
    let layoutContext: ZoneContentSurfaceLayoutContext
    let renderConfiguration: ZoneContentSurfaceRenderConfiguration
    var identity: String?
    var coordinateSpaceName: String?
    var onTap: (() -> Void)?
    var onZoneTap: ((UUID) -> Void)?
    var onMeasuredWidthChange: ((CGFloat) -> Void)?
    var onBlockBoundsChange: (([ZoneContentRenderBlockBounds]) -> Void)?
    var onDiagnosticsChange: ((ZoneContentSurfaceDiagnostics) -> Void)?
    var onDebugEvent: ((String) -> Void)?

    @State private var rawMeasuredContentSize: CGSize = .zero
    @State private var measurementSource = "none"
    @State private var leafSnapshots: [ZoneContentLeafLayoutDebugSnapshot] = []

    private var contentIdentity: String {
        identity ?? zone.id.uuidString
    }

    private var estimatedContentSize: CGSize {
        ZoneContentEstimator.estimatedSize(
            for: zone,
            fontScale: fontScale,
            availableWidth: layoutContext.availableContentWidth
        )
    }

    private var appliedMeasuredContentSize: CGSize {
        Self.appliedMeasurement(
            rawMeasuredContentSize,
            estimatedContentSize: estimatedContentSize
        )
    }

    private var resolvedLayout: ZoneContentSurfaceResolvedLayout {
        ZoneContentSurfaceLayoutResolver.resolve(
            context: layoutContext,
            estimatedContentSize: estimatedContentSize,
            measuredContentSize: appliedMeasuredContentSize
        )
    }

    private var metrics: ZoneContentSurfaceMetrics {
        ZoneContentSurfaceMetrics(
            layout: resolvedLayout.viewportLayout,
            rawMeasuredContentSize: rawMeasuredContentSize,
            appliedMeasuredContentSize: appliedMeasuredContentSize,
            measurementSource: measurementSource,
            isVerticalScrollEnabled: resolvedLayout.isVerticalScrollEnabled
        )
    }

    private var diagnostics: ZoneContentSurfaceDiagnostics {
        ZoneContentSurfaceDiagnostics(
            metrics: metrics,
            leafSnapshots: leafSnapshots
        )
    }

    var body: some View {
        Group {
            if let layout = resolvedLayout.viewportLayout {
                viewportBody(layout: layout)
            } else {
                intrinsicBody
            }
        }
        .onAppear {
            publishDiagnosticsIfNeeded()
        }
        .onChange(of: diagnostics) { _, _ in
            publishDiagnosticsIfNeeded()
        }
        .onChange(of: contentIdentity) { _, _ in
            resetMeasurement()
        }
        .onChange(of: layoutContext.availableContentWidth) { _, _ in
            resetMeasurement()
        }
        .onChange(of: fontScale) { _, _ in
            resetMeasurement()
        }
    }

    private var intrinsicBody: some View {
        baseRenderedContent
            .padding(.horizontal, layoutContext.sanitizedHorizontalPadding)
            .padding(.vertical, layoutContext.sanitizedVerticalPadding)
            .frame(
                width: layoutContext.sanitizedContainerWidth,
                alignment: .topLeading
            )
    }

    private func viewportBody(layout: ZoneContentLayout) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                scrollOffsetProbe

                if renderConfiguration.showsViewportDebugGuide {
                    viewportDebugGuide(layout: layout)
                }

                measuredRenderedContent
                    .padding(.top, layoutContext.sanitizedVerticalPadding + layout.contentTopInset)
                    .padding(.leading, layoutContext.sanitizedHorizontalPadding)
                    .padding(.bottom, layoutContext.sanitizedVerticalPadding + layout.contentBottomInset)
            }
            .frame(
                width: layout.containerSize.width,
                height: layout.scrollContentHeight,
                alignment: .topLeading
            )
        }
        .scrollDisabled(!resolvedLayout.isVerticalScrollEnabled)
        .background(
            ZoneContentScrollViewStabilizer(
                resetToken: layoutContext.scrollResetToken
            )
        )
        .coordinateSpace(name: resolvedCoordinateSpaceName)
        .id("\(contentIdentity)-viewport")
        .frame(
            width: layout.containerSize.width,
            height: layout.containerSize.height
        )
    }

    private var baseRenderedContent: some View {
        ZoneContentRenderView(
            zone: zone,
            fontScale: fontScale,
            availableWidth: resolvedLayout.availableContentWidth,
            centersLeafBlocks: renderConfiguration.centersLeafBlocks,
            alignmentDefaults: renderConfiguration.alignmentDefaults,
            alignLeafBlocksToGroupLeading: renderConfiguration.alignLeafBlocksToGroupLeading,
            animatesLayoutChanges: renderConfiguration.animatesLayoutChanges,
            showsDebugGuides: renderConfiguration.showsDebugGuides,
            showsZoneSurfaces: renderConfiguration.showsZoneSurfaces,
            showsCodeBlockZoneSurfaces: renderConfiguration.showsCodeBlockZoneSurfaces,
            usesBorderOnlyZoneHighlights: renderConfiguration.usesBorderOnlyZoneHighlights,
            zoneHighlightStrokeStyle: renderConfiguration.zoneHighlightStrokeStyle,
            debugGuideStyle: renderConfiguration.debugGuideStyle,
            textVerticalPadding: renderConfiguration.textVerticalPadding,
            textHorizontalPaddingOverride: renderConfiguration.textHorizontalPaddingOverride,
            alignmentFeedback: renderConfiguration.alignmentFeedback,
            collectsDebugMetrics: renderConfiguration.collectsDebugMetrics,
            leafTapBehavior: renderConfiguration.leafTapBehavior,
            onTap: onTap,
            onZoneTap: onZoneTap,
            onBlockBoundsChange: handleBlockBoundsChange,
            onRootBlockWidthChange: onMeasuredWidthChange
        )
        .coordinateSpace(name: ZoneContentRenderCoordinateSpace.name)
        .frame(width: resolvedLayout.availableContentWidth, alignment: .topLeading)
        .onPreferenceChange(ZoneContentLeafDebugPreferenceKey.self) { snapshots in
            guard onDiagnosticsChange != nil else { return }
            leafSnapshots = snapshots.sorted { $0.path < $1.path }
        }
    }

    private var measuredRenderedContent: some View {
        baseRenderedContent
        .onGeometryChange(for: CGSize.self) { proxy in
            CGSize(
                width: ceil(proxy.size.width),
                height: ceil(proxy.size.height)
            )
        } action: { size in
            acceptMeasurement(size, source: "root-geometry")
        }
    }

    private var resolvedCoordinateSpaceName: String {
        coordinateSpaceName ?? "ZoneContentSurfaceScroll-\(contentIdentity)"
    }

    private var scrollOffsetProbe: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(resolvedCoordinateSpaceName)).minY
            } action: { minY in
                onDebugEvent?("scroll probe minY=\(Self.metric(minY)) offset=\(Self.metric(-minY))")
            }
            .allowsHitTesting(false)
    }

    private func viewportDebugGuide(layout: ZoneContentLayout) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
                Color.cyan.opacity(0.9),
                style: StrokeStyle(lineWidth: 1.6, dash: [7, 5])
            )
            .frame(
                width: layout.debugAvailableFrame.width,
                height: layout.debugAvailableFrame.height,
                alignment: .topLeading
            )
            .padding(.leading, layoutContext.sanitizedHorizontalPadding)
            .padding(.top, layoutContext.sanitizedVerticalPadding)
            .allowsHitTesting(false)
    }

    private func handleBlockBoundsChange(_ bounds: [ZoneContentRenderBlockBounds]) {
        onBlockBoundsChange?(bounds)
        guard layoutContext.sanitizedViewportHeight != nil else { return }

        let expectedLeafCount = ZoneContentRenderPolicy.renderableLeafCount(in: zone)
        guard let blockSize = Self.measuredContentSize(
            from: bounds,
            expectedLeafCount: expectedLeafCount,
            fallbackWidth: resolvedLayout.availableContentWidth
        ) else {
            let reportedLeafCount = Set(
                bounds
                    .filter { $0.kind == "leaf" }
                    .map(\.zoneID)
            ).count
            onDebugEvent?(
                "geometry ignored incomplete-bounds reported=\(reportedLeafCount) expected=\(expectedLeafCount)"
            )
            return
        }
        acceptMeasurement(blockSize, source: "leaf-block-bounds")
    }

    private func acceptMeasurement(_ newSize: CGSize, source: String) {
        guard layoutContext.sanitizedViewportHeight != nil else { return }
        guard newSize.width > 0, newSize.height > 0 else {
            onDebugEvent?("geometry ignored non-positive source=\(source) raw=\(Self.sizeMetric(newSize))")
            return
        }

        let minimumHeight = Self.minimumMeasurementHeight(
            estimatedContentSize: estimatedContentSize
        )
        let maximumHeight = Self.maximumMeasurementHeight(
            estimatedContentSize: estimatedContentSize,
            context: layoutContext
        )
        guard newSize.height + 0.5 >= minimumHeight else {
            onDebugEvent?("geometry rejected source=\(source) raw=\(Self.sizeMetric(newSize)) minH=\(Self.metric(minimumHeight))")
            return
        }
        guard newSize.height <= maximumHeight else {
            onDebugEvent?("geometry rejected oversized source=\(source) raw=\(Self.sizeMetric(newSize)) maxH=\(Self.metric(maximumHeight))")
            return
        }

        if source == "root-geometry",
           measurementSource == "leaf-block-bounds",
           rawMeasuredContentSize.height > 0,
           newSize.height <= rawMeasuredContentSize.height + 0.5 {
            onDebugEvent?("geometry ignored root-fallback-after-leaf raw=\(Self.sizeMetric(newSize)) old=\(Self.sizeMetric(rawMeasuredContentSize))")
            return
        }

        if source == "root-geometry",
           rawMeasuredContentSize.height > 0,
           newSize.height > rawMeasuredContentSize.height * 1.5,
           newSize.height - rawMeasuredContentSize.height > 120 {
            onDebugEvent?("geometry rejected stale-root raw=\(Self.sizeMetric(newSize)) old=\(Self.sizeMetric(rawMeasuredContentSize))")
            return
        }

        guard abs(rawMeasuredContentSize.width - newSize.width) > 0.5
                || abs(rawMeasuredContentSize.height - newSize.height) > 0.5 else {
            onDebugEvent?("geometry unchanged source=\(source) raw=\(Self.sizeMetric(newSize)) old=\(Self.sizeMetric(rawMeasuredContentSize))")
            return
        }

        let oldSize = rawMeasuredContentSize
        rawMeasuredContentSize = newSize
        measurementSource = source
        onDebugEvent?("geometry accepted source=\(source) old=\(Self.sizeMetric(oldSize)) new=\(Self.sizeMetric(newSize)) minH=\(Self.metric(minimumHeight))")
    }

    private func resetMeasurement() {
        rawMeasuredContentSize = .zero
        measurementSource = "none"
        leafSnapshots = []
        onDebugEvent?("surface context changed; measurements reset")
    }

    private func publishDiagnosticsIfNeeded() {
        onDiagnosticsChange?(diagnostics)
    }

    static func appliedMeasurement(
        _ measuredSize: CGSize,
        estimatedContentSize: CGSize
    ) -> CGSize {
        guard measuredSize.width > 0, measuredSize.height > 0 else { return .zero }
        guard measuredSize.height + 0.5 >= minimumMeasurementHeight(
            estimatedContentSize: estimatedContentSize
        ) else {
            return .zero
        }
        return measuredSize
    }

    static func minimumMeasurementHeight(estimatedContentSize: CGSize) -> CGFloat {
        max(1, ceil(estimatedContentSize.height * 0.25))
    }

    static func maximumMeasurementHeight(
        estimatedContentSize: CGSize,
        context: ZoneContentSurfaceLayoutContext
    ) -> CGFloat {
        max(
            ceil(estimatedContentSize.height * 12),
            ceil((context.sanitizedViewportHeight ?? 1) * 12),
            1
        )
    }

    static func measuredContentSize(
        from bounds: [ZoneContentRenderBlockBounds],
        expectedLeafCount: Int,
        fallbackWidth: CGFloat
    ) -> CGSize? {
        let framesByZone = Dictionary(
            bounds.compactMap { bound -> (UUID, CGRect)? in
                guard bound.kind == "leaf" else { return nil }
                let frame = bound.frame
                guard !frame.isNull,
                      !frame.isInfinite,
                      frame.width > 0,
                      frame.height > 0 else {
                    return nil
                }
                return (bound.zoneID, frame)
            },
            uniquingKeysWith: { _, latest in latest }
        )
        guard expectedLeafCount > 0,
              framesByZone.count == expectedLeafCount else {
            return nil
        }

        let frames = Array(framesByZone.values)
        let rootGroupHeight = bounds
            .first(where: { $0.kind == "group" && $0.path == "root" })
            .map { max($0.blockSize.height, $0.frame.height) }
            ?? 0
        let minY = min(frames.map(\.minY).min() ?? 0, 0)
        let maxY = frames.map(\.maxY).max() ?? 0
        let maxX = frames.map(\.maxX).max() ?? fallbackWidth

        return CGSize(
            width: ceil(max(fallbackWidth, maxX)),
            height: ceil(max(max(maxY - minY, rootGroupHeight), 1))
        )
    }

    private static func sizeMetric(_ size: CGSize) -> String {
        "\(metric(size.width))x\(metric(size.height))"
    }

    private static func metric(_ value: CGFloat) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", value)
    }
}

private struct ZoneContentScrollViewStabilizer: UIViewRepresentable {
    let resetToken: Int

    final class Coordinator {
        var appliedResetToken: Int?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = view.zoneContentNearestAncestorScrollView() else { return }
            scrollView.bounces = false
            scrollView.alwaysBounceVertical = false

            guard context.coordinator.appliedResetToken != resetToken else { return }
            context.coordinator.appliedResetToken = resetToken
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top),
                animated: false
            )
        }
    }
}

private extension UIView {
    func zoneContentNearestAncestorScrollView() -> UIScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}
