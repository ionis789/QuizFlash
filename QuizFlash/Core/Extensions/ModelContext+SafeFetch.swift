//
//  ModelContext+SafeFetch.swift
//  QuizFlash
//
//  Provides a crash-safe alternative to ModelContext.model(for:).
//
//  Problem:
//  ModelContext.model(for:) can trigger a fatal error on iOS 17/26 if the
//  PersistentIdentifier cannot be resolved in the current store. This happens
//  when the model has already been deleted, when the schema is mismatched,
//  or when a background context races with a foreground deletion.
//
//  Solution:
//  safeModel(for:as:) performs a FetchDescriptor lookup by persistentModelID,
//  which returns nil instead of crashing when no matching row is found.

import SwiftData
import Foundation

extension ModelContext {

    /// Returns the model for the given identifier, or `nil` if it cannot be resolved.
    ///
    /// Unlike `model(for:)`, this method uses a `FetchDescriptor` predicate lookup
    /// so it never triggers a fatal error — it simply returns `nil` when the
    /// persistent identifier cannot be found in the current store.
    ///
    /// - Parameters:
    ///   - id: The `PersistentIdentifier` to look up.
    ///   - type: The expected concrete `PersistentModel` type.
    /// - Returns: The matching model instance, or `nil` on any failure.
    func safeModel<T: PersistentModel>(for id: PersistentIdentifier, as type: T.Type) -> T? {
        let descriptor = FetchDescriptor<T>(
            predicate: #Predicate { $0.persistentModelID == id }
        )
        return (try? fetch(descriptor))?.first
    }
}
