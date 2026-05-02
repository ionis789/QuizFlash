//
//  EditorFormatMenuBar.swift
//  QuizFlash
//
//  Format bar providing text/media formatting controls and a radial drag menu
//  for adding zones in any direction.
//

import SwiftUI

// MARK: - Editor Format Menu Bar

/// The persistent formatting toolbar shown near the top of the card editor.
///
/// Contains:
/// - A radial drag-to-add button for inserting zones in any direction
/// - Text formatting controls (style, weight, alignment, colour, highlight, bullet)
/// - Media controls (alignment, size) when the selected zone contains an image or sketch
/// - A split button (visible when the focused zone has ≥ 2 lines)
/// - A delete button and a "Done" button to dismiss the bar
struct EditorFormatMenuBar: View {
    @Environment(AppPreferences.self) private var appPreferences

    let content: ZoneCardContent
    let path: ZonePath

    var onAddZoneAction: (AddDirection) -> Void
    var onPreviewDirection: (AddDirection?) -> Void
    var onSplit: () -> Void
    var onDuplicate: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onChoosePhoto: () -> Void
    var onSketch: () -> Void
    var canPreview: Bool
    var onPreview: () -> Void
    var onClose: () -> Void

    // MARK: - Local UI State
    @State private var isDraggingMenu = false
    @State private var activeDirection: AddDirection? = nil

    // MARK: - Layout Constants
    private let menuCenter = CGPoint(x: 50, y: 86)
    /// Radial distance between the hub and each directional bubble (in points).
    private let arrowRadius: CGFloat = 44
    /// Minimum drag distance from the hub centre required to select a direction.
    private let captureRadius: CGFloat = 20

