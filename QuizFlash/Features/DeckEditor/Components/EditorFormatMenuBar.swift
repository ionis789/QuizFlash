//
//  EditorFormatMenuBar.swift
//  QuizFlash
//
//  Format bar providing text/media formatting controls.
//

import SwiftUI

// MARK: - Editor Format Menu Bar

struct EditorFormatMenuBar: View {
    @Environment(AppPreferences.self) private var appPreferences
    @State private var toolMode: ToolMode = .format

    let content: ZoneCardContent
    let path: ZonePath

    var onChoosePhoto: () -> Void
    var onSketch: () -> Void
    var onSetAutoSize: () -> Void
    var onSetFillWidth: () -> Void
    var onSetBlockAlignment: (ZoneBlockAlignment) -> Void
    var onDuplicateZone: () -> Void
    var onDeleteZone: () -> Void
    var canPreview: Bool
    var showsPrimaryActions: Bool
    var showsZoneActions: Bool
    var showsPreviewAction: Bool
    var showsMoreActions: Bool
    var onPreview: () -> Void
    var onClose: () -> Void

    private enum ToolMode {
        case format
        case zoneActions
    }

    init(
        content: ZoneCardContent,
        path: ZonePath,
        onChoosePhoto: @escaping () -> Void,
        onSketch: @escaping () -> Void,
        onSetAutoSize: @escaping () -> Void = { },
        onSetFillWidth: @escaping () -> Void = { },
        onSetBlockAlignment: @escaping (ZoneBlockAlignment) -> Void = { _ in },
        onDuplicateZone: @escaping () -> Void = { },
        onDeleteZone: @escaping () -> Void = { },
        canPreview: Bool,
        showsPrimaryActions: Bool = true,
        showsZoneActions: Bool = false,
        showsPreviewAction: Bool = true,
        showsMoreActions: Bool = true,
        onPreview: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.content = content
        self.path = path
        self.onChoosePhoto = onChoosePhoto
        self.onSketch = onSketch
        self.onSetAutoSize = onSetAutoSize
        self.onSetFillWidth = onSetFillWidth
        self.onSetBlockAlignment = onSetBlockAlignment
        self.onDuplicateZone = onDuplicateZone
        self.onDeleteZone = onDeleteZone
        self.canPreview = canPreview
        self.showsPrimaryActions = showsPrimaryActions
        self.showsZoneActions = showsZoneActions
        self.showsPreviewAction = showsPreviewAction
        self.showsMoreActions = showsMoreActions
        self.onPreview = onPreview
        self.onClose = onClose
    }

    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var locale: Locale { appPreferences.resolvedLocale }
    private var showsTextTools: Bool {
        guard let zone, zone.isLeaf else { return false }
        return zone.contentType == .text || zone.contentType == .empty || zone.contentType == .code
    }
    private var showsMediaTools: Bool {
        guard let zone, zone.isLeaf else { return false }
        return zone.contentType == .image || zone.contentType == .sketch
    }
    private var showsTrailingZoneControls: Bool {
        showsZoneActions && (showsPreviewAction || showsMoreActions)
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                activeTools
                .padding(.leading, 16)
                .padding(.trailing, 10)
            }
            
            if showsTrailingZoneControls {
                Divider()
                    .frame(height: 26)

                if showsPreviewAction {
                    previewButton
                }

                if showsMoreActions {
                    modeToggleButton
                }

                Divider()
                    .frame(height: 26)
            } else {
                Divider()
                    .frame(height: 26)
            }
            
