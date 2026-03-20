//
//  AICardConversionModels.swift
//  QuizFlash
//
//  Sendable value types used by the AI-backed card conversion pipeline.
//

import Foundation
import SwiftData

// MARK: - AI Card Conversion Models

/// One persisted card projected into a lightweight value payload for AI conversion.
struct AICardConversionSource: Identifiable, Equatable, Sendable {
    let id: PersistentIdentifier
    let kind: CardKind
    let content: DraftCardContent
}

/// One converted AI payload paired back to the originating persisted card.
struct AICardConversionOutput: Sendable {
    let sourceCardID: PersistentIdentifier
    let generatedCard: AIFlashcard
}