    init(
        content: ZoneCardContent,
        path: ZonePath,
        onAddZoneAction: @escaping (AddDirection) -> Void,
        onPreviewDirection: @escaping (AddDirection?) -> Void,
        onSplit: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onChoosePhoto: @escaping () -> Void,
        onSketch: @escaping () -> Void,
        canPreview: Bool,
        onPreview: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.content = content
        self.path = path
        self.onAddZoneAction = onAddZoneAction
        self.onPreviewDirection = onPreviewDirection
        self.onSplit = onSplit
        self.onDuplicate = onDuplicate
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onChoosePhoto = onChoosePhoto
        self.onSketch = onSketch
        self.canPreview = canPreview
        self.onPreview = onPreview
        self.onClose = onClose
    }

    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var zoneController = ZoneController.shared
    private var lineTracker = ZoneLineTracker.shared
    private var locale: Locale { appPreferences.resolvedLocale }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    /// Returns `true` when the focused zone has at least 2 lines and can be split.
    private var canSplit: Bool {
        guard let zone = zone,
              zone.contentType == .text,
              let zoneID = zone.id as UUID? else { return false }

        if let heightInfo = zoneController.zoneHeightInfo(for: zoneID) {
            return heightInfo.canSplit
        }
        return lineTracker.canSplitZone(zoneID: zoneID)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            dragMenuButton
                .padding(.leading, 12)
                .padding(.trailing, 8)
            
            Divider().frame(height: 28)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    cardActionTools
                    toolbarDivider
                    addZoneTapTools

                    if canSplit { ToolbarButton(icon: "rectangle.split.1x2", accessibilityLabel: localized("Split Zone")) { onSplit() } }
                    
                    if zone?.contentType == .text || zone?.contentType == .empty { textTools }
                    else if zone?.contentType == .image || zone?.contentType == .sketch { mediaTools }

                    ToolbarButton(icon: "arrow.up", accessibilityLabel: localized("Move Up")) { onMoveUp() }
                    ToolbarButton(icon: "arrow.down", accessibilityLabel: localized("Move Down")) { onMoveDown() }
                    ToolbarButton(icon: "doc.on.doc", accessibilityLabel: localized("Duplicate")) { onDuplicate() }
                    ToolbarButton(icon: "trash", tint: .red, accessibilityLabel: localized("Delete")) { content.deleteZone(at: path); onClose() }
                }
                .padding(.horizontal, 8)
            }
            
            Divider().frame(height: 28)
            
            Button { onClose() } label: {
                Text(localized("Done"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(accent, in: Capsule())
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
        )
    }
    
    // MARK: - Drag Menu Button

    private var dragMenuButton: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.body.weight(.medium))
            .foregroundStyle(isDraggingMenu ? .white : accent)
            .frame(width: 34, height: 34)
            .background(isDraggingMenu ? accent : accent.opacity(0.12), in: Capsule())
            .overlay {
                if isDraggingMenu {
                    // Radial direction picker — appears while the user is dragging
                    DirectionPopoverMenu(
                        activeDirection: activeDirection,
                        accent: accent,
                        arrowRadius: arrowRadius
                    )
                    .offset(x: menuCenter.x, y: menuCenter.y)
                    .zIndex(1)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.1, anchor: .bottomLeading).combined(with: .opacity).animation(.spring(response: 0.35, dampingFraction: 0.7)),
                            removal: .scale(scale: 0.1, anchor: .bottomLeading).combined(with: .opacity).animation(.easeOut(duration: 0.2))
                        )
                    )
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in handleDragChange(value) }
                    .onEnded { value in handleDragEnd(value) }
            )
    }

    private var cardActionTools: some View {
        HStack(spacing: 8) {
            ToolbarButton(
                icon: "photo.on.rectangle",
                accessibilityLabel: localized("Choose Photos"),
                action: onChoosePhoto
            )
            ToolbarButton(
                icon: "pencil.and.scribble",
                accessibilityLabel: localized("Sketch"),
                action: onSketch
            )
            ToolbarButton(
                icon: "eye",
                tint: canPreview ? .primary : .secondary,
                isEnabled: canPreview,
                accessibilityLabel: localized("Preview"),
                action: onPreview
            )
        }
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 28)
    }

    private var addZoneTapTools: some View {
        HStack(spacing: 8) {
            ToolbarButton(icon: AddDirection.left.icon, accessibilityLabel: localized("Add Left")) {
                onAddZoneAction(.left)
            }
            ToolbarButton(icon: AddDirection.up.icon, accessibilityLabel: localized("Add Above")) {
                onAddZoneAction(.up)
            }
            ToolbarButton(icon: AddDirection.down.icon, accessibilityLabel: localized("Add Below")) {
                onAddZoneAction(.down)
            }
            ToolbarButton(icon: AddDirection.right.icon, accessibilityLabel: localized("Add Right")) {
                onAddZoneAction(.right)
            }
        }
    }

    // MARK: - Drag Handling

    private func handleDragChange(_ value: DragGesture.Value) {
        if !isDraggingMenu {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isDraggingMenu = true
            }
        }

        // Scale up translation so the user does not need to drag far.
        let dx = value.translation.width * 1.3
        let dy = value.translation.height * 1.3
        let distToCenter = hypot(dx, dy)

        // Map the drag angle to one of the four cardinal directions.
        var newDir: AddDirection? = nil
        if distToCenter > captureRadius {
            let angle = atan2(dy, dx)
            let pi = CGFloat.pi
            if angle > -pi/4 && angle <= pi/4 { newDir = .right }
            else if angle > pi/4 && angle <= 3*pi/4 { newDir = .down }
            else if angle > -3*pi/4 && angle <= -pi/4 { newDir = .up }
            else { newDir = .left }
        }

        // Only trigger haptic feedback and state update when crossing a boundary.
        let prevDir = activeDirection
        if newDir != prevDir {
            if newDir != nil { UISelectionFeedbackGenerator().selectionChanged() }
            else { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                activeDirection = newDir
            }
            onPreviewDirection(newDir)
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value) {
        let finalDir = activeDirection

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isDraggingMenu = false
            activeDirection = nil
            onPreviewDirection(nil)
        }

        if let dir = finalDir { onAddZoneAction(dir) }
    }
    
    // MARK: - Text Tools
    private var textTools: some View {
        HStack(spacing: 8) {
            verticalAlignmentMenu
            sizeModeMenu
            if showsBlockPositionMenu { blockAlignmentMenu }
            textAlignmentMenu

            Menu {
                ForEach([TextBlockStyle.title, .headline, .body, .caption], id: \.self) { style in
                    Button {
                        content.updateZone(at: path) { $0.textStyle = style }
                    } label: {
                        HStack {
                            Text(style.localizedName(locale: locale))
                            if zone?.textStyle == style { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: { ToolbarButton(icon: "textformat.size", accessibilityLabel: localized("Text Size")) }
            
            ToolbarButton(icon: "bold", isActive: zone?.isBold == true, accessibilityLabel: localized("Bold")) { content.updateZone(at: path) { $0.isBold.toggle() } }
            ToolbarButton(icon: "italic", isActive: zone?.isItalic == true, accessibilityLabel: localized("Italic")) { content.updateZone(at: path) { $0.isItalic.toggle() } }
            
            Menu {
                ForEach(FontFamily.allCases, id: \.self) { family in
                    Button {
                        content.updateZone(at: path) { $0.fontFamily = family }
                    } label: {
                        HStack {
                            Image(systemName: family.icon)
                            Text(family.localizedName(locale: locale))
                            if zone?.fontFamily == family { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: { ToolbarButton(icon: zone?.fontFamily.icon ?? "textformat", accessibilityLabel: localized("Font")) }

            Menu {
                ForEach(TextBlockColor.allCases, id: \.self) { color in
                    Button { content.updateZone(at: path) { $0.textColor = color } } label: { HStack { Circle().fill(color.color).frame(width: 14, height: 14); Text(color.localizedName(locale: locale)) } }
                }
            } label: { ToolbarButton(icon: "paintpalette", tint: zone?.textColor.color ?? .primary, accessibilityLabel: localized("Text Color")) }
            
            Menu {
                ForEach(HighlightColor.allCases, id: \.self) { highlight in
                    Button { content.updateZone(at: path) { $0.highlightColor = highlight } } label: {
                        HStack {
                            if highlight != .none { RoundedRectangle(cornerRadius: 2).fill(highlight.color ?? .clear).frame(width: 14, height: 14) } else { Image(systemName: "xmark").frame(width: 14, height: 14) }
                            Text(highlight.localizedName(locale: locale))
                            if zone?.highlightColor == highlight { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: { ToolbarButton(icon: "highlighter", isActive: zone?.highlightColor != HighlightColor.none, tint: .primary, accessibilityLabel: localized("Highlight")) }
            
            ToolbarButton(icon: "list.bullet", isActive: zone?.hasBullet == true, accessibilityLabel: localized("Bullet List")) { content.updateZone(at: path) { $0.hasBullet.toggle() } }
        }
    }
    
    // MARK: - Media Tools
    private var mediaTools: some View {
        HStack(spacing: 8) {
            verticalAlignmentMenu
            sizeModeMenu
            if showsBlockPositionMenu { blockAlignmentMenu }

            Menu {
                Button { content.updateZone(at: path) { $0.imageScale = 0.3 } } label: { HStack { Text(localized("Small")); if zone?.imageScale == 0.3 { Image(systemName: "checkmark") } } }
                Button { content.updateZone(at: path) { $0.imageScale = 0.7 } } label: { HStack { Text(localized("Medium")); if zone?.imageScale == 0.7 { Image(systemName: "checkmark") } } }
                Button { content.updateZone(at: path) { $0.imageScale = 1.0 } } label: { HStack { Text(localized("Full Width")); if zone?.imageScale == 1.0 { Image(systemName: "checkmark") } } }
            } label: { ToolbarButton(icon: "aspectratio", accessibilityLabel: localized("Image Size")) }
        }
    }

    // MARK: - Layout Tools

    private var showsBlockPositionMenu: Bool {
        guard let zone else { return true }
        return zone.sizeMode != .fillWidth
    }

    private var sizeModeMenu: some View {
        Menu {
            Button {
                content.updateZone(at: path) {
                    $0.sizeMode = .auto
                    if $0.blockAlignment == .center {
                        $0.blockAlignment = .auto
                    }
                    $0.fixedWidth = nil
                    $0.fixedHeight = nil
                }
            } label: {
                menuRow(title: localized("Auto Size"), systemImage: "arrow.up.left.and.down.right.magnifyingglass", isSelected: zone?.sizeMode == .auto)
            }

            Button {
                content.updateZone(at: path) {
                    $0.sizeMode = .fillWidth
                    $0.blockAlignment = .leading
                    $0.fixedWidth = nil
                    $0.fixedHeight = nil
                }
            } label: {
                menuRow(title: localized("Fill Width"), systemImage: "arrow.left.and.right", isSelected: zone?.sizeMode == .fillWidth)
            }

            if zone?.sizeMode == .fixed {
                Button { } label: {
                    menuRow(title: localized("Fixed Size"), systemImage: "rectangle.resize", isSelected: true)
                }
                .disabled(true)
            }
        } label: {
            ToolbarButton(icon: sizeModeIcon(for: zone?.sizeMode ?? .auto), accessibilityLabel: localized("Zone Size"))
        }
    }

    private var verticalAlignmentMenu: some View {
        Menu {
            Button {
                content.updateZone(at: .root) { $0.verticalAlignment = .top }
            } label: {
                menuRow(
                    title: localized("Align Top"),
                    systemImage: "align.vertical.top",
                    isSelected: resolvedVerticalAlignment == .top
                )
            }

            Button {
                content.updateZone(at: .root) { $0.verticalAlignment = .center }
            } label: {
                menuRow(
                    title: localized("Align Middle"),
                    systemImage: "align.vertical.center",
                    isSelected: resolvedVerticalAlignment == .center
                )
            }

            Button {
                content.updateZone(at: .root) { $0.verticalAlignment = .bottom }
            } label: {
                menuRow(
                    title: localized("Align Bottom"),
                    systemImage: "align.vertical.bottom",
                    isSelected: resolvedVerticalAlignment == .bottom
                )
            }
        } label: {
            ToolbarButton(
                icon: verticalAlignmentIcon(for: resolvedVerticalAlignment),
                accessibilityLabel: localized("Vertical Position")
            )
        }
    }

    private var blockAlignmentMenu: some View {
        Menu {
            Button {
                content.updateZone(at: path) {
                    $0.sizeMode = .auto
                    $0.blockAlignment = .auto
                    $0.fixedWidth = nil
                    $0.fixedHeight = nil
                }
            } label: {
                menuRow(title: localized("Auto Block"), systemImage: "sparkles", isSelected: isAutoBlockSelected)
            }

            Button {
                content.updateZone(at: path) {
                    if $0.sizeMode == .fillWidth {
                        $0.sizeMode = .auto
                        $0.fixedWidth = nil
                        $0.fixedHeight = nil
                    }
                    $0.blockAlignment = .leading
                }
            } label: {
                menuRow(title: localized("Block Left"), systemImage: "rectangle.leadinghalf.inset.filled", isSelected: zone?.blockAlignment == .leading)
            }

            if zone?.sizeMode == .fixed {
                Button {
                    content.updateZone(at: path) { $0.blockAlignment = .center }
                } label: {
                    menuRow(title: localized("Block Center"), systemImage: "rectangle.center.inset.filled", isSelected: zone?.blockAlignment == .center)
                }
            }

            Button {
                content.updateZone(at: path) {
                    if $0.sizeMode == .fillWidth {
                        $0.sizeMode = .auto
                        $0.fixedWidth = nil
                        $0.fixedHeight = nil
                    }
                    $0.blockAlignment = .trailing
                }
            } label: {
                menuRow(title: localized("Block Right"), systemImage: "rectangle.trailinghalf.inset.filled", isSelected: zone?.blockAlignment == .trailing)
            }
        } label: {
            ToolbarButton(icon: blockAlignmentIcon(for: zone), accessibilityLabel: localized("Block Position"))
        }
    }

    private var textAlignmentMenu: some View {
        Menu {
            Button {
                content.updateZone(at: path) { $0.textAlignment = .leading }
            } label: {
                menuRow(title: localized("Align Left"), systemImage: "text.alignleft", isSelected: zone?.textAlignment == .leading)
            }

            Button {
                content.updateZone(at: path) { $0.textAlignment = .center }
            } label: {
                menuRow(title: localized("Align Center"), systemImage: "text.aligncenter", isSelected: zone?.textAlignment == .center)
            }

            Button {
                content.updateZone(at: path) { $0.textAlignment = .trailing }
            } label: {
                menuRow(title: localized("Align Right"), systemImage: "text.alignright", isSelected: zone?.textAlignment == .trailing)
            }
        } label: {
            ToolbarButton(icon: alignmentIcon(for: zone?.textAlignment ?? .leading), accessibilityLabel: localized("Text Lines"))
        }
    }

    private func menuRow(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if isSelected { Image(systemName: "checkmark") }
        }
    }

    private func sizeModeIcon(for mode: ZoneSizeMode) -> String {
        switch mode {
        case .auto:
            return "arrow.up.left.and.down.right.magnifyingglass"
        case .fillWidth:
            return "arrow.left.and.right"
        case .fixed:
            return "rectangle.resize"
        }
    }

    private var isAutoBlockSelected: Bool {
        guard let zone else { return true }
        return zone.blockAlignment == .auto
            || (zone.sizeMode != .fixed && zone.blockAlignment == .center)
    }

    private func blockAlignmentIcon(for zone: ZoneModel?) -> String {
        let alignment = zone?.blockAlignment ?? .auto
        if zone?.sizeMode != .fixed && alignment == .center {
            return "sparkles"
        }

        switch alignment {
        case .auto:
            return "sparkles"
        case .leading:
            return "rectangle.leadinghalf.inset.filled"
        case .center:
            return "rectangle.center.inset.filled"
        case .trailing:
            return "rectangle.trailinghalf.inset.filled"
        }
    }

    private func alignmentIcon(for alignment: TextBlockAlignment) -> String {
        switch alignment { case .leading: return "text.alignleft"; case .center: return "text.aligncenter"; case .trailing: return "text.alignright" }
    }

    private var resolvedVerticalAlignment: ZoneVerticalAlignment {
        content.rootZone.verticalAlignment.resolved(fallback: .center)
    }

    private func verticalAlignmentIcon(for alignment: ZoneVerticalAlignment) -> String {
        switch alignment {
        case .auto, .center:
            return "align.vertical.center"
        case .top:
            return "align.vertical.top"
        case .bottom:
            return "align.vertical.bottom"
        }
    }
}

// MARK: - Popover Menu Elements

/// Radial hub showing four directional chevrons.
///
/// The active direction bubble scales up and fills with the accent colour,
/// giving clear visual feedback about which zone-add action will fire on release.
struct DirectionPopoverMenu: View {
    let activeDirection: AddDirection?
    let accent: Color
    let arrowRadius: CGFloat

    var body: some View {
        ZStack {
            // Central hub
            Circle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.secondary))
                .scaleEffect(activeDirection != nil ? 0.6 : 1.0)
                .opacity(activeDirection != nil ? 0.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: activeDirection)

            // Directional bubbles
            PopoverBubble(icon: "chevron.up", isActive: activeDirection == .up, accent: accent).offset(y: -arrowRadius)
            PopoverBubble(icon: "chevron.down", isActive: activeDirection == .down, accent: accent).offset(y: arrowRadius)
            PopoverBubble(icon: "chevron.left", isActive: activeDirection == .left, accent: accent).offset(x: -arrowRadius)
            PopoverBubble(icon: "chevron.right", isActive: activeDirection == .right, accent: accent).offset(x: arrowRadius)
        }
        .allowsHitTesting(false)
    }
}

/// A single directional bubble in the radial direction picker.
///
/// Scales up and fills with the accent colour when `isActive` is `true`.
struct PopoverBubble: View {
    let icon: String
    let isActive: Bool
    let accent: Color

    var body: some View {
        Image(systemName: icon)
            .font(.title3.weight(.bold))
            .foregroundStyle(isActive ? .white : .primary)
            .frame(width: isActive ? 52 : 36, height: isActive ? 52 : 36)
            .background(
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    if isActive {
                        Circle()
                            .fill(accent)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.2).combined(with: .opacity),
                                removal: .scale(scale: 0.2).combined(with: .opacity)
                            ))
                    }
                }
            )
            .overlay(Circle().stroke(Color.white.opacity(isActive ? 0 : 0.2), lineWidth: 1))
            .shadow(color: isActive ? accent.opacity(0.5) : .black.opacity(0.1), radius: isActive ? 12 : 5, y: isActive ? 6 : 2)
            .opacity(isActive ? 1.0 : 0.7)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isActive)
    }
}

// MARK: - Toolbar Button

struct ToolbarButton: View {
    let icon: String
    var isActive: Bool = false
    var tint: Color = .primary
    var isEnabled: Bool = true
    var accessibilityLabel: String?
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button { action?() } label: {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(isActive ? ThemeManager.shared.accentColor.color : tint)
                .frame(width: 32, height: 32)
                .background(isActive ? ThemeManager.shared.accentColor.color.opacity(0.12) : Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(accessibilityLabel ?? icon)
    }
}