            Button { onClose() } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 36)
                    .contentShape(Rectangle())
            }
            .padding(.trailing, 10)
            .accessibilityLabel(localized("Hide Keyboard"))
        }
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .animation(.tabItemSpring, value: toolMode)
        .onChange(of: path) { _, _ in
            toolMode = .format
        }
    }

    @ViewBuilder
    private var activeTools: some View {
        HStack(spacing: 20) {
            if toolMode == .zoneActions, showsZoneActions, showsMoreActions {
                zoneActionTools
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                if showsPrimaryActions {
                    cardActionTools
                }

                if showsTextTools {
                    textTools
                } else if showsMediaTools {
                    mediaTools
                }
            }
        }
        .id(toolMode)
    }

    private var modeToggleButton: some View {
        Button {
            withAnimation(.tabItemSpring) {
                toolMode = toolMode == .format ? .zoneActions : .format
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(toolMode == .zoneActions ? Color.black.opacity(0.78) : accent)
                .frame(width: 42, height: 36)
                .background {
                    if toolMode == .zoneActions {
                        Capsule(style: .continuous)
                            .fill(accent)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("More Options"))
        .accessibilityAddTraits(toolMode == .zoneActions ? .isSelected : [])
    }

    private var previewButton: some View {
        Button(action: onPreview) {
            Image(systemName: "eye")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(canPreview ? accent : Color.secondary)
                .frame(width: 42, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canPreview)
        .opacity(canPreview ? 1 : 0.45)
        .accessibilityLabel(localized("Preview"))
    }

    private var cardActionTools: some View {
        HStack(spacing: 16) {
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

    // MARK: - Zone Actions
    private var zoneActionTools: some View {
        HStack(spacing: 16) {
            zoneSizeMenu
            blockPositionMenu
            zoneContentMenu
            zoneOperationsMenu
        }
    }

    private var zoneSizeMenu: some View {
        Menu {
            Button(action: onSetAutoSize) {
                menuRow(
                    title: localized("Auto Size"),
                    systemImage: "arrow.up.left.and.down.right.magnifyingglass",
                    isSelected: zone?.sizeMode == .auto
                )
            }

            Button(action: onSetFillWidth) {
                menuRow(
                    title: localized("Fill Width"),
                    systemImage: "arrow.left.and.right",
                    isSelected: zone?.sizeMode == .fillWidth
                )
            }

            if zone?.sizeMode == .fixed {
                Button { } label: {
                    menuRow(
                        title: localized("Fixed Size"),
                        systemImage: "rectangle.resize",
                        isSelected: true
                    )
                }
                .disabled(true)
            }
        } label: {
            ToolbarIconLabel(
                icon: sizeModeIcon(for: zone?.sizeMode ?? .auto),
                isActive: zone?.sizeMode != .auto,
                accessibilityLabel: localized("Zone Size")
            )
        }
    }

    private var blockPositionMenu: some View {
        Menu {
            Button {
                onSetBlockAlignment(.leading)
            } label: {
                menuRow(
                    title: localized("Block Left"),
                    systemImage: "rectangle.leadinghalf.inset.filled",
                    isSelected: zone?.blockAlignment == .leading
                )
            }

            Button {
                onSetBlockAlignment(.center)
            } label: {
                menuRow(
                    title: localized("Block Center"),
                    systemImage: "rectangle.center.inset.filled",
                    isSelected: zone?.blockAlignment == .center
                )
            }

            Button {
                onSetBlockAlignment(.trailing)
            } label: {
                menuRow(
                    title: localized("Block Right"),
                    systemImage: "rectangle.trailinghalf.inset.filled",
                    isSelected: zone?.blockAlignment == .trailing
                )
            }
        } label: {
            ToolbarIconLabel(
                icon: blockAlignmentIcon(for: zone),
                isActive: zone?.blockAlignment != .auto,
                accessibilityLabel: localized("Block Position")
            )
        }
    }

    private var zoneContentMenu: some View {
        Menu {
            Button(action: onChoosePhoto) {
                Label(localized("Choose Photos"), systemImage: "photo.on.rectangle")
            }

            Button(action: onSketch) {
                Label(localized("Sketch"), systemImage: "pencil.and.scribble")
            }
        } label: {
            ToolbarIconLabel(
                icon: "plus.rectangle.on.rectangle",
                accessibilityLabel: localized("Choose Photos")
            )
        }
    }

    private var zoneOperationsMenu: some View {
        Menu {
            Button(action: onDuplicateZone) {
                Label(localized("Duplicate"), systemImage: "doc.on.doc")
            }

            Button(role: .destructive, action: onDeleteZone) {
                Label(localized("Delete"), systemImage: "trash")
            }
        } label: {
            ToolbarIconLabel(
                icon: "ellipsis.circle",
                accessibilityLabel: localized("More Options")
            )
        }
    }

    // MARK: - Text Tools
    private var textTools: some View {
        HStack(spacing: 16) {
            paragraphMenu
            typographyMenu
            textColorMenu
            backgroundColorMenu
        }
    }

    private var paragraphMenu: some View {
        Menu {
            Section {
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
            }

            Section {
                Button {
                    content.updateZone(at: path) { $0.hasBullet.toggle() }
                } label: {
                    menuRow(title: localized("Bullet List"), systemImage: "list.bullet", isSelected: zone?.hasBullet == true)
                }
            }
        } label: {
            ToolbarIconLabel(
                icon: paragraphMenuIcon,
                isActive: isParagraphMenuActive,
                accessibilityLabel: localized("Text Lines")
            )
        }
    }

    private var typographyMenu: some View {
        Menu {
            Section {
                ForEach([TextBlockStyle.title, .headline, .body, .caption], id: \.self) { style in
                    Button {
                        content.updateZone(at: path) { $0.textStyle = style }
                    } label: {
                        menuRow(
                            title: style.localizedName(locale: locale),
                            systemImage: textStyleIcon(for: style),
                            isSelected: zone?.textStyle == style
                        )
                    }
                }
            }

            Section {
                ForEach(FontFamily.allCases, id: \.self) { family in
                    Button {
                        content.updateZone(at: path) { $0.fontFamily = family }
                    } label: {
                        menuRow(
                            title: family.localizedName(locale: locale),
                            systemImage: family.icon,
                            isSelected: zone?.fontFamily == family
                        )
                    }
                }
            }

            Section {
                Button {
                    content.updateZone(at: path) { $0.isBold.toggle() }
                } label: {
                    menuRow(title: localized("Bold"), systemImage: "bold", isSelected: zone?.isBold == true)
                }

                Button {
                    content.updateZone(at: path) { $0.isItalic.toggle() }
                } label: {
                    menuRow(title: localized("Italic"), systemImage: "italic", isSelected: zone?.isItalic == true)
                }
            }
        } label: {
            ToolbarIconLabel(
                icon: typographyMenuIcon,
                isActive: isTypographyMenuActive,
                accessibilityLabel: localized("Font")
            )
        }
    }

    private var textColorMenu: some View {
        Menu {
            ForEach(TextBlockColor.allCases, id: \.self) { color in
                Button {
                    content.updateZone(at: path) { $0.textColor = color }
                } label: {
                    colorMenuRow(
                        title: color.localizedName(locale: locale),
                        color: color.color,
                        isSelected: zone?.textColor == color
                    )
                }
            }
        } label: {
            ToolbarIconLabel(
                icon: "paintbrush.pointed",
                isActive: zone?.textColor != .primary,
                tint: zone?.textColor.color ?? .primary,
                accessibilityLabel: localized("Text Color")
            )
        }
    }

    private var backgroundColorMenu: some View {
        Menu {
            ForEach(HighlightColor.allCases, id: \.self) { highlight in
                Button {
                    content.updateZone(at: path) { $0.highlightColor = highlight }
                } label: {
                    highlightMenuRow(
                        title: highlight.localizedName(locale: locale),
                        highlight: highlight,
                        isSelected: zone?.highlightColor == highlight
                    )
                }
            }
        } label: {
            ToolbarIconLabel(
                icon: "rectangle",
                tint: zone?.highlightColor.zoneSurfaceTint ?? .white,
                accessibilityLabel: localized("Background Color")
            )
        }
    }
    
    // MARK: - Media Tools
    private var mediaTools: some View {
        HStack(spacing: 12) {
            Image(systemName: "aspectratio")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 34)

            Slider(
                value: imageScaleBinding,
                in: 0.2...1.0,
                step: 0.01
            )
            .tint(accent)
            .frame(width: 136)
            .accessibilityLabel(localized("Image Size"))

            Text("\(Int(((zone?.imageScale ?? 1.0) * 100).rounded()))%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private var imageScaleBinding: Binding<Double> {
        Binding(
            get: {
                Double(zone?.imageScale ?? 1.0)
            },
            set: { value in
                content.updateZone(at: path) {
                    $0.imageScale = CGFloat(value)
                    $0.sizeMode = .auto
                    $0.fixedWidth = nil
                    $0.fixedHeight = nil
                }
            }
        )
    }

    private func menuRow(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if isSelected { Image(systemName: "checkmark") }
        }
    }

    private func colorMenuRow(title: String, color: Color, isSelected: Bool) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
            Text(title)
            if isSelected { Image(systemName: "checkmark") }
        }
    }

    private func highlightMenuRow(title: String, highlight: HighlightColor, isSelected: Bool) -> some View {
        HStack {
            if let color = highlight.color {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "xmark")
                    .frame(width: 14, height: 14)
            }
            Text(title)
            if isSelected { Image(systemName: "checkmark") }
        }
    }

    private var paragraphMenuIcon: String {
        if zone?.hasBullet == true { return "list.bullet" }
        switch zone?.textAlignment ?? .leading {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }

    private var typographyMenuIcon: String {
        if zone?.isBold == true { return "bold" }
        if zone?.isItalic == true { return "italic" }
        return zone?.fontFamily.icon ?? "textformat"
    }

    private var isParagraphMenuActive: Bool {
        zone?.hasBullet == true || zone?.textAlignment != .leading
    }

    private var isTypographyMenuActive: Bool {
        zone?.isBold == true
            || zone?.isItalic == true
            || zone?.textStyle != .body
            || zone?.fontFamily != .system
    }

    private func textStyleIcon(for style: TextBlockStyle) -> String {
        switch style {
        case .title: return "textformat.size"
        case .headline: return "textformat.size"
        case .body: return "textformat"
        case .caption: return "textformat"
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

    private func blockAlignmentIcon(for zone: ZoneModel?) -> String {
        switch zone?.blockAlignment ?? .auto {
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
}

// MARK: - Zone Management Floating Button

/// Focus-scoped zone menu for operations that affect the selected zone's
/// rectangle, order, duplication, or removal.
struct ZoneManagementFloatingButton: View {
    @Environment(AppPreferences.self) private var appPreferences

    let content: ZoneCardContent
    let path: ZonePath
    var onSplit: () -> Void
    var onDuplicate: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onClose: () -> Void

    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var zoneController = ZoneController.shared
    private var lineTracker = ZoneLineTracker.shared
    private var locale: Locale { appPreferences.resolvedLocale }

    init(
        content: ZoneCardContent,
        path: ZonePath,
        onSplit: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.content = content
        self.path = path
        self.onSplit = onSplit
        self.onDuplicate = onDuplicate
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onClose = onClose
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private var canSplit: Bool {
        guard let zone,
              zone.contentType == .text
        else { return false }

        if let heightInfo = zoneController.zoneHeightInfo(for: zone.id) {
            return heightInfo.canSplit
        }
        return lineTracker.canSplitZone(zoneID: zone.id)
    }

    var body: some View {
        Menu {
            Section {
                sizeModeMenu
            }

            if showsBlockPositionMenu {
                Section {
                    blockAlignmentMenu
                }
            }

            Section {
                if canSplit {
                    Button(action: onSplit) {
                        Label(localized("Split Zone"), systemImage: "rectangle.split.1x2")
                    }
                }

                Button(action: onMoveUp) {
                    Label(localized("Move Up"), systemImage: "arrow.up")
                }
                Button(action: onMoveDown) {
                    Label(localized("Move Down"), systemImage: "arrow.down")
                }
                Button(action: onDuplicate) {
                    Label(localized("Duplicate"), systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    content.deleteZone(at: path)
                    onClose()
                } label: {
                    Label(localized("Delete"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(accent, in: Circle())
                .shadow(color: accent.opacity(0.32), radius: 12, y: 5)
        }
        .accessibilityLabel(localized("Block Position"))
    }

    private var showsBlockPositionMenu: Bool {
        guard let zone else { return true }
        return zone.sizeMode != .fillWidth
    }

    private var sizeModeMenu: some View {
        Menu {
            Button {
                content.updateZone(at: path) {
                    $0.sizeMode = .auto
                    $0.blockAlignment = .auto
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
            menuRow(title: localized("Zone Size"), systemImage: sizeModeIcon(for: zone?.sizeMode ?? .auto), isSelected: false)
        }
    }

    private var blockAlignmentMenu: some View {
        Menu {
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
            menuRow(title: localized("Block Position"), systemImage: blockAlignmentIcon(for: zone), isSelected: false)
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
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(isActive ? ThemeManager.shared.accentColor.color : tint)
                .frame(width: 30, height: 34)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .accessibilityLabel(accessibilityLabel ?? icon)
    }
}

struct ToolbarIconLabel: View {
    let icon: String
    var isActive: Bool = false
    var tint: Color = .primary
    var accessibilityLabel: String?

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(isActive ? ThemeManager.shared.accentColor.color : tint)
            .frame(width: 30, height: 34)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel ?? icon)
    }
}
