//
//  ZoneFormatBarView.swift
//  QuizFlash
//
//  Format bar with isolated drag gesture handling.
//  Synchronized preview clearing and zone addition for flawless UX.
//  Features: Invisible tracking with fluid Bubble Fill interaction.
//

import SwiftUI

// MARK: - Zone Format Bar

struct EditorFormatMenuBar: View {
    let content: ZoneCardContent
    let path: ZonePath
    
    var onAddZoneAction: (AddDirection) -> Void
    var onPreviewDirection: (AddDirection?) -> Void
    var onSplit: () -> Void
    var onClose: () -> Void
    
    // UI State - Local to this view
    @State private var isDraggingMenu = false
    @State private var activeDirection: AddDirection? = nil
    
    // Geometry Constraints
    private let menuCenter = CGPoint(x: 50, y: -90)
    private let arrowRadius: CGFloat = 44           // Mai strâns pentru un look compact
    private let captureRadius: CGFloat = 20         // Raza minimă de la centru pentru a selecta o direcție
    
    init(
        content: ZoneCardContent,
        path: ZonePath,
        onAddZoneAction: @escaping (AddDirection) -> Void,
        onPreviewDirection: @escaping (AddDirection?) -> Void,
        onSplit: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.content = content
        self.path = path
        self.onAddZoneAction = onAddZoneAction
        self.onPreviewDirection = onPreviewDirection
        self.onSplit = onSplit
        self.onClose = onClose
    }
    
    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var zoneController = ZoneController.shared
    private var lineTracker = ZoneLineTracker.shared
    
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
                    if canSplit { ToolbarButton(icon: "rectangle.split.1x2") { onSplit() } }
                    
                    if zone?.contentType == .text || zone?.contentType == .empty { textTools }
                    else if zone?.contentType == .image || zone?.contentType == .sketch { mediaTools }
                    
