// HomeViewModel.swift
// QuizFlash
//
// Manages UI state and business logic exclusively for the Home screen.
//
// Responsibilities:
//   - O(1) daily log lookups via a keyed cache dictionary
//   - Sheet presentation state (create folder)
//   - Folder creation coordinated with the SwiftData model context
//
// Explicitly NOT responsible for:
//   - Calendar navigation or date selection (owned by CalendarViewModel)
//   - Scroll geometry (computed inline in HomeView)

import SwiftUI
import SwiftData

@Observable
final class HomeViewModel {

    // MARK: - Sheet State

    var showCreateFolder: Bool = false
    var newFolderTitle: String = ""
    var newFolderColorHex: String = "#34C759"

    // MARK: - Logs Cache

    /// Keyed by ISO-8601 date string (yyyy-MM-dd) for O(1) lookups.
    /// Rebuilt whenever the `dailyLogs` SwiftData query result changes.
    var logsCache: [String: DailyActivityLog] = [:]

    /// Shared formatter for converting `Date` → cache key.
    /// Static to ensure it is allocated exactly once for the lifetime of the app.
    static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Cache Management

    /// Rebuilds `logsCache` from an updated array of logs.
    /// Called by `HomeView` on appear and on every `dailyLogs` change.
    func updateLogsCache(logs: [DailyActivityLog]) {
        guard logsCache.count != logs.count else { return }
        
        var dict = [String: DailyActivityLog]()
        dict.reserveCapacity(logs.count)
        for log in logs {
            dict[log.dateString] = log
        }
        logsCache = dict
    }

    /// Returns the activity log for a given date, or `nil` if none exists.
    func getFastLog(for date: Date) -> DailyActivityLog? {
        logsCache[HomeViewModel.dateKeyFormatter.string(from: date)]
    }

    // MARK: - Actions

    /// Creates and persists a new `FolderModel` with the current form values,
    /// then resets the form state. Silently logs errors — production builds
    /// should route these to a centralized error reporter.
    func createFolder(context: ModelContext) {
        let title = newFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let folder = FolderModel(title: title, colorHex: newFolderColorHex)
        context.insert(folder)

        do {
            try context.save()
            newFolderTitle = ""
            showCreateFolder = false
        } catch {
            print("[HomeViewModel] Failed to create folder: \(error)")
        }
    }
}
