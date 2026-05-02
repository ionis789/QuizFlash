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

// MARK: - Zone Size Mode

/// Describes how much rectangle a leaf zone occupies inside the card content area.
nonisolated enum ZoneSizeMode: String, Codable, Equatable, Sendable, CaseIterable {
    case auto
    case fillWidth
    case fixed
}

// MARK: - Zone Block Alignment

/// Describes where a zone rectangle sits inside the card content area.
nonisolated enum ZoneBlockAlignment: String, Codable, Equatable, Sendable, CaseIterable {
    case leading
    case center
    case trailing
    case auto
}

// MARK: - Zone Vertical Alignment

/// Describes how a whole card face positions its zone tree on the vertical axis.
nonisolated enum ZoneVerticalAlignment: String, Codable, Equatable, Sendable, CaseIterable {
    case auto
    case top
    case center
    case bottom

    init(fallbackContentAlignment: FlashcardContentAlignment) {
        switch fallbackContentAlignment {
        case .top:
            self = .top
        case .center:
            self = .center
        }
    }

    func resolved(fallback: ZoneVerticalAlignment) -> ZoneVerticalAlignment {
        self == .auto ? fallback.resolved(fallback: .center) : self
    }
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

    /// The size mode applied to this zone's layout rectangle.
    var sizeMode: ZoneSizeMode = .auto

    /// The block alignment applied to this zone's layout rectangle.
    var blockAlignment: ZoneBlockAlignment = .auto

    /// Explicit width used when `sizeMode` is `.fixed`.
    var fixedWidth: CGFloat? = nil

    /// Explicit height used when `sizeMode` is `.fixed`.
    var fixedHeight: CGFloat? = nil

    /// The vertical alignment applied to the card face rooted at this zone.
    var verticalAlignment: ZoneVerticalAlignment = .auto

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

    // MARK: - Initialization

    /// Creates a zone with explicit content, styling, and layout values.
    init(
        id: UUID = UUID(),
        contentType: ZoneContentType = .empty,
        codeLanguage: String? = nil,
        text: String = "",
        imageData: Data? = nil,
        textStyle: TextBlockStyle = .body,
        textAlignment: TextBlockAlignment = .leading,
        sizeMode: ZoneSizeMode = .auto,
        blockAlignment: ZoneBlockAlignment = .auto,
        verticalAlignment: ZoneVerticalAlignment = .auto,
        fixedWidth: CGFloat? = nil,
        fixedHeight: CGFloat? = nil,
        textColor: TextBlockColor = .primary,
        isBold: Bool = false,
        isItalic: Bool = false,
        hasBullet: Bool = false,
        fontFamily: FontFamily = .system,
        highlightColor: HighlightColor = .none,
        imageScale: CGFloat = 1.0,
        children: [ZoneModel]? = nil,
        direction: ZoneDirection = .horizontal
    ) {
        self.id = id
        self.contentType = contentType
        self.codeLanguage = codeLanguage
        self.text = text
        self.imageData = imageData
        self.textStyle = textStyle
        self.textAlignment = textAlignment
        self.sizeMode = sizeMode
        self.blockAlignment = blockAlignment
        self.verticalAlignment = verticalAlignment
        self.fixedWidth = fixedWidth
        self.fixedHeight = fixedHeight
        self.textColor = textColor
        self.isBold = isBold
        self.isItalic = isItalic
        self.hasBullet = hasBullet
        self.fontFamily = fontFamily
        self.highlightColor = highlightColor
        self.imageScale = imageScale
        self.children = children
        self.direction = direction
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case contentType
        case codeLanguage
        case text
        case imageData
        case textStyle
        case textAlignment
        case sizeMode
        case blockAlignment
        case verticalAlignment
        case fixedWidth
        case fixedHeight
        case textColor
        case isBold
        case isItalic
        case hasBullet
        case fontFamily
        case highlightColor
        case imageScale
        case children
        case direction
    }

    /// Decodes a zone while migrating pre-layout-mode cards safely.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTextAlignment = try container.decodeIfPresent(TextBlockAlignment.self, forKey: .textAlignment) ?? .leading
        let decodedSizeMode = try container.decodeIfPresent(ZoneSizeMode.self, forKey: .sizeMode)
        let decodedBlockAlignment = try container.decodeIfPresent(ZoneBlockAlignment.self, forKey: .blockAlignment)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.contentType = try container.decodeIfPresent(ZoneContentType.self, forKey: .contentType) ?? .empty
        self.codeLanguage = try container.decodeIfPresent(String.self, forKey: .codeLanguage)
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        self.textStyle = try container.decodeIfPresent(TextBlockStyle.self, forKey: .textStyle) ?? .body
        self.textAlignment = decodedTextAlignment
        self.sizeMode = decodedSizeMode ?? Self.migratedSizeMode(from: decodedTextAlignment)
        self.blockAlignment = decodedBlockAlignment ?? Self.migratedBlockAlignment(from: decodedTextAlignment)
        self.verticalAlignment = try container.decodeIfPresent(ZoneVerticalAlignment.self, forKey: .verticalAlignment) ?? .auto
        self.fixedWidth = try container.decodeIfPresent(CGFloat.self, forKey: .fixedWidth)
        self.fixedHeight = try container.decodeIfPresent(CGFloat.self, forKey: .fixedHeight)
        self.textColor = try container.decodeIfPresent(TextBlockColor.self, forKey: .textColor) ?? .primary
        self.isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        self.isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        self.hasBullet = try container.decodeIfPresent(Bool.self, forKey: .hasBullet) ?? false
        self.fontFamily = try container.decodeIfPresent(FontFamily.self, forKey: .fontFamily) ?? .system
        self.highlightColor = try container.decodeIfPresent(HighlightColor.self, forKey: .highlightColor) ?? .none
        self.imageScale = try container.decodeIfPresent(CGFloat.self, forKey: .imageScale) ?? 1.0
        self.children = try container.decodeIfPresent([ZoneModel].self, forKey: .children)
        self.direction = try container.decodeIfPresent(ZoneDirection.self, forKey: .direction) ?? .horizontal
    }

    private static func migratedSizeMode(from oldAlignment: TextBlockAlignment) -> ZoneSizeMode {
        oldAlignment == .leading ? .auto : .fillWidth
    }

    private static func migratedBlockAlignment(from oldAlignment: TextBlockAlignment) -> ZoneBlockAlignment {
        oldAlignment == .leading ? .auto : .leading
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
        let preservedVerticalAlignment = verticalAlignment
        var container: ZoneModel
        switch addDirection {
        case .left:  container = .container(direction: .horizontal, children: [newZone, self])
        case .right: container = .container(direction: .horizontal, children: [self, newZone])
        case .up:    container = .container(direction: .vertical,   children: [newZone, self])
        case .down:  container = .container(direction: .vertical,   children: [self, newZone])
        }
        container.verticalAlignment = preservedVerticalAlignment
        return container
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
