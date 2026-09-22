//
//  AccountDataScope.swift
//  QuizFlash
//

import Foundation

/// Immutable identity used to scope every local persisted read and write.
nonisolated struct AccountDataScope: Equatable, Hashable, Sendable {
    let uid: String

    init?(uid: String) {
        let normalizedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUID.isEmpty else { return nil }
        self.uid = normalizedUID
    }
}
