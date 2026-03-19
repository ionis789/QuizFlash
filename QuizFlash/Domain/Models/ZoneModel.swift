//
//  ZoneModel.swift
//  QuizFlash
//
//  Pure value-type model describing the content tree of one flashcard side.
//  This file must remain free of UI-layer types — no UIKit, no SwiftUI, no rendering logic.
//
//  UI state helpers previously co-located here have been moved to their correct layers:
//    - HighlightContext     → Features/Library/ViewModels/HighlightContext.swift
//    - ZoneCardContent      → Features/DeckEditor/ViewModels/ZoneCardContent.swift
//    - ImageCache + Data extension → Core/Helpers/ImageCache.swift
//
//  Note: thumbnail data is returned as raw `Data`; the View/ViewModel layer
//  is responsible for constructing `UIImage` objects from it.
//

import Foundation

// MARK: - Card Orientation

/// Describes the preferred physical orientation for displaying a card layout.
nonisolated enum CardOrientation: String, Codable {
    case portrait, landscape, adaptive
}

// MARK: - Zone Direction

/// Describes the axis along which child zones are arranged inside a container zone.
nonisolated enum ZoneDirection: String, Codable {
    case horizontal, vertical
}

// MARK: - Zone Content Type

/// Describes the kind of content stored in a leaf `ZoneModel`.
nonisolated enum ZoneContentType: String, Codable {
    case empty, text, image, sketch, code
}

// MARK: - Zone Model

