//
//  ContentBlock.swift
//  QuizFlash
//
//  Created by Ion Socol on 12.02.2026.
//
//  Apple Notes-style content block model for linear, flowing content.
//

import SwiftUI
import Foundation

// MARK: - Content Block Type
enum ContentBlockType: String, Codable, Equatable {
    case text
    case image
    case sketch
}

// MARK: - Text Alignment
enum TextBlockAlignment: String, Codable, Equatable {
    case leading
    case center
    case trailing
    
    var alignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
    
    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Text Style
enum TextBlockStyle: String, Codable, Equatable {
    case body
    case title
    case headline
    case caption
    
    var font: Font {
        switch self {
        case .body: return .system(size: 18)
        case .title: return .system(size: 28, weight: .bold)
        case .headline: return .system(size: 22, weight: .semibold)
        case .caption: return .system(size: 14)
        }
    }
}

// MARK: - Font Family
enum FontFamily: String, Codable, Equatable, CaseIterable {
    case system     // Default SF Pro
    case serif      // New York
    case mono       // SF Mono
    case rounded    // SF Rounded
    
    var name: String {
        switch self {
        case .system: return "Sans-Serif"
        case .serif: return "Serif"
        case .mono: return "Monospaced"
        case .rounded: return "Rounded"
        }
    }
    
    var icon: String {
        switch self {
        case .system: return "textformat"
        case .serif: return "textformat.abc"
        case .mono: return "chevron.left.forwardslash.chevron.right"
        case .rounded: return "a.circle"
        }
    }
    
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        case .mono:
            return .system(size: size, weight: weight, design: .monospaced)
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        }
    }
}

// MARK: - Highlight Color (Marker)
enum HighlightColor: String, Codable, Equatable, CaseIterable {
    case none
    case yellow
    case green
    case pink
    case cyan
    
    var color: Color? {
        switch self {
        case .none: return nil
        case .yellow: return Color.yellow.opacity(0.4)
        case .green: return Color.green.opacity(0.35)
        case .pink: return Color.pink.opacity(0.35)
        case .cyan: return Color.cyan.opacity(0.35)
        }
    }
    
    var name: String {
        switch self {
        case .none: return "None"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .pink: return "Pink"
        case .cyan: return "Cyan"
        }
    }
    
    var icon: String {
        switch self {
        case .none: return "xmark"
        default: return "highlighter"
        }
    }
}

// MARK: - Text Color
enum TextBlockColor: String, Codable, Equatable, CaseIterable {
    case primary
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    
    var color: Color {
        switch self {
        case .primary: return .primary
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        }
    }
    
    var name: String {
        switch self {
        case .primary: return "Default"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }
}

// MARK: - Content Block Model
/// A single block of content in the linear editor flow.
/// Blocks are ordered in a VStack, creating a natural reading flow.
struct ContentBlock: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var type: ContentBlockType
    
    // Text content
    var text: String = ""
    var textAlignment: TextBlockAlignment = .leading
    var textStyle: TextBlockStyle = .body
    var isBold: Bool = false
    var isItalic: Bool = false
    var textColor: TextBlockColor = .primary
    var hasBullet: Bool = false
    
    // Image/Sketch data (stored externally)
    var imageData: Data?
    
    // Display size (width is always full, height is adjustable)
    var displayHeight: CGFloat = 200
    
    // Image scale (0.3 to 1.0, for resizing images)
    var imageScale: CGFloat = 1.0
    
    // Lateral content (side-by-side with image/sketch)
    var lateralContent: [ContentBlock]? = nil
    
    // Creation timestamp for ordering
    var createdAt: Date = Date()
    
    // MARK: - Factory Methods
    
    /// Create a text block
    static func text(_ content: String = "", alignment: TextBlockAlignment = .leading, style: TextBlockStyle = .body) -> ContentBlock {
        ContentBlock(type: .text, text: content, textAlignment: alignment, textStyle: style)
    }
    
    /// Create a title block
    static func title(_ content: String = "") -> ContentBlock {
        ContentBlock(type: .text, text: content, textAlignment: .leading, textStyle: .title)
    }
    
    /// Create a headline block
    static func headline(_ content: String = "") -> ContentBlock {
        ContentBlock(type: .text, text: content, textAlignment: .leading, textStyle: .headline)
    }
    
    /// Create an image block
    static func image(data: Data, height: CGFloat = 200) -> ContentBlock {
        ContentBlock(type: .image, imageData: data, displayHeight: height)
    }
    
