//
//  ZoneModel.swift
//  QuizFlash
//

import SwiftUI
import Foundation

// MARK: - Global Highlight Context
/// Single source of truth for the entire card (Front & Back) during an active search session.
@Observable
final class HighlightContext {
    let query: String
    private(set) var isDismissed: Bool = false
    
    init(query: String) {
        self.query = query
    }
    
    /// Irreversibly dismisses highlights for the entire session.
    func dismiss() {
        isDismissed = true
    }
    
    /// Determines if a specific zone should show a highlight based on its text
    func shouldHighlight(text: String) -> Bool {
        guard !isDismissed, !query.isEmpty, !text.isEmpty else { return false }
        let tokens = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return tokens.contains { token in
            text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
    
    /// MVVM: Generates the completely transparent overlay with highlighted tokens internally.
    func generateOverlay(for text: String, font: Font, highlightColor: Color) -> AttributedString {
        var attrString = AttributedString(text)
        attrString.font = font
        
        // CRITICAL: Text must be completely invisible so it perfectly overlays the TextField.
        attrString.foregroundColor = .clear
        
        guard !isDismissed, !query.isEmpty else { return attrString }
        
        let tokens = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        for token in tokens {
            var searchRange = attrString.startIndex..<attrString.endIndex
            while let matchRange = attrString[searchRange].range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) {
                attrString[matchRange].backgroundColor = highlightColor.opacity(0.3)
                searchRange = matchRange.upperBound..<attrString.endIndex
            }
        }
        return attrString
    }
}

// MARK: - Card Orientation
enum CardOrientation: String, Codable {
    case portrait, landscape, adaptive
}

// MARK: - Zone Direction
enum ZoneDirection: String, Codable {
    case horizontal, vertical
}

// MARK: - Zone Content Type
enum ZoneContentType: String, Codable {
    case empty, text, image, sketch
}

// MARK: - Zone Model
struct ZoneModel: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var contentType: ZoneContentType = .empty
    var text: String = ""
    var imageData: Data? = nil
    var textStyle: TextBlockStyle = .body
    var textAlignment: TextBlockAlignment = .leading
    var textColor: TextBlockColor = .primary
    var isBold: Bool = false
    var isItalic: Bool = false
    var hasBullet: Bool = false
    var fontFamily: FontFamily = .system
    var highlightColor: HighlightColor = .none
    var imageScale: CGFloat = 1.0
    var children: [ZoneModel]? = nil
    var direction: ZoneDirection = .horizontal

    var isLeaf: Bool { children == nil || children?.isEmpty == true }

    var hasContent: Bool {
        if !isLeaf { return children?.contains { $0.hasContent } ?? false }
        switch contentType {
        case .empty: return false
        case .text: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image, .sketch: return imageData != nil
        }
    }

    var childCount: Int { children?.count ?? 0 }

    var preferredOrientation: CardOrientation {
        if isLeaf { return .adaptive }
        guard let kids = children, !kids.isEmpty else { return .adaptive }
        if direction == .horizontal && kids.count >= 2 { return .landscape }
        else if direction == .vertical {
            let hasWideChild = kids.contains { child in !child.isLeaf && child.direction == .horizontal && (child.children?.count ?? 0) >= 2 }
            return hasWideChild ? .landscape : .portrait
        }
        return .adaptive
    }

    var thumbnails: [UIImage] {
        var result: [UIImage] = []
        if isLeaf {
            if let data = imageData, (contentType == .image || contentType == .sketch), let img = UIImage(data: data) { result.append(img) }
        } else {
            children?.forEach { child in result.append(contentsOf: child.thumbnails) }
        }
        return Array(result.prefix(3))
    }

    static func empty() -> ZoneModel { ZoneModel(contentType: .empty) }
    static func text(_ content: String = "") -> ZoneModel { ZoneModel(contentType: .text, text: content) }
    static func image(data: Data) -> ZoneModel { ZoneModel(contentType: .image, imageData: data) }
    static func sketch(data: Data) -> ZoneModel { ZoneModel(contentType: .sketch, imageData: data) }
    
    static func container(direction: ZoneDirection, children: [ZoneModel]) -> ZoneModel {
        var zone = ZoneModel()
        zone.children = children
        zone.direction = direction
        return zone
    }

    func encode() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(from data: Data) -> ZoneModel? { try? JSONDecoder().decode(ZoneModel.self, from: data) }

    mutating func addZone(in addDirection: AddDirection) -> ZoneModel {
        let newZone = ZoneModel.empty()
        switch addDirection {
        case .left: return ZoneModel.container(direction: .horizontal, children: [newZone, self])
        case .right: return ZoneModel.container(direction: .horizontal, children: [self, newZone])
        case .up: return ZoneModel.container(direction: .vertical, children: [newZone, self])
        case .down: return ZoneModel.container(direction: .vertical, children: [self, newZone])
        }
    }

