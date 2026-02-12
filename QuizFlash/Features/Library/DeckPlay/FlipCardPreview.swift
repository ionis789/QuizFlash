//
//  FlipCardPreview.swift
//  QuizFlash
//
//  Adaptive flip card with visible boundaries and orientation handling.
//

import SwiftUI

struct FlipCardPreview: View {
    let card: CardModel
    var isPreviewMode: Bool = false
    @Binding var isFlipped: Bool
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    
    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var isLandscape: Bool { verticalSizeClass == .compact }
    
    private var cardCornerRadius: CGFloat {
        isPreviewMode ? 16 : (isCompact ? 24 : 32)
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Back side - use zone directly
                cardFaceWithZone(
                    title: "ANSWER",
                    zone: card.backZone,
                    containerSize: geo.size
                )
                .rotation3DEffect(.degrees(isFlipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
                
                // Front side - use zone directly
                cardFaceWithZone(
                    title: "QUESTION",
                    zone: card.frontZone,
                    containerSize: geo.size
                )
                .rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 0 : 1)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isFlipped)
        }
    }
    
    // MARK: - Card Face with Zone (preserves layout structure)
    
    @ViewBuilder
    private func cardFaceWithZone(title: String, zone: ZoneModel, containerSize: CGSize) -> some View {
        ZStack {
            // Card background with clear boundaries
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardBackgroundGradient)
                .shadow(color: shadowColor, radius: isCompact ? 12 : 16, y: 6)
            
            // Border for visibility
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
            
            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text(title)
                        .font(isCompact ? .caption2.weight(.bold) : .caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Orientation indicator
                    if !isPreviewMode {
                        zoneOrientationIndicator(for: zone)
                    }
                }
                .padding(.top, isCompact ? 16 : 20)
                .padding(.horizontal, isCompact ? 16 : 24)
                
                // Main content - render zone directly
                if isPreviewMode {
                    zonePreviewContent(zone: zone)
                } else {
                    zoneFullContent(zone: zone, containerSize: containerSize)
                }
            }
        }
    }
    
    // MARK: - Zone Preview Content (Thumbnail)
    
    @ViewBuilder
    private func zonePreviewContent(zone: ZoneModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Get first text
            if let firstText = getFirstText(from: zone), !firstText.isEmpty {
                Text(firstText)
                    .font(.subheadline)
                    .lineLimit(3)
            }
            
            // Get first image
            if let firstImageData = getFirstImage(from: zone),
               let img = UIImage(data: firstImageData) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            if !zone.hasContent {
                Text("Empty")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Zone Full Content (Uses ZonePreviewView which preserves layout)
    
    @ViewBuilder
    private func zoneFullContent(zone: ZoneModel, containerSize: CGSize) -> some View {
        if zone.hasContent {
            ScrollView {
                // Use ZonePreviewView which correctly renders horizontal/vertical layouts
                ZonePreviewView(zone: zone)
                    .padding(.horizontal, isCompact ? 16 : 24)
                    .padding(.vertical, 12)
            }
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
    
    // MARK: - Zone Orientation Indicator
    
    @ViewBuilder
    private func zoneOrientationIndicator(for zone: ZoneModel) -> some View {
        let orientation = zone.preferredOrientation
        
        if orientation != .adaptive {
            HStack(spacing: 4) {
                Image(systemName: orientation == .landscape ? "rectangle.landscape.rotate" : "rectangle.portrait.rotate")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Helpers to extract content from zone
    
    private func getFirstText(from zone: ZoneModel) -> String? {
        if zone.isLeaf {
            if zone.contentType == .text && !zone.text.isEmpty {
                return zone.text
            }
        } else if let children = zone.children {
            for child in children {
                if let text = getFirstText(from: child) {
                    return text
                }
            }
        }
        return nil
    }
    
    private func getFirstImage(from zone: ZoneModel) -> Data? {
        if zone.isLeaf {
            if (zone.contentType == .image || zone.contentType == .sketch) && zone.imageData != nil {
                return zone.imageData
            }
        } else if let children = zone.children {
            for child in children {
                if let data = getFirstImage(from: child) {
                    return data
                }
            }
        }
        return nil
    }
    
    // MARK: - Styling
    
    private var cardBackgroundGradient: some ShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(uiColor: .systemBackground),
                        Color(uiColor: .systemBackground).opacity(0.95)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(uiColor: .systemGray6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
    
    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.12)
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }
}

#Preview {
    FlipCardPreview(
        card: CardModel(frontText: "Test Question", backText: "Test Answer"),
        isFlipped: .constant(false)
    )
    .frame(height: 400)
    .padding()
}
