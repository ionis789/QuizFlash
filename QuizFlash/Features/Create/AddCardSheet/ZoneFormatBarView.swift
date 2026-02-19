//
//  ZoneFormatBarView.swift
//  QuizFlash
//
//  Format bar with isolated drag gesture handling.
//  Synchronized preview clearing and zone addition for flawless UX.
//

import SwiftUI

// MARK: - Zone Format Bar

struct ZoneFormatBar: View {
    let content: ZoneCardContent
    let path: ZonePath
    
    var onAddZoneAction: (AddDirection) -> Void
    var onPreviewDirection: (AddDirection?) -> Void
    var onSplit: () -> Void
    var onClose: () -> Void
    
    // UI State - Local to this view, doesn't trigger parent redraws
    @State private var isDraggingMenu = false
    @State private var activeDirection: AddDirection? = nil
    
    // Virtual Cursor Tracking - Internal state only
    @State private var cursorPosition: CGPoint = CGPoint(x: 50, y: -80)
    
    // Geometry Constraints
    private let menuCenter = CGPoint(x: 50, y: -80)
    private let arrowRadius: CGFloat = 55
    private let captureRadius: CGFloat = 25
    private let cursorMaxRadius: CGFloat = 75
    
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
            // Radial Drag Menu Button
            dragMenuButton
                .padding(.leading, 12)
                .padding(.trailing, 8)
            
            Divider().frame(height: 28)
            
            // Horizontal scrollable tools
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if canSplit {
                        ToolbarButton(icon: "rectangle.split.1x2") { onSplit() }
                    }
                    
                    if zone?.contentType == .text || zone?.contentType == .empty {
                        textTools
                    } else if zone?.contentType == .image || zone?.contentType == .sketch {
                        mediaTools
                    }
                    
                    ToolbarButton(icon: "trash", tint: .red) {
                        content.deleteZone(at: path)
                        onClose()
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Divider().frame(height: 28)
            
            // Done button
            Button {
                onClose()
            } label: {
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
        Image(systemName: isDraggingMenu ? "plus.square.fill" : "plus.square.dashed")
            .font(.body.weight(.medium))
            .foregroundStyle(isDraggingMenu ? .white : accent)
            .frame(width: 34, height: 34)
            .background(
                isDraggingMenu ? accent : accent.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                if isDraggingMenu {
                    ZStack {
                        // Radial popover menu
                        DirectionPopoverMenu(
                            activeDirection: activeDirection,
                            accent: accent,
                            arrowRadius: arrowRadius
                        )
                        .offset(x: menuCenter.x, y: menuCenter.y)
                        .zIndex(1)
                        
                        // Free-moving virtual cursor
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().fill(Color.white.opacity(0.95)))
                            .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 1))
                            .frame(width: 34, height: 34)
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                            .offset(x: cursorPosition.x, y: cursorPosition.y)
                            .zIndex(2)
                    }
                    .transition(.scale(scale: 0.1, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChange(value)
                    }
                    .onEnded { value in
                        handleDragEnd(value)
                    }
            )
    }
    
    // MARK: - Drag Handling (Isolated & Synchronized)
    
    private func handleDragChange(_ value: DragGesture.Value) {
        if !isDraggingMenu {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            cursorPosition = menuCenter
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isDraggingMenu = true
            }
        }
        
        let dx = value.translation.width * 1.3
        let dy = value.translation.height * 1.3
        
        let rawCursor = CGPoint(x: menuCenter.x + dx, y: menuCenter.y + dy)
        let distToCenter = hypot(dx, dy)
        var finalCursor = rawCursor
        
        if distToCenter > cursorMaxRadius {
            finalCursor.x = menuCenter.x + (dx / distToCenter) * cursorMaxRadius
            finalCursor.y = menuCenter.y + (dy / distToCenter) * cursorMaxRadius
        }
        
        withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.8)) {
            cursorPosition = finalCursor
        }
        
        let prevDir = activeDirection
        var newDir: AddDirection? = nil
        
        if distToCenter > captureRadius {
            let angle = atan2(dy, dx)
            let pi = CGFloat.pi
            
            if angle > -pi/4 && angle <= pi/4 { newDir = .right }
            else if angle > pi/4 && angle <= 3*pi/4 { newDir = .down }
            else if angle > -3*pi/4 && angle <= -pi/4 { newDir = .up }
            else { newDir = .left }
        }
        
        // Notify ONLY on direction change
        if newDir != prevDir {
            activeDirection = newDir
            
            if newDir != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            } else {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
            onPreviewDirection(activeDirection)
        }
    }
    
    private func handleDragEnd(_ value: DragGesture.Value) {
        let finalDir = activeDirection
        
        // Use identical spring values as AddCardSheetView to morph layout seamlessly
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isDraggingMenu = false
            activeDirection = nil
            cursorPosition = menuCenter
            
            // Clear preview inside the same transaction
            onPreviewDirection(nil)
        }
        
        // Trigger actual addition immediately so the ghost swaps with the real zone flawlessly
        if let dir = finalDir {
            onAddZoneAction(dir)
        }
    }
    
    // MARK: - Text Tools
    
    private var textTools: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach([TextBlockStyle.title, .headline, .body, .caption], id: \.self) { style in
                    Button {
                        content.updateZone(at: path) { $0.textStyle = style }
                    } label: {
                        HStack {
                            Text(style.rawValue.capitalized)
                            if zone?.textStyle == style { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: { ToolbarButton(icon: "textformat.size") }
            
            ToolbarButton(icon: "bold", isActive: zone?.isBold == true) {
                content.updateZone(at: path) { $0.isBold.toggle() }
            }
            
            ToolbarButton(icon: "italic", isActive: zone?.isItalic == true) {
                content.updateZone(at: path) { $0.isItalic.toggle() }
            }
            
            Menu {
                ForEach(FontFamily.allCases, id: \.self) { family in
                    Button {
                        content.updateZone(at: path) { $0.fontFamily = family }
                    } label: {
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
                    Button {
                        content.updateZone(at: path) { $0.textColor = color }
                    } label: {
                        HStack {
                            Circle().fill(color.color).frame(width: 14, height: 14)
                            Text(color.name)
                        }
                    }
                }
            } label: { ToolbarButton(icon: "paintpalette", tint: zone?.textColor.color ?? .primary) }
            
            Menu {
                ForEach(HighlightColor.allCases, id: \.self) { highlight in
                    Button {
                        content.updateZone(at: path) { $0.highlightColor = highlight }
                    } label: {
                        HStack {
                            if highlight != .none {
                                RoundedRectangle(cornerRadius: 2).fill(highlight.color ?? .clear).frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "xmark").frame(width: 14, height: 14)
                            }
                            Text(highlight.name)
                            if zone?.highlightColor == highlight { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: { ToolbarButton(icon: "highlighter", isActive: zone?.highlightColor != HighlightColor.none, tint: .primary) }
            
            ToolbarButton(icon: "list.bullet", isActive: zone?.hasBullet == true) {
                content.updateZone(at: path) { $0.hasBullet.toggle() }
            }
        }
    }
    
    // MARK: - Media Tools
    
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

// MARK: - Popover Menu Elements

struct DirectionPopoverMenu: View {
    let activeDirection: AddDirection?
    let accent: Color
    let arrowRadius: CGFloat
    
    var body: some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.15)).frame(width: 28, height: 28)
            PopoverBubble(icon: "arrow.up", isActive: activeDirection == .up, accent: accent).offset(y: -arrowRadius)
            PopoverBubble(icon: "arrow.down", isActive: activeDirection == .down, accent: accent).offset(y: arrowRadius)
            PopoverBubble(icon: "arrow.left", isActive: activeDirection == .left, accent: accent).offset(x: -arrowRadius)
            PopoverBubble(icon: "arrow.right", isActive: activeDirection == .right, accent: accent).offset(x: arrowRadius)
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
            .frame(width: 44, height: 44)
            .background(isActive ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(isActive ? 0 : 0.2), lineWidth: 1))
            .shadow(color: .black.opacity(isActive ? 0.3 : 0.15), radius: isActive ? 12 : 8, y: 4)
            .scaleEffect(isActive ? 1.15 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isActive)
    }
}

// MARK: - Toolbar Button

struct ToolbarButton: View {
    let icon: String
    var isActive: Bool = false
    var tint: Color = .primary
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(isActive ? ThemeManager.shared.accentColor.color : tint)
                .frame(width: 34, height: 34)
                .background(
                    isActive
                        ? ThemeManager.shared.accentColor.color.opacity(0.12)
                        : Color(uiColor: .tertiarySystemFill)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
