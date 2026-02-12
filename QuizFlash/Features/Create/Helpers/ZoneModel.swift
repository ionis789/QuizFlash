//
//  ZoneModel.swift
//  QuizFlash
//
//  Recursive zone model for flexible card layouts.
//  Zones can be split horizontally or vertically, creating a tree structure.
//

import SwiftUI
import Foundation

// MARK: - Card Orientation

enum CardOrientation: String, Codable {
    case portrait   // Optimized for tall screens
    case landscape  // Optimized for wide screens
    case adaptive   // Works well in both
}

// MARK: - Zone Direction

enum ZoneDirection: String, Codable {
    case horizontal // Children side by side (left to right)
    case vertical   // Children stacked (top to bottom)
}

// MARK: - Zone Content Type

enum ZoneContentType: String, Codable {
    case empty      // No content yet
    case text       // Text content
    case image      // Image content
    case sketch     // Sketch content
}

// MARK: - Zone Model

/// Recursive zone model - can contain content OR child zones
struct ZoneModel: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    
    // Content (if this is a leaf zone)
    var contentType: ZoneContentType = .empty
    var text: String = ""
    var imageData: Data? = nil
    
    // Text formatting
    var textStyle: TextBlockStyle = .body
    var textAlignment: TextBlockAlignment = .leading
    var textColor: TextBlockColor = .primary
    var isBold: Bool = false
    var isItalic: Bool = false
    var hasBullet: Bool = false
    
    // Image/Sketch scale (0.3 to 1.0)
    var imageScale: CGFloat = 1.0
    
    // Children (if this is a container zone)
    var children: [ZoneModel]? = nil
    var direction: ZoneDirection = .horizontal
    
    // MARK: - Computed Properties
    
    /// Check if this zone is a leaf (has content, no children)
    var isLeaf: Bool {
        children == nil || children?.isEmpty == true
    }
    
    /// Check if this zone has actual content
    var hasContent: Bool {
        if !isLeaf { return children?.contains { $0.hasContent } ?? false }
        switch contentType {
        case .empty: return false
        case .text: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image, .sketch: return imageData != nil
        }
    }
    
    /// Number of direct children
    var childCount: Int {
        children?.count ?? 0
    }
    
    /// Determines if this layout is optimized for landscape (wide) or portrait (tall)
    /// Based on the structure: horizontal splits suggest landscape, vertical suggest portrait
    var preferredOrientation: CardOrientation {
        if isLeaf {
            // Single content - works in both
            return .adaptive
        }
        
        guard let kids = children, !kids.isEmpty else { return .adaptive }
        
        // Check root direction
        if direction == .horizontal && kids.count >= 2 {
            // Multiple horizontal children = landscape preferred
            return .landscape
        } else if direction == .vertical {
            // Vertical layout = portrait preferred
            // But check if any child is horizontal with multiple items
            let hasWideChild = kids.contains { child in
                !child.isLeaf && child.direction == .horizontal && (child.children?.count ?? 0) >= 2
            }
            return hasWideChild ? .landscape : .portrait
        }
        
        return .adaptive
    }
    
    // MARK: - Factory Methods
    
    /// Create an empty zone
    static func empty() -> ZoneModel {
        ZoneModel(contentType: .empty)
    }
    
    /// Create a text zone
    static func text(_ content: String = "") -> ZoneModel {
        ZoneModel(contentType: .text, text: content)
    }
    
    /// Create an image zone
    static func image(data: Data) -> ZoneModel {
        ZoneModel(contentType: .image, imageData: data)
    }
    
    /// Create a sketch zone
    static func sketch(data: Data) -> ZoneModel {
        ZoneModel(contentType: .sketch, imageData: data)
    }
    
    /// Create a container zone with children
    static func container(direction: ZoneDirection, children: [ZoneModel]) -> ZoneModel {
        var zone = ZoneModel()
        zone.children = children
        zone.direction = direction
        return zone
    }
    
    // MARK: - Encoding/Decoding Helpers (nonisolated for Swift 6)
    
    /// Encode zone to Data
    func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }
    
    /// Decode zone from Data
    static func decode(from data: Data) -> ZoneModel? {
        try? JSONDecoder().decode(ZoneModel.self, from: data)
    }
    
    // MARK: - Mutations
    
    /// Add a zone in the specified direction relative to this zone
    /// Returns the modified parent that contains both zones
    mutating func addZone(in addDirection: AddDirection) -> ZoneModel {
        let newZone = ZoneModel.empty()
        
        switch addDirection {
        case .left:
            return ZoneModel.container(direction: .horizontal, children: [newZone, self])
        case .right:
            return ZoneModel.container(direction: .horizontal, children: [self, newZone])
        case .up:
            return ZoneModel.container(direction: .vertical, children: [newZone, self])
        case .down:
            return ZoneModel.container(direction: .vertical, children: [self, newZone])
        }
    }
    
    /// Add a sibling zone when we're already in a container
    mutating func addSibling(at index: Int, direction: AddDirection) {
        guard var kids = children else { return }
        
        let newZone = ZoneModel.empty()
        
        // Determine where to insert based on direction
        switch direction {
        case .left, .up:
            kids.insert(newZone, at: index)
        case .right, .down:
            kids.insert(newZone, at: min(index + 1, kids.count))
        }
        
        children = kids
    }
}

