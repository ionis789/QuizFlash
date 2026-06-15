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
    var onInsertForcedLineBreak: () -> Void
    var onDeleteZone: () -> Void
    var canPreview: Bool
    var showsPrimaryActions: Bool
    var showsZoneActions: Bool
    var onPreview: () -> Void
    var onClose: () -> Void

    init(
        content: ZoneCardContent,
        path: ZonePath,
        onChoosePhoto: @escaping () -> Void,
        onSketch: @escaping () -> Void,
        onInsertForcedLineBreak: @escaping () -> Void = { },
        onDeleteZone: @escaping () -> Void = { },
        canPreview: Bool,
        showsPrimaryActions: Bool = true,
        showsZoneActions: Bool = false,
        onPreview: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.content = content
        self.path = path
        self.onChoosePhoto = onChoosePhoto
        self.onSketch = onSketch
        self.onInsertForcedLineBreak = onInsertForcedLineBreak
        self.onDeleteZone = onDeleteZone
        self.canPreview = canPreview
        self.showsPrimaryActions = showsPrimaryActions
        self.showsZoneActions = showsZoneActions
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
                activeTools
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

    @ViewBuilder
    private var activeTools: some View {
        HStack(spacing: 20) {
            if showsPrimaryActions {
                cardActionTools
            }

            if showsTextTools {
                textTools
            } else if showsMediaTools {
                mediaTools
            }

            if showsZoneActions {
                zoneActionTools
            }
        }
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
            zoneContentMenu
            zoneOperationsMenu
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
            forcedLineBreakButton
            paragraphMenu
            typographyMenu
            textColorMenu
            backgroundColorMenu
        }
    }

    private var forcedLineBreakButton: some View {
        ToolbarButton(
            icon: "return",
            tint: accent,
            accessibilityLabel: localized("Force Line Break"),
            action: onInsertForcedLineBreak
        )
    }

    private var paragraphMenu: some View {
        Menu {
            Section {
                Button {
                    content.updateZone(at: path) {
                        $0.blockAlignment = .leading
                        $0.textAlignment = .leading
                    }
                } label: {
                    menuRow(title: localized("Align Left"), systemImage: "text.alignleft", isSelected: effectiveBlockAlignment == .leading)
                }

                Button {
                    content.updateZone(at: path) {
                        $0.blockAlignment = .center
                        $0.textAlignment = .leading
                    }
                } label: {
                    menuRow(title: localized("Align Center"), systemImage: "text.aligncenter", isSelected: effectiveBlockAlignment == .center)
                }

                Button {
                    content.updateZone(at: path) {
                        $0.blockAlignment = .trailing
                        $0.textAlignment = .leading
                    }
                } label: {
                    menuRow(title: localized("Align Right"), systemImage: "text.alignright", isSelected: effectiveBlockAlignment == .trailing)
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
        switch effectiveBlockAlignment {
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
        zone?.hasBullet == true || effectiveBlockAlignment != .leading
    }

    private var effectiveBlockAlignment: TextBlockAlignment {
        switch zone?.blockAlignment ?? .leading {
        case .leading:
            return .leading
        case .auto:
            return content.rootZone.leafCount == 1 ? .center : .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
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

}

// MARK: - Zone Management Floating Button

/// Focus-scoped zone menu for operations that affect the selected zone's
/// rectangle, order, or removal.
struct ZoneManagementFloatingButton: View {
    @Environment(AppPreferences.self) private var appPreferences

    let content: ZoneCardContent
    let path: ZonePath
    var onSplit: () -> Void
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
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.content = content
        self.path = path
        self.onSplit = onSplit
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
        .accessibilityLabel(localized("More Options"))
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
