//
//  ZoneFormatBarView.swift
//  QuizFlash
//

import SwiftUI

// MARK: -UI-only: format bar for zone (add/split/delete, text or media tools).

struct ZoneFormatBar: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    var onAddZone: (AddDirection) -> Void
    var onSplit: () -> Void
    var onClose: () -> Void

    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var canSplit: Bool {
        guard let zone = zone else { return false }
        return zone.contentType == .text && !zone.text.isEmpty && zone.text.components(separatedBy: "\n").count >= 2
    }

    var body: some View {
        HStack(spacing: 0) {
            addZoneMenu.padding(.leading, 12).padding(.trailing, 8)
            Divider().frame(height: 28)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if canSplit { ToolbarButton(icon: "rectangle.split.1x2") { onSplit() } }
                    if zone?.contentType == .text || zone?.contentType == .empty { textTools }
                    else if zone?.contentType == .image || zone?.contentType == .sketch { mediaTools }
                    ToolbarButton(icon: "trash", tint: .red) {
                        content.deleteZone(at: path)
                        onClose()
                    }
                }
                .padding(.horizontal, 8)
            }
            Divider().frame(height: 28)
            Button { onClose() } label: {
                Text("Done").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(accent, in: Capsule())
            }
            .padding(.leading, 8).padding(.trailing, 12)
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var addZoneMenu: some View {
        Menu {
            Section("Horizontal") {
                Button { onAddZone(.left) } label: { Label("Left", systemImage: "arrow.left") }
                Button { onAddZone(.right) } label: { Label("Right", systemImage: "arrow.right") }
            }
            Section("Vertical") {
                Button { onAddZone(.up) } label: { Label("Above", systemImage: "arrow.up") }
                Button { onAddZone(.down) } label: { Label("Below", systemImage: "arrow.down") }
            }
        } label: {
            Image(systemName: "plus.square.dashed")
                .font(.body.weight(.medium)).foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var textTools: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach([TextBlockStyle.title, .headline, .body, .caption], id: \.self) { style in
                    Button { content.updateZone(at: path) { $0.textStyle = style } } label: {
                        HStack { Text(style.rawValue.capitalized); if zone?.textStyle == style { Image(systemName: "checkmark") } }
                    }
                }
            } label: { ToolbarButton(icon: "textformat.size") }

            ToolbarButton(icon: "bold", isActive: zone?.isBold == true) { content.updateZone(at: path) { $0.isBold.toggle() } }
            ToolbarButton(icon: "italic", isActive: zone?.isItalic == true) { content.updateZone(at: path) { $0.isItalic.toggle() } }

            Menu {
                ForEach(FontFamily.allCases, id: \.self) { family in
                    Button { content.updateZone(at: path) { $0.fontFamily = family } } label: {
                        HStack {
                            Image(systemName: family.icon)
                            Text(family.name)
                            if zone?.fontFamily == family { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: { ToolbarButton(icon: zone?.fontFamily.icon ?? "textformat") }

            Menu {
                Button { content.updateZone(at: path) { $0.textAlignment = .leading } } label: { Label("Left", systemImage: "text.alignleft") }
                Button { content.updateZone(at: path) { $0.textAlignment = .center } } label: { Label("Center", systemImage: "text.aligncenter") }
                Button { content.updateZone(at: path) { $0.textAlignment = .trailing } } label: { Label("Right", systemImage: "text.alignright") }
            } label: { ToolbarButton(icon: "text.alignleft") }

            Menu {
                ForEach(TextBlockColor.allCases, id: \.self) { color in
                    Button { content.updateZone(at: path) { $0.textColor = color } } label: {
                        HStack { Circle().fill(color.color).frame(width: 14, height: 14); Text(color.name) }
                    }
                }
            } label: { ToolbarButton(icon: "paintpalette", tint: zone?.textColor.color ?? .primary) }

            Menu {
                ForEach(HighlightColor.allCases, id: \.self) { highlight in
                    Button { content.updateZone(at: path) { $0.highlightColor = highlight } } label: {
                        HStack {
                            if highlight != .none {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(highlight.color ?? .clear)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "xmark")
                                    .frame(width: 14, height: 14)
                            }
                            Text(highlight.name)
                            if zone?.highlightColor == highlight { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                ToolbarButton(
                    icon: "highlighter",
                    isActive: zone?.highlightColor != HighlightColor.none,
                    tint: zone?.highlightColor.color != nil ? .primary : .primary
                )
            }

            ToolbarButton(icon: "list.bullet", isActive: zone?.hasBullet == true) { content.updateZone(at: path) { $0.hasBullet.toggle() } }
        }
    }

    private var mediaTools: some View {
        HStack(spacing: 8) {
            Menu {
                Button { content.updateZone(at: path) { $0.textAlignment = .leading } } label: {
                    HStack { Text("Left"); if zone?.textAlignment == .leading { Image(systemName: "checkmark") } }
                }
                Button { content.updateZone(at: path) { $0.textAlignment = .center } } label: {
                    HStack { Text("Center"); if zone?.textAlignment == .center { Image(systemName: "checkmark") } }
                }
                Button { content.updateZone(at: path) { $0.textAlignment = .trailing } } label: {
                    HStack { Text("Right"); if zone?.textAlignment == .trailing { Image(systemName: "checkmark") } }
                }
            } label: { ToolbarButton(icon: alignmentIcon(for: zone?.textAlignment ?? .leading)) }

            Menu {
                Button { content.updateZone(at: path) { $0.imageScale = 0.3 } } label: {
                    HStack { Text("Small"); if zone?.imageScale == 0.3 { Image(systemName: "checkmark") } }
                }
                Button { content.updateZone(at: path) { $0.imageScale = 0.7 } } label: {
                    HStack { Text("Medium"); if zone?.imageScale == 0.7 { Image(systemName: "checkmark") } }
                }
                Button { content.updateZone(at: path) { $0.imageScale = 1.0 } } label: {
                    HStack { Text("Full Width"); if zone?.imageScale == 1.0 { Image(systemName: "checkmark") } }
                }
            } label: { ToolbarButton(icon: "aspectratio") }
        }
    }

    private func alignmentIcon(for alignment: TextBlockAlignment) -> String {
        switch alignment {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }
}

// MARK: - Toolbar Button

struct ToolbarButton: View {
    let icon: String
    var isActive: Bool = false
    var tint: Color = .primary
    var action: (() -> Void)? = nil
    var body: some View {
        Button { action?() } label: {
            Image(systemName: icon).font(.body.weight(.medium))
                .foregroundStyle(isActive ? ThemeManager.shared.accentColor.color : tint)
                .frame(width: 34, height: 34)
                .background(isActive ? ThemeManager.shared.accentColor.color.opacity(0.12) : Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