// MARK: - Add Direction

enum AddDirection: String, CaseIterable {
    case left, right, up, down
    
    var icon: String {
        switch self {
        case .left: return "arrow.left.square"
        case .right: return "arrow.right.square"
        case .up: return "arrow.up.square"
        case .down: return "arrow.down.square"
        }
    }
    
    var zoneDirection: ZoneDirection {
        switch self {
        case .left, .right: return .horizontal
        case .up, .down: return .vertical
        }
    }
}

// MARK: - Zone Path

/// Identifies a zone in the tree structure
struct ZonePath: Equatable, Hashable {
    let indices: [Int]
    
    static let root = ZonePath(indices: [])
    
    /// Unique ID for ScrollViewReader
    var id: String {
        "zone_" + indices.map { String($0) }.joined(separator: "_")
    }
    
    func appending(_ index: Int) -> ZonePath {
        ZonePath(indices: indices + [index])
    }
    
    var parent: ZonePath? {
        guard !indices.isEmpty else { return nil }
        return ZonePath(indices: Array(indices.dropLast()))
    }
    
    var lastIndex: Int? {
        indices.last
    }
}

// MARK: - Card Side Content (Updated)

/// Observable wrapper for zone-based card content
@Observable
class ZoneCardContent {
    var rootZone: ZoneModel
    
    init(rootZone: ZoneModel = .text()) {
        self.rootZone = rootZone
    }
    
    /// Check if content exists
    var hasContent: Bool {
        rootZone.hasContent
    }
    
    /// Get zone at path
    func zone(at path: ZonePath) -> ZoneModel? {
        var current = rootZone
        for index in path.indices {
            guard let children = current.children, index < children.count else { return nil }
            current = children[index]
        }
        return current
    }
    
    /// Update zone at path
    func updateZone(at path: ZonePath, with update: (inout ZoneModel) -> Void) {
        if path.indices.isEmpty {
            update(&rootZone)
            return
        }
        
        updateZoneRecursive(zone: &rootZone, path: path, pathIndex: 0, update: update)
    }
    
    private func updateZoneRecursive(zone: inout ZoneModel, path: ZonePath, pathIndex: Int, update: (inout ZoneModel) -> Void) {
        guard pathIndex < path.indices.count else {
            update(&zone)
            return
        }
        
        let childIndex = path.indices[pathIndex]
        guard zone.children != nil, childIndex < zone.children!.count else { return }
        
        if pathIndex == path.indices.count - 1 {
            update(&zone.children![childIndex])
        } else {
            updateZoneRecursive(zone: &zone.children![childIndex], path: path, pathIndex: pathIndex + 1, update: update)
        }
    }
    
