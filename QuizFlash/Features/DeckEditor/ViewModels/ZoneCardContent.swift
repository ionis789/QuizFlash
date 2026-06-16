//
//  ZoneCardContent.swift
//  QuizFlash
//
//  Observable ViewModel that manages the mutable zone tree for one side of a card
//  during an active editing or preview session.
//
//  Extracted from `Domain/Models/ZoneModel.swift` where mutable UI state does not belong.
//  Belongs in the DeckEditor feature layer because it drives `ZoneView` directly.
//

import Foundation

// MARK: - Zone Card Content

/// An observable ViewModel that owns and mutates the `ZoneModel` tree for one
/// face of a flashcard (front or back) during an active editing session.
///
/// `ZoneCardContent` is the single mutable source of truth for zone layout changes.
/// `ZoneView` and its sub-views read from and write to this object exclusively —
/// they must never mutate the `ZoneModel` tree directly.
///
/// After editing is complete, call `rootZone` to extract the final `ZoneModel`
/// and persist it back to the `DraftCard` or `CardModel`.
@Observable
final class ZoneCardContent {

    // MARK: - Properties

    /// The root node of the zone content tree.
    ///
    /// Modifying this property triggers SwiftUI observation and re-renders all
    /// views that depend on this object.
    var rootZone: ZoneModel
    private let stableAuthoringRoot: Bool

    /// `true` if the root zone or any descendant contains non-empty content.
    var hasContent: Bool { rootZone.hasContent }

    // MARK: - Initializer

    /// Creates a new `ZoneCardContent` with the given root zone.
    /// - Parameter rootZone: The initial zone tree. Defaults to a single empty text zone.
    init(rootZone: ZoneModel = .text(), stableAuthoringRoot: Bool = false) {
        self.stableAuthoringRoot = stableAuthoringRoot
        var normalizedRoot = rootZone
        normalizedRoot.normalizeAuthoringLayoutRecursively()
        if stableAuthoringRoot {
            normalizedRoot.wrapLeafInStableAuthoringRootIfNeeded()
        }
        self.rootZone = normalizedRoot
        ZoneEditorDebugStore.shared.recordLayoutEvent(
            "zone-content-init",
            zoneID: normalizedRoot.id,
            pathID: ZonePath.root.id,
            details: "stable=\(stableAuthoringRoot ? 1 : 0) root=\(rootDebugSummary(normalizedRoot))"
        )
    }

    // MARK: - Read

    /// Returns the `ZoneModel` at the given path within the tree, or `nil` if
    /// the path does not correspond to a valid node.
    ///
    /// - Parameter path: The index path from the root to the target zone.
    func zone(at path: ZonePath) -> ZoneModel? {
        var current = rootZone
        for index in path.indices {
            guard let children = current.children, index < children.count else { return nil }
            current = children[index]
        }
        return current
    }

    // MARK: - Write

    /// Applies an in-place mutation to the zone at the given path.
    ///
    /// Mutations bubble upward through the value-type tree, triggering a full
    /// `rootZone` replacement so that `@Observable` picks up the change.
    ///
    /// - Parameters:
    ///   - path: The index path to the target zone.
    ///   - update: A closure that receives an `inout ZoneModel` to mutate.
    func updateZone(at path: ZonePath, with update: (inout ZoneModel) -> Void) {
        let before = rootDebugSummary(rootZone)
        if path.indices.isEmpty {
            update(&rootZone)
            recordMutation("update-root", path: path, before: before)
            return
        }
        updateZoneRecursive(zone: &rootZone, path: path, pathIndex: 0, update: update)
        recordMutation("update", path: path, before: before)
    }

    // MARK: - Add Zone

