//
//  ExamGoalModel.swift
//  QuizFlash
//
//  A SwiftData model representing a dated study target linked to one or more decks.
//

import Foundation
import SwiftData

// MARK: - Exam Goal Status

/// Lifecycle status for an exam goal shown in Home analytics.
nonisolated enum ExamGoalStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case completed
    case archived

    var id: String { rawValue }

    /// Human-readable status label used by Home surfaces.
    var title: String {
        switch self {
        case .active:
            return "Active"
        case .completed:
            return "Completed"
        case .archived:
            return "Archived"
        }
    }

    /// SF Symbol used by Home status menus and chips.
    var systemImage: String {
        switch self {
        case .active:
            return "bolt.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .archived:
            return "archivebox.fill"
        }
    }
}

// MARK: - Exam Goal Model

/// A dated study goal that can track readiness across multiple linked decks.
///
/// `ExamGoalModel` belongs in the data layer only. Presentation-specific summaries
/// and readiness calculations live in Home view-model code.
@Model
class ExamGoalModel {

    // MARK: - Stored Properties

    /// User-facing title of the exam or checkpoint.
    var title: String

    /// Optional note shown in Home summaries and day markers.
    var note: String

    /// Target calendar date for the exam goal.
    var date: Date

    /// Raw storage backing the persisted status enum.
    var statusRaw: String

    /// Desired daily study workload while preparing for this goal.
    var targetWorkload: Int

    /// Creation timestamp used for stable sorting and future auditing.
    var createdAt: Date

    /// Last update timestamp used when the goal changes.
    var editedAt: Date

    // MARK: - Relationships

    /// Decks that contribute material toward this exam goal.
    @Relationship(inverse: \DeckModel.examGoals)
    var linkedDecks: [DeckModel] = []

    // MARK: - Computed Properties

    /// Type-safe accessor around the persisted status.
    var status: ExamGoalStatus {
        get { ExamGoalStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        title: String,
        note: String = "",
        date: Date,
        targetWorkload: Int = 30,
        status: ExamGoalStatus = .active,
        linkedDecks: [DeckModel] = []
    ) {
        let now = Date()
        self.title = title
        self.note = note
        self.date = date
        self.statusRaw = status.rawValue
        self.targetWorkload = targetWorkload
        self.createdAt = now
        self.editedAt = now
        self.linkedDecks = linkedDecks
    }
}