    /// Add zone in direction relative to zone at path
    func addZone(relativeTo path: ZonePath, direction: AddDirection) {
        if path.indices.isEmpty {
            // Adding relative to root - wrap root in container
            let newZone = ZoneModel.empty()
            let oldRoot = rootZone
            
            switch direction {
            case .left:
                rootZone = .container(direction: .horizontal, children: [newZone, oldRoot])
            case .right:
                rootZone = .container(direction: .horizontal, children: [oldRoot, newZone])
            case .up:
                rootZone = .container(direction: .vertical, children: [newZone, oldRoot])
            case .down:
                rootZone = .container(direction: .vertical, children: [oldRoot, newZone])
            }
            return
        }
        
        // Get parent path and child index
        guard let parentPath = path.parent, let childIndex = path.lastIndex else { return }
        
        // Check if parent direction matches add direction
        let parentZone = parentPath.indices.isEmpty ? rootZone : zone(at: parentPath)
        guard let parent = parentZone else { return }
        
        if !parent.isLeaf && parent.direction == direction.zoneDirection {
            // Same direction - just add sibling
            updateZone(at: parentPath) { parentZone in
                let newZone = ZoneModel.empty()
                var kids = parentZone.children ?? []
                switch direction {
                case .left, .up:
                    kids.insert(newZone, at: childIndex)
                case .right, .down:
                    kids.insert(newZone, at: childIndex + 1)
                }
                parentZone.children = kids
            }
        } else {
            // Different direction - wrap current zone in new container
            updateZone(at: path) { currentZone in
                let oldZone = currentZone
                let newZone = ZoneModel.empty()
                
                switch direction {
                case .left:
                    currentZone = .container(direction: .horizontal, children: [newZone, oldZone])
                case .right:
                    currentZone = .container(direction: .horizontal, children: [oldZone, newZone])
                case .up:
                    currentZone = .container(direction: .vertical, children: [newZone, oldZone])
                case .down:
                    currentZone = .container(direction: .vertical, children: [oldZone, newZone])
                }
            }
        }
    }
    
    /// Delete zone at path
    func deleteZone(at path: ZonePath) {
        guard !path.indices.isEmpty else {
            // Can't delete root, just reset it
            rootZone = .text()
            return
        }
        
        guard let parentPath = path.parent, let childIndex = path.lastIndex else { return }
        
        updateZone(at: parentPath) { parent in
            guard var kids = parent.children, childIndex < kids.count else { return }
            kids.remove(at: childIndex)
            
            if kids.count == 1 {
                // Only one child left - replace parent with child
                parent = kids[0]
            } else if kids.isEmpty {
                // No children - convert to empty leaf
                parent = .empty()
            } else {
                parent.children = kids
            }
        }
    }
    
    /// Clean up empty zones
    func cleanup() {
        cleanupRecursive(zone: &rootZone)
    }
    
    private func cleanupRecursive(zone: inout ZoneModel) {
        // First, recurse into children
        if var kids = zone.children {
            for i in 0..<kids.count {
                cleanupRecursive(zone: &kids[i])
            }
            
            // Remove empty children
            kids = kids.filter { $0.hasContent || !$0.isLeaf }
            
            if kids.count == 1 {
                // Collapse single child
                zone = kids[0]
            } else if kids.isEmpty {
                // Convert to empty leaf
                zone.children = nil
                zone.contentType = .empty
            } else {
                zone.children = kids
            }
        }
    }
}

// MARK: - Migration Helper

extension ZoneCardContent {
    /// Create from old CardSideContent
    static func from(oldContent: CardSideContent) -> ZoneCardContent {
        let zones = oldContent.blocks.map { block -> ZoneModel in
            switch block.type {
            case .text:
                var zone = ZoneModel.text(block.text)
                zone.textStyle = block.textStyle
                zone.textAlignment = block.textAlignment
                zone.textColor = block.textColor
                zone.isBold = block.isBold
                zone.isItalic = block.isItalic
                zone.hasBullet = block.hasBullet
                return zone
            case .image:
                if let data = block.imageData {
                    var zone = ZoneModel.image(data: data)
                    // IMPORTANT: Copy scale and alignment from block!
                    zone.imageScale = block.imageScale
                    zone.textAlignment = block.textAlignment
                    return zone
                }
                return .empty()
            case .sketch:
                if let data = block.imageData {
                    var zone = ZoneModel.sketch(data: data)
                    // IMPORTANT: Copy scale and alignment from block!
                    zone.imageScale = block.imageScale
                    zone.textAlignment = block.textAlignment
                    return zone
                }
                return .empty()
            }
        }
        
        if zones.isEmpty {
            return ZoneCardContent(rootZone: .text())
        } else if zones.count == 1 {
            return ZoneCardContent(rootZone: zones[0])
        } else {
            return ZoneCardContent(rootZone: .container(direction: .vertical, children: zones))
        }
    }
    
