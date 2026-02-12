//
//  FlipCardPreview.swift
//  QuizFlash
//
//  Adaptive flip card with visible boundaries.
//

import SwiftUI

struct FlipCardPreview: View {
    let card: CardModel
    var isPreviewMode: Bool = false
    @Binding var isFlipped: Bool
    // New property to control scroll state
    var scrollDisabled: Bool = false
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    
    private var isCompact: Bool { horizontalSizeClass == .compact }
    
    private var cardCornerRadius: CGFloat {
        isPreviewMode ? 16 : (isCompact ? 24 : 32)
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Back side (Answer)
                cardFaceWithZone(
                    title: "ANSWER",
                    zone: card.backZone,
                    containerSize: geo.size
                )
                .rotation3DEffect(.degrees(isFlipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
                
                // Front side (Question)
                cardFaceWithZone(
                    title: "QUESTION",
                    zone: card.frontZone,
                    containerSize: geo.size
                )
                .rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 0 : 1)
            }
            .compositingGroup()
            .animation(.easeInOut(duration: 0.35), value: isFlipped)
        }
    }
    
    // MARK: - Card Face Logic
    
    @ViewBuilder
    private func cardFaceWithZone(title: String, zone: ZoneModel, containerSize: CGSize) -> some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardBackgroundGradient)
                .shadow(color: shadowColor, radius: isCompact ? 12 : 16, y: 6)
            
            // Border
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
            
            // Content Container
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title)
                        .font(isCompact ? .caption2.weight(.bold) : .caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if !isPreviewMode {
                        zoneOrientationIndicator(for: zone)
                    }
                }
                .padding(.top, isCompact ? 16 : 20)
                .padding(.horizontal, isCompact ? 16 : 24)
                
                // Content
                if isPreviewMode {
                    zonePreviewContent(zone: zone)
                } else {
                    zoneFullContent(zone: zone, containerSize: containerSize)
                }
            }
        }
    }
    
    @ViewBuilder
    private func zonePreviewContent(zone: ZoneModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let firstText = getFirstText(from: zone), !firstText.isEmpty {
                Text(firstText).font(.subheadline).lineLimit(3)
            }
            if let firstImageData = getFirstImage(from: zone),
               let img = UIImage(data: firstImageData) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if !zone.hasContent {
                Text("Empty").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
    }
    
    @ViewBuilder
    private func zoneFullContent(zone: ZoneModel, containerSize: CGSize) -> some View {
        if zone.hasContent {
            ScrollView(.vertical, showsIndicators: true) {
                ZonePreviewView(zone: zone)
                    .padding(.horizontal, isCompact ? 16 : 24)
                    .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            // CRITICAL FIX: Disables scroll when parent is swiping
            .scrollDisabled(scrollDisabled)
        } else {
            emptyZoneContent
        }
    }
    
    private var emptyZoneContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.quote")
                .font(isCompact ? .largeTitle : .system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No content")
                .font(isCompact ? .body : .title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func zoneOrientationIndicator(for zone: ZoneModel) -> some View {
        let orientation = zone.preferredOrientation
        if orientation != .adaptive {
            Image(systemName: orientation == .landscape ? "rectangle.landscape.rotate" : "rectangle.portrait.rotate")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    
    // Helpers
    private func getFirstText(from zone: ZoneModel) -> String? {
        if zone.isLeaf {
            if zone.contentType == .text && !zone.text.isEmpty { return zone.text }
        } else if let children = zone.children {
            for child in children {
                if let text = getFirstText(from: child) { return text }
            }
        }
        return nil
    }
    
    private func getFirstImage(from zone: ZoneModel) -> Data? {
        if zone.isLeaf {
            if (zone.contentType == .image || zone.contentType == .sketch) && zone.imageData != nil { return zone.imageData }
        } else if let children = zone.children {
            for child in children {
                if let data = getFirstImage(from: child) { return data }
            }
        }
        return nil
    }
    
    // Styling
    private var cardBackgroundGradient: some ShapeStyle {
        let colors: [Color] = colorScheme == .dark
            ? [Color(uiColor: .systemBackground), Color(uiColor: .systemBackground).opacity(0.95)]
            : [.white, Color(uiColor: .systemGray6)]
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    
    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.12)
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }
}