    /// Inserts a new empty zone relative to the zone at the given path.
    ///
    /// Reuses an existing vertical parent container when possible to avoid
    /// unnecessary nesting.
    ///
    /// - Parameters:
    ///   - path: The index path to the reference zone.
    ///   - direction: The direction from which the new zone is added.
    /// - Returns: The `UUID` of the newly created zone (used to drive focus after insertion).
    @discardableResult
    func addZone(
        relativeTo path: ZonePath,
        direction: AddDirection,
        newZone: ZoneModel = .empty()
    ) -> UUID {
        let before = rootDebugSummary(rootZone)
        let newZoneID = newZone.id

        if path.indices.isEmpty {
            let oldRoot = rootZone
            let preservedVerticalAlignment = oldRoot.verticalAlignment
            switch direction {
            case .up:
                rootZone = .container(direction: .vertical, children: [newZone, oldRoot])
            case .down:
                rootZone = .container(direction: .vertical, children: [oldRoot, newZone])
            }
            rootZone.verticalAlignment = preservedVerticalAlignment
            recordMutation(
                "add-root",
                path: path,
                before: before,
                details: "direction=\(direction) new=\(newZone.contentType.rawValue)#\(newZoneID.uuidString.prefix(6))"
            )
            return newZoneID
        }

        guard let parentPath = path.parent, let childIndex = path.lastIndex else { return newZoneID }
        let parentZone = parentPath.indices.isEmpty ? rootZone : zone(at: parentPath)
        guard let parent = parentZone else { return newZoneID }

        if !parent.isLeaf && parent.direction == .vertical {
            // The parent is already a vertical container, so insert directly.
            updateZone(at: parentPath) { parentZone in
                var kids = parentZone.children ?? []
                switch direction {
                case .up:
                    kids.insert(newZone, at: childIndex)
                case .down:
                    kids.insert(newZone, at: childIndex + 1)
                }
                parentZone.children = kids
            }
        } else {
            // Wrap the current zone in a new vertical container.
            updateZone(at: path) { currentZone in
                let oldZone = currentZone
                switch direction {
                case .up:
                    currentZone = .container(direction: .vertical, children: [newZone, oldZone])
                case .down:
                    currentZone = .container(direction: .vertical, children: [oldZone, newZone])
                }
            }
        }
        recordMutation(
            "add",
            path: path,
            before: before,
            details: "direction=\(direction) new=\(newZone.contentType.rawValue)#\(newZoneID.uuidString.prefix(6))"
        )
        return newZoneID
    }

    /// Inserts a new empty text zone relative to the requested semantic path.
    ///
    /// Empty-card taps reuse the root zone so the first edit does not create
    /// unnecessary container nesting.
    @discardableResult
    func addTextZone(relativeTo path: ZonePath?, direction: AddDirection) -> UUID {
        let before = rootDebugSummary(rootZone)
        if !rootZone.hasContent, rootZone.isLeaf {
            let preservedVerticalAlignment = rootZone.verticalAlignment
            rootZone = .text()
            rootZone.verticalAlignment = preservedVerticalAlignment
            recordMutation("reuse-empty-root", path: .root, before: before, details: "direction=\(direction)")
            return rootZone.id
        }

        return addZone(relativeTo: path ?? .root, direction: direction, newZone: .text())
    }

    // MARK: - Move

    /// Moves the zone at `path` one slot up within its parent container.
    @discardableResult
    func moveZoneUp(at path: ZonePath) -> ZonePath? {
        guard let parentPath = path.parent,
              let childIndex = path.lastIndex,
              childIndex > 0 else { return nil }

        updateZone(at: parentPath) { parent in
            guard var kids = parent.children, childIndex < kids.count else { return }
            kids.swapAt(childIndex, childIndex - 1)
            parent.children = kids
        }

        return ZonePath(indices: parentPath.indices + [childIndex - 1])
    }

    /// Moves the zone at `path` one slot down within its parent container.
    @discardableResult
    func moveZoneDown(at path: ZonePath) -> ZonePath? {
        guard let parentPath = path.parent,
              let childIndex = path.lastIndex else { return nil }

        let childCount = zone(at: parentPath)?.children?.count ?? 0
        guard childIndex < childCount - 1 else { return nil }

        updateZone(at: parentPath) { parent in
            guard var kids = parent.children, childIndex < kids.count - 1 else { return }
            kids.swapAt(childIndex, childIndex + 1)
            parent.children = kids
        }

        return ZonePath(indices: parentPath.indices + [childIndex + 1])
    }

    // MARK: - Delete Zone