    /// Convert back to old CardSideContent
    func toOldContent() -> CardSideContent {
        var blocks: [ContentBlock] = []
        collectBlocks(from: rootZone, into: &blocks)
        return CardSideContent(blocks: blocks.isEmpty ? [.text()] : blocks)
    }
    
    private func collectBlocks(from zone: ZoneModel, into blocks: inout [ContentBlock]) {
        if zone.isLeaf {
            switch zone.contentType {
            case .empty:
                break
            case .text:
                var block = ContentBlock.text(zone.text)
                block.textStyle = zone.textStyle
                block.textAlignment = zone.textAlignment
                block.textColor = zone.textColor
                block.isBold = zone.isBold
                block.isItalic = zone.isItalic
                block.hasBullet = zone.hasBullet
                blocks.append(block)
            case .image:
                if let data = zone.imageData {
                    var block = ContentBlock.image(data: data)
                    // IMPORTANT: Copy scale and alignment from zone!
                    block.imageScale = zone.imageScale
                    block.textAlignment = zone.textAlignment
                    blocks.append(block)
                }
            case .sketch:
                if let data = zone.imageData {
                    var block = ContentBlock.sketch(data: data)
                    // IMPORTANT: Copy scale and alignment from zone!
                    block.imageScale = zone.imageScale
                    block.textAlignment = zone.textAlignment
                    blocks.append(block)
                }
            }
        } else if let children = zone.children {
            for child in children {
                collectBlocks(from: child, into: &blocks)
            }
        }
    }
}

// MARK: - Image Optimization Extension
extension Data {
    /// Comprimă imaginea la o dimensiune maximă pentru stocare eficientă
    func compressedImageData(maxDimension: CGFloat = 1200, compressionQuality: CGFloat = 0.7) -> Data? {
        guard let uiImage = UIImage(data: self) else { return nil }
        
        let size = uiImage.size
        let scale: CGFloat
        
        if size.width > size.height {
            scale = size.width > maxDimension ? maxDimension / size.width : 1.0
        } else {
            scale = size.height > maxDimension ? maxDimension / size.height : 1.0
        }
        
        if scale >= 1.0 {
            // Imagine deja mică, doar comprimăm JPEG
            return uiImage.jpegData(compressionQuality: compressionQuality)
        }
        
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        uiImage.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage?.jpegData(compressionQuality: compressionQuality)
    }
    
    /// Creează thumbnail mic pentru preview rapid
    func thumbnailData(maxDimension: CGFloat = 400) -> Data? {
        return compressedImageData(maxDimension: maxDimension, compressionQuality: 0.6)
    }
}

// MARK: - Image Cache for Performance
final class ImageCache {
    static let shared = ImageCache()
    private init() {}
    
    private var cache = NSCache<NSString, UIImage>()
    
    func image(for data: Data, scale: CGFloat = 1.0) -> UIImage? {
        let key = NSString(string: "\(data.hashValue)_\(scale)")
        
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        guard let original = UIImage(data: data) else { return nil }
        
        // Dacă scale e 1.0, returnăm originalul
        if scale >= 0.99 {
            cache.setObject(original, forKey: key)
            return original
        }
        
        // Altfel, scalăm imaginea
        let newSize = CGSize(
            width: original.size.width * scale,
            height: original.size.height * scale
        )
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, UIScreen.main.scale)
        original.draw(in: CGRect(origin: .zero, size: newSize))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        if let scaled = scaled {
            cache.setObject(scaled, forKey: key)
            return scaled
        }
        
        return original
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}
