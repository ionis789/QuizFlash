//
//  EditorFormatMenuBar.swift
//  QuizFlash
//
//  Format bar providing text/media formatting controls.
//

import SwiftUI

// MARK: - Editor Format Menu Bar

/// The persistent formatting toolbar shown near the top of the card editor.
///
/// Contains:
/// - Text formatting controls (style, weight, alignment, colour, highlight, bullet)
/// - Media controls when the selected zone contains an image or sketch
/// - A "Done" button to dismiss the bar
struct EditorFormatMenuBar: View {
    @Environment(AppPreferences.self) private var appPreferences

    let content: ZoneCardContent
    let path: ZonePath

    var onChoosePhoto: () -> Void
    var onSketch: () -> Void
    var canPreview: Bool
    var onPreview: () -> Void
    var onClose: () -> Void

    init(
        content: ZoneCardContent,
        path: ZonePath,
        onChoosePhoto: @escaping () -> Void,
        onSketch: @escaping () -> Void,
        canPreview: Bool,
        onPreview: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.content = content
        self.path = path
        self.onChoosePhoto = onChoosePhoto
        self.onSketch = onSketch
        self.canPreview = canPreview
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

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    cardActionTools
                    
                    if showsTextTools { textTools }
                    else if showsMediaTools { mediaTools }
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
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

    // MARK: - Text Tools
    private var textTools: some View {
        HStack(spacing: 8) {
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
            Menu {
                Button { content.updateZone(at: path) { $0.imageScale = 0.3 } } label: { HStack { Text(localized("Small")); if zone?.imageScale == 0.3 { Image(systemName: "checkmark") } } }
                Button { content.updateZone(at: path) { $0.imageScale = 0.7 } } label: { HStack { Text(localized("Medium")); if zone?.imageScale == 0.7 { Image(systemName: "checkmark") } } }
                Button { content.updateZone(at: path) { $0.imageScale = 1.0 } } label: { HStack { Text(localized("Full Width")); if zone?.imageScale == 1.0 { Image(systemName: "checkmark") } } }
            } label: { ToolbarButton(icon: "aspectratio", accessibilityLabel: localized("Image Size")) }
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

    private func alignmentIcon(for alignment: TextBlockAlignment) -> String {
        switch alignment { case .leading: return "text.alignleft"; case .center: return "text.aligncenter"; case .trailing: return "text.alignright" }
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
            verticalAlignmentMenu
            sizeModeMenu
            if showsBlockPositionMenu { blockAlignmentMenu }

            Divider()

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
            menuRow(title: localized("Zone Size"), systemImage: sizeModeIcon(for: zone?.sizeMode ?? .auto), isSelected: false)
        }
    }

    private var verticalAlignmentMenu: some View {
        Menu {
            Button {
                content.updateZone(at: .root) { $0.verticalAlignment = .top }
            } label: {
                menuRow(title: localized("Align Top"), systemImage: "align.vertical.top", isSelected: resolvedVerticalAlignment == .top)
            }

            Button {
                content.updateZone(at: .root) { $0.verticalAlignment = .center }
            } label: {
                menuRow(title: localized("Align Middle"), systemImage: "align.vertical.center", isSelected: resolvedVerticalAlignment == .center)
            }

            Button {
                content.updateZone(at: .root) { $0.verticalAlignment = .bottom }
            } label: {
                menuRow(title: localized("Align Bottom"), systemImage: "align.vertical.bottom", isSelected: resolvedVerticalAlignment == .bottom)
            }
        } label: {
            menuRow(title: localized("Vertical Position"), systemImage: verticalAlignmentIcon(for: resolvedVerticalAlignment), isSelected: false)
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
