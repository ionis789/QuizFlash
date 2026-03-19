//
//  LearnModeViewModel.swift
//  QuizFlash
//
//  Manages the guided Learn report built from deck card previews and review history.
//

import SwiftUI
import SwiftData
import OSLog

// MARK: - Learn Mode View Model

/// Coordinates the loading state for the Learn-mode report sheet.
@Observable
@MainActor
final class LearnModeViewModel {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "LearnModeViewModel"
    )

    /// The deck being summarized.
    let deck: DeckModel

    /// The latest loaded report snapshot.
    private(set) var report: LearnModeReport = .empty

    /// `true` while the background repository is preparing the report.
    var isLoading = false

    /// Human-readable load failure shown in the fallback state.
    var errorMessage: String?

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(deck: DeckModel) {
        self.deck = deck
    }

    deinit {
        loadTask?.cancel()
    }

    /// Starts or refreshes the report load for the current deck.
    func load(container: ModelContainer) {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        let deckID = deck.persistentModelID
        loadTask = Task { [weak self] in
            let repository = PlayModeCardRepository(container: container)
            let report = await repository.loadLearnReport(for: deckID)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                self.report = report
                self.isLoading = false
            }
        }
    }

    /// Loads the report and surfaces a fallback message if the task fails unexpectedly.
    func loadIfNeeded(container: ModelContainer) {
        guard !isLoading, report == .empty, errorMessage == nil else { return }
        load(container: container)
    }

    /// Resets replaceable resources when the sheet disappears.
    func tearDown() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    /// Stores a non-fatal loading error for the Learn report.
    func presentError(_ error: Error) {
        logger.error("Failed to load Learn report: \(error.localizedDescription, privacy: .public)")
        errorMessage = "Learn mode couldn’t prepare this deck report."
        isLoading = false
    }
}
