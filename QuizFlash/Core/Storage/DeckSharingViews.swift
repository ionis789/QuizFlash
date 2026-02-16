//
//  DeckSharingViews.swift
//  QuizFlash
//

import SwiftUI
import SwiftData


/// UI-only: share sheet, export button, import progress, storage info.

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

// MARK: - Export Deck Button

struct ExportDeckButton: View {
    let deck: DeckModel

    @StateObject private var sharingManager = DeckSharingManager.shared
    @State private var exportedURL: URL?
    @State private var showShareSheet = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Button {
            exportDeck()
        } label: {
            if sharingManager.isExporting {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Label("Export Deck", systemImage: "square.and.arrow.up")
            }
        }
            .disabled(sharingManager.isExporting)
            .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
            .alert("Export Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func exportDeck() {
        Task {
            do {
                let url = try await sharingManager.exportDeck(deck)
                exportedURL = url
                showShareSheet = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Import Progress View

struct ImportProgressView: View {
    @ObservedObject var sharingManager: DeckSharingManager

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: sharingManager.progress)
                .progressViewStyle(.linear)

            Text(sharingManager.currentOperation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
            .padding()
            .frame(width: 250)
    }
}

// MARK: - Storage Info View

struct StorageInfoView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var storageManager = StorageManager.shared
    @StateObject private var garbageCollector = GarbageCollector.shared
    @State private var lastCleanupDate: String = "Never"
    let decks: [DeckModel]

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Total Used", systemImage: "externaldrive.fill")
                    Spacer()
                    if storageManager.isCalculating {
                        ProgressView()
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

            Section {
                if storageManager.deckStorageInfo.isEmpty && !storageManager.isCalculating {
                    Text("No deck data")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(storageManager.deckStorageInfo.values).sorted(by: { $0.totalBytes > $1.totalBytes })) { info in
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
                            ProgressView()
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
                let formater = RelativeDateTimeFormatter()
                formater.unitsStyle = .full
                lastCleanupDate = formater.localizedString(for: lastCleanup, relativeTo: Date())
            }
        }
    }
}