    func previewText(maxLength: Int = 60) -> String {
        if isLeaf {
            switch contentType {
            case .text:
                let line = text.split(separator: "\n").first.map(String.init) ?? text
                if line.count <= maxLength { return line }
                return String(line.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
            case .image: return "Image"
            case .sketch: return "Sketch"
            case .empty: return "Empty"
            }
        }
        guard let kids = children else { return "Empty" }
        for child in kids {
            let p = child.previewText(maxLength: maxLength)
            if p != "Empty" { return p }
        }
        return "Empty"
    }
}

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

struct ZonePath: Equatable, Hashable {
    let indices: [Int]
    static let root = ZonePath(indices: [])
    var id: String { "zone_" + indices.map { String($0) }.joined(separator: "_") }
    func appending(_ index: Int) -> ZonePath { ZonePath(indices: indices + [index]) }
    var parent: ZonePath? { indices.isEmpty ? nil : ZonePath(indices: Array(indices.dropLast())) }
    var lastIndex: Int? { indices.last }
}

@Observable
class ZoneCardContent {
    var rootZone: ZoneModel
    init(rootZone: ZoneModel = .text()) { self.rootZone = rootZone }
    var hasContent: Bool { rootZone.hasContent }

    func zone(at path: ZonePath) -> ZoneModel? {
        var current = rootZone
        for index in path.indices {
            guard let children = current.children, index < children.count else { return nil }
            current = children[index]
        }
        return current
    }

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

        if pathIndex == path.indices.count - 1 { update(&zone.children![childIndex]) }
        else { updateZoneRecursive(zone: &zone.children![childIndex], path: path, pathIndex: pathIndex + 1, update: update) }
    }

    @discardableResult
    func addZone(relativeTo path: ZonePath, direction: AddDirection) -> UUID {
        let newZone = ZoneModel.empty()
        let newZoneID = newZone.id

        if path.indices.isEmpty {
            let oldRoot = rootZone
            switch direction {
            case .left: rootZone = .container(direction: .horizontal, children: [newZone, oldRoot])
            case .right: rootZone = .container(direction: .horizontal, children: [oldRoot, newZone])
            case .up: rootZone = .container(direction: .vertical, children: [newZone, oldRoot])
            case .down: rootZone = .container(direction: .vertical, children: [oldRoot, newZone])
            }
            return newZoneID
        }

        guard let parentPath = path.parent, let childIndex = path.lastIndex else { return newZoneID }
        let parentZone = parentPath.indices.isEmpty ? rootZone : zone(at: parentPath)
        guard let parent = parentZone else { return newZoneID }

        if !parent.isLeaf && parent.direction == direction.zoneDirection {
            updateZone(at: parentPath) { parentZone in
                var kids = parentZone.children ?? []
                switch direction {
                case .left, .up: kids.insert(newZone, at: childIndex)
                case .right, .down: kids.insert(newZone, at: childIndex + 1)
                }
                parentZone.children = kids
            }
        } else {
            updateZone(at: path) { currentZone in
                let oldZone = currentZone
                switch direction {
                case .left: currentZone = .container(direction: .horizontal, children: [newZone, oldZone])
                case .right: currentZone = .container(direction: .horizontal, children: [oldZone, newZone])
                case .up: currentZone = .container(direction: .vertical, children: [newZone, oldZone])
                case .down: currentZone = .container(direction: .vertical, children: [oldZone, newZone])
                }
            }
        }
        return newZoneID
    }

    func deleteZone(at path: ZonePath) {
        guard !path.indices.isEmpty else {
            rootZone = .text()
            return
        }
        guard let parentPath = path.parent, let childIndex = path.lastIndex else { return }
        updateZone(at: parentPath) { parent in
            guard var kids = parent.children, childIndex < kids.count else { return }
            kids.remove(at: childIndex)
            if kids.count == 1 { parent = kids[0] }
            else if kids.isEmpty { parent = .empty() }
            else { parent.children = kids }
        }
    }

    func cleanup() { cleanupRecursive(zone: &rootZone) }

    private func cleanupRecursive(zone: inout ZoneModel) {
        if var kids = zone.children {
            for i in 0..<kids.count { cleanupRecursive(zone: &kids[i]) }
            if kids.count == 1 { zone = kids[0] }
            else if kids.isEmpty {
                zone.children = nil
                zone.contentType = .empty
            } else { zone.children = kids }
        }
    }
}


// MARK: - Image Optimization Extension
extension Data {
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
            return uiImage.jpegData(compressionQuality: compressionQuality)
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        uiImage.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage?.jpegData(compressionQuality: compressionQuality)
    }

    func thumbnailData(maxDimension: CGFloat = 400) -> Data? {
        return compressedImageData(maxDimension: maxDimension, compressionQuality: 0.6)
    }
}

// MARK: - Image Cache for Performance
final class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, UIImage>()
    
    private init() {
        cache.totalCostLimit = 50 * 1024 * 1024
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearCache()
        }
    }
    
    func image(for data: Data, id: String, targetSize: CGSize, scale: CGFloat = UIScreen.main.scale) -> UIImage? {
        let cacheKey = "\(id)_\(targetSize.width)x\(targetSize.height)" as NSString
        
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        guard let downsampledImage = downsample(imageData: data, to: targetSize, scale: scale) else {
            return UIImage(data: data)
        }
        
        let cost = Int(downsampledImage.size.width * downsampledImage.size.height * 4)
        cache.setObject(downsampledImage, forKey: cacheKey, cost: cost)
        
        return downsampledImage
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
    
    private func downsample(imageData: Data, to pointSize: CGSize, scale: CGFloat) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, imageSourceOptions) else {
            return nil
        }
        
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }
        
        return UIImage(cgImage: downsampledImage)
    }
}