    /// Removes the zone at the given path from the tree.
    ///
    /// If the parent is left with a single child after deletion, the parent collapses
    /// into that child (unwrapping the unnecessary container).
    ///
    /// - Parameter path: The index path to the zone to delete. Deleting the root
    ///   replaces the entire tree with an empty text zone.
    func deleteZone(at path: ZonePath) {
        let before = rootDebugSummary(rootZone)
        guard !path.indices.isEmpty else {
            let preservedVerticalAlignment = rootZone.verticalAlignment
            rootZone = .text()
            rootZone.verticalAlignment = preservedVerticalAlignment
            restoreStableAuthoringRootIfNeeded()
            recordMutation("delete-root", path: path, before: before)
            return
        }
        guard let parentPath = path.parent, let childIndex = path.lastIndex else { return }
        updateZone(at: parentPath) { parent in
            guard var kids = parent.children, childIndex < kids.count else { return }
            kids.remove(at: childIndex)
            if kids.count == 1      { parent = kids[0] }
            else if kids.isEmpty    { parent = .text() }
            else                    { parent.children = kids }
        }
        restoreStableAuthoringRootIfNeeded()
        recordMutation("delete", path: path, before: before)
    }

    // MARK: - Cleanup

    /// Recursively collapses redundant single-child containers in the tree.
    ///
    /// Call this before saving to avoid persisting unnecessary nesting produced
    /// by sequential zone deletions.
    func cleanup() {
        let preservedVerticalAlignment = rootZone.verticalAlignment
        cleanupRecursive(zone: &rootZone)
        rootZone.verticalAlignment = preservedVerticalAlignment
    }

    // MARK: - Private Helpers

    private func updateZoneRecursive(
        zone: inout ZoneModel,
        path: ZonePath,
        pathIndex: Int,
        update: (inout ZoneModel) -> Void
    ) {
        guard pathIndex < path.indices.count else {
            update(&zone)
            return
        }
        let childIndex = path.indices[pathIndex]
        guard zone.children != nil, childIndex < zone.children!.count else { return }

        if pathIndex == path.indices.count - 1 {
            update(&zone.children![childIndex])
        } else {
            updateZoneRecursive(
                zone: &zone.children![childIndex],
                path: path,
                pathIndex: pathIndex + 1,
                update: update
            )
        }
    }

    private func recordMutation(
        _ action: String,
        path: ZonePath,
        before: String,
        details: String = ""
    ) {
        ZoneEditorDebugStore.shared.recordLayoutEvent(
            "zone-content-\(action)",
            zoneID: zone(at: path)?.id,
            pathID: path.id,
            details: "\(details.isEmpty ? "" : "\(details) ")before=\(before) after=\(rootDebugSummary(rootZone))"
        )
    }

    private func rootDebugSummary(_ zone: ZoneModel) -> String {
        if zone.isLeaf {
            return "\(zone.contentType.rawValue)#\(zone.id.uuidString.prefix(6))"
        }

        let children = (zone.children ?? [])
            .prefix(6)
            .map { child in
                child.isLeaf
                    ? "\(child.contentType.rawValue)#\(child.id.uuidString.prefix(6))"
                    : "\(child.direction.rawValue)#\(child.id.uuidString.prefix(6)):\(child.children?.count ?? 0)"
            }
            .joined(separator: ",")
        return "\(zone.direction.rawValue)#\(zone.id.uuidString.prefix(6))[\(children)]"
    }

    private func cleanupRecursive(zone: inout ZoneModel) {
        if var kids = zone.children {
            for i in 0..<kids.count { cleanupRecursive(zone: &kids[i]) }
            if kids.count == 1      { zone = kids[0] }
            else if kids.isEmpty    { zone.children = nil; zone.contentType = .empty }
            else {
                zone.direction = .vertical
                zone.children = kids
            }
        }
    }

    private func restoreStableAuthoringRootIfNeeded() {
        guard stableAuthoringRoot else { return }
        rootZone.wrapLeafInStableAuthoringRootIfNeeded()
    }
}

private extension ZoneModel {
    mutating func wrapLeafInStableAuthoringRootIfNeeded() {
        guard isLeaf else { return }
        let child = self
        let preservedVerticalAlignment = verticalAlignment
        self = .container(direction: .vertical, children: [child])
        verticalAlignment = preservedVerticalAlignment
    }

    mutating func normalizeAuthoringLayoutRecursively() {
        guard var kids = children else { return }
        for index in kids.indices {
            kids[index].normalizeAuthoringLayoutRecursively()
        }
        direction = .vertical
        children = kids
    }

    mutating func regenerateIDsRecursively() {
        id = UUID()
        guard var kids = children else { return }
        for index in kids.indices {
            kids[index].regenerateIDsRecursively()
        }
        children = kids
    }
}