    /// Create a sketch block
    static func sketch(data: Data, height: CGFloat = 300) -> ContentBlock {
        ContentBlock(type: .sketch, imageData: data, displayHeight: height)
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, type, text, textAlignment, textStyle, isBold, isItalic, textColor, hasBullet, imageData, displayHeight, imageScale, lateralContent, createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(ContentBlockType.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        textAlignment = try container.decodeIfPresent(TextBlockAlignment.self, forKey: .textAlignment) ?? .leading
        textStyle = try container.decodeIfPresent(TextBlockStyle.self, forKey: .textStyle) ?? .body
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        textColor = try container.decodeIfPresent(TextBlockColor.self, forKey: .textColor) ?? .primary
        hasBullet = try container.decodeIfPresent(Bool.self, forKey: .hasBullet) ?? false
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        displayHeight = try container.decodeIfPresent(CGFloat.self, forKey: .displayHeight) ?? 200
        imageScale = try container.decodeIfPresent(CGFloat.self, forKey: .imageScale) ?? 1.0
        lateralContent = try container.decodeIfPresent([ContentBlock].self, forKey: .lateralContent)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
    
    init(
        id: UUID = UUID(),
        type: ContentBlockType,
        text: String = "",
        textAlignment: TextBlockAlignment = .leading,
        textStyle: TextBlockStyle = .body,
        isBold: Bool = false,
        isItalic: Bool = false,
        textColor: TextBlockColor = .primary,
        hasBullet: Bool = false,
        imageData: Data? = nil,
        displayHeight: CGFloat = 200,
        imageScale: CGFloat = 1.0,
        lateralContent: [ContentBlock]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.textAlignment = textAlignment
        self.textStyle = textStyle
        self.isBold = isBold
        self.isItalic = isItalic
        self.textColor = textColor
        self.hasBullet = hasBullet
        self.imageData = imageData
        self.displayHeight = displayHeight
        self.imageScale = imageScale
        self.lateralContent = lateralContent
        self.createdAt = createdAt
    }
}

// MARK: - Content Block State (Observable)
/// Manages the state for a card side's content blocks.
@Observable
class CardSideContent {
    var blocks: [ContentBlock] = []
    
    init(blocks: [ContentBlock] = []) {
        self.blocks = blocks
    }
    
    // MARK: - Block Management
    
    /// Add a text block at the end or after a specific block
    func addTextBlock(after blockId: UUID? = nil, initialText: String = "") {
        let newBlock = ContentBlock.text(initialText)
        insertBlock(newBlock, after: blockId)
    }
    
    /// Add an image block
    func addImageBlock(data: Data, after blockId: UUID? = nil) {
        let newBlock = ContentBlock.image(data: data)
        insertBlock(newBlock, after: blockId)
    }
    
    /// Add a sketch block
    func addSketchBlock(data: Data, after blockId: UUID? = nil) {
        let newBlock = ContentBlock.sketch(data: data)
        insertBlock(newBlock, after: blockId)
    }
    
    /// Insert block at position
    private func insertBlock(_ block: ContentBlock, after blockId: UUID?) {
        if let blockId = blockId, let index = blocks.firstIndex(where: { $0.id == blockId }) {
            blocks.insert(block, at: index + 1)
        } else {
            blocks.append(block)
        }
    }
    
    /// Delete a block
    func deleteBlock(id: UUID) {
        blocks.removeAll { $0.id == id }
    }
    
    /// Move block
    func moveBlock(from source: IndexSet, to destination: Int) {
        blocks.move(fromOffsets: source, toOffset: destination)
    }
    
    /// Update text in a block
    func updateText(id: UUID, text: String) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].text = text
        }
    }
    
    /// Update display height
    func updateHeight(id: UUID, height: CGFloat) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].displayHeight = max(100, height)
        }
    }
    
    /// Update text alignment
    func updateAlignment(id: UUID, alignment: TextBlockAlignment) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].textAlignment = alignment
        }
    }
    
    /// Update text style
    func updateStyle(id: UUID, style: TextBlockStyle) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].textStyle = style
        }
    }
    
    /// Toggle bold
    func toggleBold(id: UUID) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].isBold.toggle()
        }
    }
    
    /// Toggle italic
    func toggleItalic(id: UUID) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].isItalic.toggle()
        }
    }
    
    // MARK: - Serialization
    
    /// Encode blocks to JSON Data
    func toData() -> Data? {
        try? JSONEncoder().encode(blocks)
    }
    
    /// Decode blocks from JSON Data
    static func fromData(_ data: Data?) -> CardSideContent {
        guard let data = data,
              let blocks = try? JSONDecoder().decode([ContentBlock].self, from: data) else {
            return CardSideContent()
        }
        return CardSideContent(blocks: blocks)
    }
    
    // MARK: - Legacy Migration
    
    /// Create content from legacy text + images format
    static func fromLegacy(text: String, images: [Data]) -> CardSideContent {
        var blocks: [ContentBlock] = []
        
        // Add text block first if not empty
        if !text.isEmpty {
            blocks.append(.text(text))
        }
        
        // Add image blocks
        for imageData in images {
            blocks.append(.image(data: imageData))
        }
        
        // Ensure at least one text block exists
        if blocks.isEmpty {
            blocks.append(.text())
        }
        
        return CardSideContent(blocks: blocks)
    }
    
    // MARK: - Computed Properties
    
    /// Get combined text from all text blocks
    var combinedText: String {
        blocks
            .filter { $0.type == .text }
            .map { $0.text }
            .joined(separator: "\n")
    }
    
    /// Get all image data
    var allImages: [Data] {
        blocks
            .filter { $0.type == .image || $0.type == .sketch }
            .compactMap { $0.imageData }
    }
    
    /// Check if content is empty
    var isEmpty: Bool {
        blocks.allSatisfy { block in
            switch block.type {
            case .text: return block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .image, .sketch: return block.imageData == nil
            }
        }
    }
    
    /// Check if has any content
    var hasContent: Bool {
        !isEmpty
    }
}