                    ToolbarButton(icon: "trash", tint: .red) { content.deleteZone(at: path); onClose() }
                }
                .padding(.horizontal, 8)
            }
            
            Divider().frame(height: 28)
            
            Button { onClose() } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(accent, in: Capsule())
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 10)
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
                    // Hub-ul cu bule (Fără cursor)
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
    
    // MARK: - Drag Handling (Invisible Gesture Tracking)
    
    private func handleDragChange(_ value: DragGesture.Value) {
        if !isDraggingMenu {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isDraggingMenu = true
            }
        }
        
        // Multiplicator pentru a nu fi nevoit să tragi degetul prea mult
        let dx = value.translation.width * 1.3
        let dy = value.translation.height * 1.3
        let distToCenter = hypot(dx, dy)
        
        // Determinăm pe ce direcție se află degetul
        var newDir: AddDirection? = nil
        if distToCenter > captureRadius {
            let angle = atan2(dy, dx)
            let pi = CGFloat.pi
            if angle > -pi/4 && angle <= pi/4 { newDir = .right }
            else if angle > pi/4 && angle <= 3*pi/4 { newDir = .down }
            else if angle > -3*pi/4 && angle <= -pi/4 { newDir = .up }
            else { newDir = .left }
        }
        
        // Declanșăm starea DOAR dacă traversăm dintr-o zonă în alta
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
            Menu {
                ForEach([TextBlockStyle.title, .headline, .body, .caption], id: \.self) { style in
                    Button { content.updateZone(at: path) { $0.textStyle = style } } label: { HStack { Text(style.rawValue.capitalized); if zone?.textStyle == style { Image(systemName: "checkmark") } } }
                }
            } label: { ToolbarButton(icon: "textformat.size") }
            
            ToolbarButton(icon: "bold", isActive: zone?.isBold == true) { content.updateZone(at: path) { $0.isBold.toggle() } }
            ToolbarButton(icon: "italic", isActive: zone?.isItalic == true) { content.updateZone(at: path) { $0.isItalic.toggle() } }
            
            Menu {
                ForEach(FontFamily.allCases, id: \.self) { family in
                    Button { content.updateZone(at: path) { $0.fontFamily = family } } label: { HStack { Image(systemName: family.icon); Text(family.name); if zone?.fontFamily == family { Image(systemName: "checkmark") } } }
                }
            } label: { ToolbarButton(icon: zone?.fontFamily.icon ?? "textformat") }
            
            Menu {
                Button { content.updateZone(at: path) { $0.textAlignment = .leading } } label: { Label("Left", systemImage: "text.alignleft") }
                Button { content.updateZone(at: path) { $0.textAlignment = .center } } label: { Label("Center", systemImage: "text.aligncenter") }
                Button { content.updateZone(at: path) { $0.textAlignment = .trailing } } label: { Label("Right", systemImage: "text.alignright") }
            } label: { ToolbarButton(icon: "text.alignleft") }
            
            Menu {
                ForEach(TextBlockColor.allCases, id: \.self) { color in
                    Button { content.updateZone(at: path) { $0.textColor = color } } label: { HStack { Circle().fill(color.color).frame(width: 14, height: 14); Text(color.name) } }
                }
            } label: { ToolbarButton(icon: "paintpalette", tint: zone?.textColor.color ?? .primary) }
            
            Menu {
                ForEach(HighlightColor.allCases, id: \.self) { highlight in
                    Button { content.updateZone(at: path) { $0.highlightColor = highlight } } label: {
                        HStack {
                            if highlight != .none { RoundedRectangle(cornerRadius: 2).fill(highlight.color ?? .clear).frame(width: 14, height: 14) } else { Image(systemName: "xmark").frame(width: 14, height: 14) }
                            Text(highlight.name)
                            if zone?.highlightColor == highlight { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: { ToolbarButton(icon: "highlighter", isActive: zone?.highlightColor != HighlightColor.none, tint: .primary) }
            
            ToolbarButton(icon: "list.bullet", isActive: zone?.hasBullet == true) { content.updateZone(at: path) { $0.hasBullet.toggle() } }
        }
    }
    
    // MARK: - Media Tools
    private var mediaTools: some View {
        HStack(spacing: 8) {
            Menu {
                Button { content.updateZone(at: path) { $0.textAlignment = .leading } } label: { HStack { Text("Left"); if zone?.textAlignment == .leading { Image(systemName: "checkmark") } } }
                Button { content.updateZone(at: path) { $0.textAlignment = .center } } label: { HStack { Text("Center"); if zone?.textAlignment == .center { Image(systemName: "checkmark") } } }
                Button { content.updateZone(at: path) { $0.textAlignment = .trailing } } label: { HStack { Text("Right"); if zone?.textAlignment == .trailing { Image(systemName: "checkmark") } } }
            } label: { ToolbarButton(icon: alignmentIcon(for: zone?.textAlignment ?? .leading)) }
            
            Menu {
                Button { content.updateZone(at: path) { $0.imageScale = 0.3 } } label: { HStack { Text("Small"); if zone?.imageScale == 0.3 { Image(systemName: "checkmark") } } }
                Button { content.updateZone(at: path) { $0.imageScale = 0.7 } } label: { HStack { Text("Medium"); if zone?.imageScale == 0.7 { Image(systemName: "checkmark") } } }
                Button { content.updateZone(at: path) { $0.imageScale = 1.0 } } label: { HStack { Text("Full Width"); if zone?.imageScale == 1.0 { Image(systemName: "checkmark") } } }
            } label: { ToolbarButton(icon: "aspectratio") }
        }
    }
    
    private func alignmentIcon(for alignment: TextBlockAlignment) -> String {
        switch alignment { case .leading: return "text.alignleft"; case .center: return "text.aligncenter"; case .trailing: return "text.alignright" }
    }
}

// MARK: - Popover Menu Elements

struct DirectionPopoverMenu: View {
    let activeDirection: AddDirection?
    let accent: Color
    let arrowRadius: CGFloat
    
    var body: some View {
        ZStack {
            // Central Hub
            Circle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.secondary))
                .scaleEffect(activeDirection != nil ? 0.6 : 1.0)
                .opacity(activeDirection != nil ? 0.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: activeDirection)
            
            // Nodes (Chevrons)
            PopoverBubble(icon: "chevron.up", isActive: activeDirection == .up, accent: accent).offset(y: -arrowRadius)
            PopoverBubble(icon: "chevron.down", isActive: activeDirection == .down, accent: accent).offset(y: arrowRadius)
            PopoverBubble(icon: "chevron.left", isActive: activeDirection == .left, accent: accent).offset(x: -arrowRadius)
            PopoverBubble(icon: "chevron.right", isActive: activeDirection == .right, accent: accent).offset(x: arrowRadius)
        }
        .allowsHitTesting(false)
    }
}

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
                    // EFECTUL DE UMPLERE: Apare din centru
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
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button { action?() } label: {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(isActive ? ThemeManager.shared.accentColor.color : tint)
                .frame(width: 34, height: 34)
                .background(isActive ? ThemeManager.shared.accentColor.color.opacity(0.12) : Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
