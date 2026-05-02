//
//  ZoneEditorCanvas.swift
//  QuizFlash
//
//  Reusable card canvas for zone-based authoring surfaces.
//

import SwiftUI
import UIKit

// MARK: - Zone Editor Canvas Tap Context

/// Card-local tap information used by owners to create zones semantically.
struct ZoneEditorCanvasTapContext {
    let location: CGPoint
    let contentSize: CGSize
    let zoneFrames: [ZoneEditorResolvedZoneFrame]
}

// MARK: - Zone Editor Canvas

/// A reusable editing canvas that renders a zone tree on a real flashcard surface.
struct ZoneEditorCanvas: View {
    @Bindable var content: ZoneCardContent
    @Binding var selectedPath: ZonePath?
    @Binding var previewDirection: AddDirection?

    let highlightContext: HighlightContext?
    let fontScale: CGFloat
    let verticalAlignmentFallback: ZoneVerticalAlignment
    let onEmptySpaceTap: (ZoneEditorCanvasTapContext) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(KeyboardMonitor.self) private var keyboardMonitor

    @State private var zoneFrames: [ZoneEditorResolvedZoneFrame] = []
    @State private var scheduledScrollTask: Task<Void, Never>?
    @State private var lastTapDebugLine: String = ""

    private static let coordinateSpaceName = "ZoneEditorCanvasContent"
    private static let playModeCardAspectRatio: CGFloat = 369.0 / 613.0

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var cardCornerRadius: CGFloat { isCompact ? 42 : 52 }
    private var editorCardHorizontalPadding: CGFloat { isCompact ? 20 : 28 }
    private var editorCardVerticalPadding: CGFloat { isCompact ? 20 : 24 }

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = isCompact ? 12 : 24
            let maxEditorWidth: CGFloat = isCompact ? .infinity : 620
            let proposedWidth = max(geometry.size.width - (horizontalInset * 2), 1)
            let cardWidth = min(proposedWidth, maxEditorWidth)
            let cardHeight = cardWidth / Self.playModeCardAspectRatio
            let contentWidth = max(cardWidth - (editorCardHorizontalPadding * 2), 1)
            let contentHeight = max(cardHeight - (editorCardVerticalPadding * 2), 1)
            let estimatedContentSize = FlashcardGridContentEstimator.estimatedSize(
                for: content.rootZone,
                fontScale: fontScale,
                availableWidth: contentWidth
            )
            let contentFitsVertically = estimatedContentSize.height <= contentHeight
            let resolvedVerticalAlignment = content.rootZone.verticalAlignment.resolved(
                fallback: verticalAlignmentFallback
            )
            let contentFrameAlignment: Alignment = contentFitsVertically
                ? frameAlignment(for: resolvedVerticalAlignment)
                : .top
            let keyboardAvoidanceInset = keyboardMonitor.isVisible
                ? max(keyboardMonitor.visibleHeight + UIConstants.Spacing.extraLarge, 160)
                : 0

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    zoneContentSurface(
                        contentWidth: contentWidth,
                        contentHeight: contentHeight,
                        contentFrameAlignment: contentFrameAlignment
                    )
                    .padding(.horizontal, editorCardHorizontalPadding)
                    .padding(.top, editorCardVerticalPadding)
                    .padding(.bottom, editorCardVerticalPadding + keyboardAvoidanceInset)
                    .frame(width: cardWidth, alignment: .topLeading)
                    .frame(minHeight: cardHeight + keyboardAvoidanceInset, alignment: .topLeading)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                .background(cardSurface)
                .overlay(cardBorder)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    debugOverlay
                        .padding(editorCardHorizontalPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, horizontalInset)
                .padding(.top, UIConstants.Spacing.small)
                .padding(.bottom, UIConstants.Spacing.small)
                .onChange(of: selectedPath) { _, newPath in
                    scheduleSelectionScroll(to: newPath, in: proxy)
                }
                .onChange(of: keyboardMonitor.visibleHeight) { _, _ in
                    scheduleSelectionScroll(to: selectedPath, in: proxy)
                }
                .onDisappear {
                    scheduledScrollTask?.cancel()
                    scheduledScrollTask = nil
                }
            }
        }
    }

    private func zoneContentSurface(
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        contentFrameAlignment: Alignment
    ) -> some View {
        ZoneEditorView(
            content: content,
            path: .root,
            selectedPath: $selectedPath,
            highlightContext: highlightContext,
            fontScale: fontScale,
            availableWidth: contentWidth,
            previewDirection: $previewDirection
        )
        .frame(width: contentWidth, alignment: .topLeading)
        .frame(minHeight: contentHeight, alignment: contentFrameAlignment)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(coordinateSpace: .named(Self.coordinateSpaceName))
                        .onEnded { value in
                            handleEmptySpaceTap(
                                location: value.location,
                                contentSize: CGSize(width: contentWidth, height: contentHeight)
                            )
                        }
                )
        }
        .coordinateSpace(name: Self.coordinateSpaceName)
        .overlayPreferenceValue(ZoneEditorZoneBoundsPreferenceKey.self) { bounds in
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ZoneEditorResolvedZoneFramePreferenceKey.self,
                    value: bounds.map {
                        ZoneEditorResolvedZoneFrame(
                            path: $0.path,
                            zoneID: $0.zoneID,
                            frame: proxy[$0.bounds]
                        )
                    }
                )
            }
        }
        .onPreferenceChange(ZoneEditorResolvedZoneFramePreferenceKey.self) { frames in
            zoneFrames = frames
        }
    }

    private func frameAlignment(for verticalAlignment: ZoneVerticalAlignment) -> Alignment {
        switch verticalAlignment {
        case .auto, .center:
            return .center
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }

    private func handleEmptySpaceTap(location: CGPoint, contentSize: CGSize) {
        guard !zoneFrames.contains(where: { $0.frame.insetBy(dx: -6, dy: -6).contains(location) }) else {
            lastTapDebugLine = "tap zone/select"
            return
        }

        lastTapDebugLine = "tap empty x=\(Int(location.x)) y=\(Int(location.y))"
        onEmptySpaceTap(
            ZoneEditorCanvasTapContext(
                location: location,
                contentSize: contentSize,
                zoneFrames: zoneFrames
            )
        )
    }

    private func scheduleSelectionScroll(to path: ZonePath?, in proxy: ScrollViewProxy) {
        scheduledScrollTask?.cancel()
        guard let path else { return }

        scheduledScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                proxy.scrollTo(path.id, anchor: keyboardMonitor.isVisible ? .top : .center)
            }
        }
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .fill(cardBackground)
            .shadow(color: shadowColor, radius: 12, y: 6)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .stroke(borderColor, lineWidth: 1)
    }

    @ViewBuilder
    private var debugOverlay: some View {
        if showsDebugOverlay {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedDebugLine)
                Text(lastTapDebugLine.isEmpty ? "tap idle" : lastTapDebugLine)
                if let selectedFrame {
                    Text("rect \(Int(selectedFrame.width))x\(Int(selectedFrame.height)) @ \(Int(selectedFrame.minX)),\(Int(selectedFrame.minY))")
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.orange)
            .padding(UIConstants.Spacing.tiny)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: UIConstants.Radius.small))
            .allowsHitTesting(false)
        }
    }

    private var selectedDebugLine: String {
        guard let selectedPath, let zone = content.zone(at: selectedPath) else {
            return "selected nil"
        }

        return "selected \(selectedPath.id) size=\(zone.sizeMode.rawValue) block=\(zone.blockAlignment.rawValue) text=\(zone.textAlignment.rawValue)"
    }

    private var selectedFrame: CGRect? {
        guard let selectedPath else { return nil }
        return zoneFrames.first { $0.path == selectedPath }?.frame
    }

    private var showsDebugOverlay: Bool {
        AppFeatures.current.showsVisualDebugOverlays
            && developmentPreferences.flashcardGridTextLayoutDebugEnabled
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(red: 0.068, green: 0.068, blue: 0.068))
            : AnyShapeStyle(Color(red: 0.92, green: 0.92, blue: 0.91))
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.42) : Color.black.opacity(0.12)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.08)
    }
}
