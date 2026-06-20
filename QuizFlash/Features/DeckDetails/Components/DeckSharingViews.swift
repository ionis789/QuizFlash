//
//  DeckSharingViews.swift
//  QuizFlash
//
//  UI-only sharing and storage components.
//  These are dumb views — all export state lives in `DeckViewModel` and is
//  passed down via closures or bindings. No `@StateObject` / `@ObservedObject`.
//

import SwiftUI
import SwiftData

// MARK: - Share Sheet

/// A thin `UIViewControllerRepresentable` wrapper around `UIActivityViewController`.
struct ShareSheet: UIViewControllerRepresentable {
    /// The items to share (typically a `[URL]`).
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

// MARK: - Export Deck Button

/// A dumb button that triggers deck export via a closure supplied by the parent ViewModel.
///
/// All export state (`isExporting`, share sheet presentation) is owned by `DeckViewModel`
/// and bound through the parent view — this component has zero local state.
struct ExportDeckButton: View {

    // MARK: - Inputs

    /// Called when the user taps the export button. The parent is responsible for
    /// updating `isExporting` and presenting the share sheet.
    let onExport: () -> Void

    /// Mirrors `DeckViewModel.isExporting`; disables the button and shows loading dots.
    let isExporting: Bool

    // MARK: - Body

    var body: some View {
        Button {
            onExport()
        } label: {
            if isExporting {
                ProgressActivityDots()
            } else {
                Label("Export Deck", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(isExporting)
    }
}

// MARK: - Import Progress View

/// Displays live import progress driven by a `DeckSharingManager` instance
/// passed directly from the presenting view.
///
/// Uses `@ObservedObject` because `DeckSharingManager` is an `ObservableObject`-based
/// service; ownership stays with the caller.
struct ImportProgressView: View {

    // MARK: - Inputs

    /// The sharing manager observed for progress updates.
    @ObservedObject var sharingManager: DeckSharingManager

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            ProgressActivityDots()

            Text(sharingManager.currentOperation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 250)
    }
}

// MARK: - Storage Info View

/// Full-screen list that shows per-deck storage usage and offers a cleanup action.
///
/// `StorageManager` and `GarbageCollector` are still `ObservableObject`-based services;
/// they are owned here via `@StateObject` because they represent independent domain
/// logic not related to `DeckViewModel`.
struct StorageInfoView: View {

    // MARK: - Inputs

    @Environment(\.modelContext) private var context
    /// The list of decks whose storage footprint should be calculated.
    let decks: [DeckModel]

    // MARK: - Private State

    @StateObject private var storageManager   = StorageManager.shared
    @StateObject private var garbageCollector = GarbageCollector.shared
    @State private var lastCleanupDate: String = "Never"

    // MARK: - Body

    var body: some View {
        List {

            // MARK: Summary Section
            Section {
                HStack {
                    Label("Total Used", systemImage: "externaldrive.fill")
                    Spacer()
                    if storageManager.isCalculating {
                        ProgressActivityDots()
                    } else {
                        Text(StorageManager.formatBytes(storageManager.totalStorageUsed))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Label("Last Cleanup", systemImage: "trash")
                    Spacer()
                    Text(lastCleanupDate)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Storage")
            }

            // MARK: Per-Deck Breakdown Section
            Section {
                if storageManager.deckStorageInfo.isEmpty && !storageManager.isCalculating {
                    Text("No deck data")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        Array(storageManager.deckStorageInfo.values)
                            .sorted { $0.totalBytes > $1.totalBytes }
                    ) { info in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.deckTitle)
                                    .font(.body)
                                Text("\(info.cardCount) cards, \(info.imageCount) images")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(info.formattedSize)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("By Deck")
            }

            // MARK: Cleanup Section
            Section {
                Button {
                    Task {
                        await garbageCollector.runFullCleanup(context: context)
                    }
                } label: {
                    HStack {
                        Label("Clear Temp Files", systemImage: "trash.circle")
                        Spacer()
                        if garbageCollector.isRunning {
                            ProgressActivityDots()
                        }
                    }
                }
                .disabled(garbageCollector.isRunning)

                if garbageCollector.bytesFreed > 0 {
                    HStack {
                        Text("Freed")
                        Spacer()
                        Text(StorageManager.formatBytes(garbageCollector.bytesFreed))
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Cleanup")
            }
        }
        .navigationTitle("Storage")
        .task {
            await storageManager.calculateStorage(for: decks)
            if let lastCleanup = garbageCollector.lastCleanupDate {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                lastCleanupDate = formatter.localizedString(for: lastCleanup, relativeTo: Date())
            }
        }
    }
}