/// A recursive value type representing one node in a flashcard content tree.
///
/// A `ZoneModel` is either:
/// - A **leaf**: holds content (`text`, `imageData`, etc.) directly.
/// - A **container**: holds an ordered array of child `ZoneModel` nodes, arranged
///   horizontally or vertically.
///
/// The entire tree is serialised to JSON and stored in `CardModel.frontZoneData` /
/// `CardModel.backZoneData` using `@Attribute(.externalStorage)`.
nonisolated struct ZoneModel: Identifiable, Codable, Equatable, Sendable {

    // MARK: - Identity

    /// A stable unique identifier for this zone node.
    var id: UUID = UUID()

    // MARK: - Content

    /// The kind of content this leaf zone holds.
    var contentType: ZoneContentType = .empty

    /// The programming language identifier for `.code` zones (e.g. `"swift"`, `"python"`).
    var codeLanguage: String? = nil

    /// The text content for `.text` and `.code` zones.
    var text: String = ""

    /// The raw image data for `.image` and `.sketch` zones.
    var imageData: Data? = nil

    // MARK: - Text Styling

    /// The text size/weight style applied to this zone.
    var textStyle: TextBlockStyle = .body

    /// The horizontal text alignment applied to this zone.
    var textAlignment: TextBlockAlignment = .leading

    /// The foreground text colour applied to this zone.
    var textColor: TextBlockColor = .primary

    /// Whether text in this zone is bold.
    var isBold: Bool = false

    /// Whether text in this zone is italic.
    var isItalic: Bool = false

    /// Whether this zone shows a leading bullet point.
    var hasBullet: Bool = false

    /// The font family applied to this zone.
    var fontFamily: FontFamily = .system

    /// The background highlight colour applied to this zone.
    var highlightColor: HighlightColor = .none

    // MARK: - Image

    /// A scaling factor applied to image content in this zone.
    var imageScale: CGFloat = 1.0

    // MARK: - Layout (Container)

    /// Child zones. Non-nil and non-empty when this node is a container.
    var children: [ZoneModel]? = nil

    /// The layout axis for arranging child zones. Only meaningful when `children` is non-nil.
    var direction: ZoneDirection = .horizontal

    // MARK: - Computed Properties

    /// `true` if this zone has no children (i.e., it is a leaf node).
    var isLeaf: Bool { children == nil || children?.isEmpty == true }

    /// `true` if this zone (or any descendant) contains non-empty content.
    var hasContent: Bool {
        if !isLeaf { return children?.contains { $0.hasContent } ?? false }
        switch contentType {
        case .empty: return false
        case .text, .code:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image, .sketch: return imageData != nil
        }
    }

    /// The number of direct child zones.
    var childCount: Int { children?.count ?? 0 }

    /// The preferred display orientation inferred from the zone tree layout.
    var preferredOrientation: CardOrientation {
        if isLeaf { return .adaptive }
        guard let kids = children, !kids.isEmpty else { return .adaptive }
        if direction == .horizontal && kids.count >= 2 { return .landscape }
        if direction == .vertical {
            let hasWideChild = kids.contains { child in
                !child.isLeaf &&
                child.direction == .horizontal &&
                (child.children?.count ?? 0) >= 2
            }
            return hasWideChild ? .landscape : .portrait
        }
        return .adaptive
    }

    /// Extracts up to three raw image `Data` objects from image/sketch leaf nodes
    /// in the subtree rooted at this zone.
    ///
    /// Returns raw `Data` rather than `UIImage` so that this model remains free
    /// of UIKit. The caller (ViewModel or View layer) is responsible for
    /// converting each `Data` blob into a `UIImage` or `Image`.
    var thumbnailDataList: [Data] {
        var result: [Data] = []
        if isLeaf {
            if let data = imageData,
               (contentType == .image || contentType == .sketch) {
                result.append(data)
            }
        } else {
            children?.forEach { child in result.append(contentsOf: child.thumbnailDataList) }
        }
        return Array(result.prefix(3))
    }

    // MARK: - Factory Methods

    /// Creates an empty leaf zone.
    static func empty() -> ZoneModel { ZoneModel(contentType: .empty) }

    /// Creates a text leaf zone with optional initial content.
    static func text(_ content: String = "") -> ZoneModel { ZoneModel(contentType: .text, text: content) }

    /// Creates an image leaf zone from raw image data.
    static func image(data: Data) -> ZoneModel { ZoneModel(contentType: .image, imageData: data) }

    /// Creates a sketch leaf zone from raw sketch data.
    static func sketch(data: Data) -> ZoneModel { ZoneModel(contentType: .sketch, imageData: data) }

    /// Creates a code leaf zone with optional language identifier.
    static func code(_ content: String, language: String? = nil) -> ZoneModel {
        var zone = ZoneModel(contentType: .code, text: content)
        zone.codeLanguage = language
        return zone
    }

    /// Creates a container zone wrapping child zones along the given axis.
    static func container(direction: ZoneDirection, children: [ZoneModel]) -> ZoneModel {
        var zone = ZoneModel()
        zone.children = children
        zone.direction = direction
        return zone
    }

    // MARK: - Serialisation

    /// Encodes this zone tree to JSON data.
    /// - Returns: JSON `Data`, or `nil` if encoding fails.
    func encode() -> Data? { try? JSONEncoder().encode(self) }

    /// Decodes a `ZoneModel` from raw JSON data.
    ///
    /// Explicitly `nonisolated` so it can be called from any actor context without
    /// inheriting the `@MainActor` isolation that co-located `@Observable` classes
    /// may spread to types in the same source file.
    /// - Parameter data: The raw JSON data to decode.
    /// - Returns: A decoded `ZoneModel`, or `nil` if decoding fails.
    nonisolated static func decode(from data: Data) -> ZoneModel? {
        try? JSONDecoder().decode(ZoneModel.self, from: data)
    }

    // MARK: - Mutation Helpers

    /// Wraps this zone in a new container that places a new empty zone relative to it.
    ///
    /// - Parameter addDirection: The direction from which the new zone is inserted.
    /// - Returns: A new container `ZoneModel` that includes both this zone and the new empty zone.
    mutating func addZone(in addDirection: AddDirection) -> ZoneModel {
        let newZone = ZoneModel.empty()
        switch addDirection {
        case .left:  return .container(direction: .horizontal, children: [newZone, self])
        case .right: return .container(direction: .horizontal, children: [self, newZone])
        case .up:    return .container(direction: .vertical,   children: [newZone, self])
        case .down:  return .container(direction: .vertical,   children: [self, newZone])
        }
    }

    // MARK: - Preview Text

    /// Returns a single-line plain-text preview of the first non-empty leaf in the subtree.
    ///
    /// Used for search indexing and deck list previews.
    /// - Parameter maxLength: Maximum number of characters in the returned string. Defaults to `60`.
    /// - Returns: A truncated preview string, or `"Empty"` if no content exists.
    func previewText(maxLength: Int = 60) -> String {
        if isLeaf {
            switch contentType {
            case .text, .code:
                let line = text.split(separator: "\n").first.map(String.init) ?? text
                if line.count <= maxLength { return line }
                return String(line.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
            case .image:  return "Image"
            case .sketch: return "Sketch"
            case .empty:  return "Empty"
            }
        }
        guard let kids = children else { return "Empty" }
        for child in kids {
            let preview = child.previewText(maxLength: maxLength)
            if preview != "Empty" { return preview }
        }
        return "Empty"
    }
}

// MARK: - Add Direction

/// Represents the four cardinal directions for inserting a new zone relative to an existing one.
enum AddDirection: String, CaseIterable {

    case left, right, up, down

    /// The SF Symbol icon name that visually represents this direction.
    var icon: String {
        switch self {
        case .left:  return "arrow.left.square"
        case .right: return "arrow.right.square"
        case .up:    return "arrow.up.square"
        case .down:  return "arrow.down.square"
        }
    }

    /// The `ZoneDirection` axis corresponding to this add direction.
    var zoneDirection: ZoneDirection {
        switch self {
        case .left, .right: return .horizontal
        case .up, .down:    return .vertical
        }
    }
}

// MARK: - Zone Path

/// An immutable index path that uniquely identifies a zone node within a `ZoneModel` tree.
///
/// The `indices` array encodes the path from the root to the target node, where each
/// element is a child index at the corresponding depth.
struct ZonePath: Equatable, Hashable {

    /// The sequence of child indices from root to target.
    let indices: [Int]

    /// The zone path that refers to the root node.
    static let root = ZonePath(indices: [])

    /// A stable string identifier suitable for use as a SwiftUI view identity.
    var id: String { "zone_" + indices.map { String($0) }.joined(separator: "_") }

    /// Returns a new path extended by one additional child index.
    func appending(_ index: Int) -> ZonePath { ZonePath(indices: indices + [index]) }

    /// The path to the parent node, or `nil` if this is the root.
    var parent: ZonePath? { indices.isEmpty ? nil : ZonePath(indices: Array(indices.dropLast())) }

    /// The index of this node within its parent's `children` array, or `nil` if this is the root.
    var lastIndex: Int? { indices.last }
}
