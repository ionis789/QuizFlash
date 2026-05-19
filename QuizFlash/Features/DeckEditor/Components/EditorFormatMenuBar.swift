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

    let content: ZoneCardContent
    let path: ZonePath

    var onChoosePhoto: () -> Void
    var onSketch: () -> Void
    var canPreview: Bool
    var showsPrimaryActions: Bool
    var onPreview: () -> Void
    var onClose: () -> Void

    init(
        content: ZoneCardContent,
        path: ZonePath,
        onChoosePhoto: @escaping () -> Void,
        onSketch: @escaping () -> Void,
        canPreview: Bool,
        showsPrimaryActions: Bool = true,
        onPreview: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.content = content
        self.path = path
        self.onChoosePhoto = onChoosePhoto
        self.onSketch = onSketch
        self.canPreview = canPreview
        self.showsPrimaryActions = showsPrimaryActions
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
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    if showsPrimaryActions {
                        cardActionTools
                    }
                    
                    if showsTextTools { textTools }
                    else if showsMediaTools { mediaTools }
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
            }
            
            Divider()
                .frame(height: 26)
            
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

    // MARK: - Text Tools
    private var textTools: some View {
        HStack(spacing: 16) {
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
