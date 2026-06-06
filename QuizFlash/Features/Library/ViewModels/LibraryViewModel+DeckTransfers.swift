//
//  LibraryViewModel+DeckTransfers.swift
//  QuizFlash
//
//  Delete, move, import, and export flows for the Library view model.
//

import Foundation
import SwiftData

// MARK: - Deck Mutations

extension LibraryViewModel {

    func triggerDeckImport() {
        showFileImporter = true
    }

    func deleteSelectedDecks(from allDecks: [DeckModel], context: ModelContext) {
        deleteDecks(with: selectedDecks, from: allDecks, context: context)
        selectedDecks.removeAll()
        isSelecting = false
    }

    func confirmSingleDeletion(context: ModelContext) {
        if let target = deckToDelete,
           let deck = context.safeModel(for: target.id, as: DeckModel.self) {
            deck.folder?.deckCount -= 1
            context.delete(deck)
        }
        deckToDelete = nil
    }

    func moveSingleDeck(
        from allDecks: [DeckModel],
        to destinationFolder: FolderModel?,
        context: ModelContext
    ) {
        showMoveConfirmation = false
        guard let target = deckToMove else { return }
        moveDecks(
            with: [target.id],
            from: allDecks,
            to: destinationFolder,
            context: context,
            exitsSelectionModeOnSuccess: false
        )
        deckToMove = nil
    }

    func moveSelectedDecks(
        from allDecks: [DeckModel],
        to destinationFolder: FolderModel?,
        context: ModelContext
    ) {
        showMoveConfirmation = false
        moveDecks(
            with: selectedDecks,
            from: allDecks,
            to: destinationFolder,
            context: context,
            exitsSelectionModeOnSuccess: true
        )
    }

    func handleFileImport(_ result: Result<[URL], Error>, context: ModelContext) {
        switch result {
        case .success(let urls):
            let jsonURLs = urls.filter { $0.pathExtension.lowercased() == "json" }
            guard !jsonURLs.isEmpty else {
                importErrorMessage = AppLocalization.string(
                    "Please select .json files",
                    locale: AppPreferences.persistedResolvedLocale
                )
                showImportError = true
                return
            }

            isImporting = true
            Task {
                var importedCount = 0
                var lastImportedName = ""
                var errors: [String] = []

                for url in jsonURLs {
                    do {
                        let deck = try await DeckSharingManager.shared.importDeck(from: url, into: context)
                        importedCount += 1
                        lastImportedName = deck.title
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }

                self.isImporting = false
                if importedCount > 0 {
                    self.importedDeckName = importedCount == 1 ? lastImportedName : "\(importedCount) decks"
                    self.showImportSuccess = true
                }
                if !errors.isEmpty {
                    self.importErrorMessage = errors.joined(separator: "\n")
                    self.showImportError = true
                }
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }

    func exportSelectedDecks(from allDecks: [DeckModel]) {
        let selected = allDecks.filter { selectedDecks.contains($0.id) }
        guard !selected.isEmpty else { return }

        exitSelectionMode()
        exportDecks(selected)
    }

    func exportSingleDeck(_ target: LibraryDeckActionTarget, from allDecks: [DeckModel]) {
        guard let deck = allDecks.first(where: { $0.id == target.id }) else { return }
        exportDecks([deck])
    }
}

// MARK: - Helpers

private extension LibraryViewModel {

    func exportDecks(_ decks: [DeckModel]) {
        guard !decks.isEmpty else { return }
        isExporting = true

        Task {
            var exportedFiles: [URL] = []
            var errors: [String] = []

            for deck in decks {
                do {
                    let url = try await DeckSharingManager.shared.exportDeck(deck)
                    exportedFiles.append(url)
                } catch {
                    errors.append("\(deck.title): \(error.localizedDescription)")
                }
            }

            self.isExporting = false
            if !exportedFiles.isEmpty {
                self.exportedURLs = exportedFiles
                self.showShareSheet = true
            }
            if !errors.isEmpty {
                self.exportErrorMessage = errors.joined(separator: "\n")
                self.showExportError = true
            }
        }
    }

    func deleteDecks(
        with ids: Set<PersistentIdentifier>,
        from allDecks: [DeckModel],
        context: ModelContext
    ) {
        for deck in allDecks where ids.contains(deck.id) {
            deck.folder?.deckCount -= 1
            context.delete(deck)
        }
    }

    func moveDecks(
        with ids: Set<PersistentIdentifier>,
        from allDecks: [DeckModel],
        to destinationFolder: FolderModel?,
        context: ModelContext,
        exitsSelectionModeOnSuccess: Bool
    ) {
        let decksToMove = allDecks.filter { ids.contains($0.id) }
        guard !decksToMove.isEmpty else { return }

        let affectedFolders = uniqueFolders(
            from: decksToMove.compactMap(\.folder) + (destinationFolder.map { [$0] } ?? [])
        )
        let originalFolderCounts = Dictionary(
            uniqueKeysWithValues: affectedFolders.map { ($0.persistentModelID, $0.deckCount) }
        )
        let originalDeckFolders = Dictionary(uniqueKeysWithValues: decksToMove.map { ($0.id, $0.folder) })
        let originalEditedAt = Dictionary(uniqueKeysWithValues: decksToMove.map { ($0.id, $0.editedAt) })

        var movedDecks: [DeckModel] = []

        for deck in decksToMove {
            if deck.folder?.persistentModelID == destinationFolder?.persistentModelID {
                continue
            }

            deck.folder?.deckCount -= 1
            destinationFolder?.deckCount += 1
            deck.folder = destinationFolder
            deck.editedAt = Date()
            movedDecks.append(deck)
        }

        guard !movedDecks.isEmpty else {
            if exitsSelectionModeOnSuccess {
                exitSelectionMode()
            }
            return
        }

        do {
            try context.save()
            if exitsSelectionModeOnSuccess {
                exitSelectionMode()
            }
        } catch {
            for deck in movedDecks {
                deck.folder = originalDeckFolders[deck.id] ?? nil
                if let editedAt = originalEditedAt[deck.id] {
                    deck.editedAt = editedAt
                }
            }

            for folder in affectedFolders {
                if let count = originalFolderCounts[folder.persistentModelID] {
                    folder.deckCount = count
                }
            }

            moveErrorMessage = "Couldn't move the selected decks right now."
            showMoveError = true
        }
    }

    func uniqueFolders(from folders: [FolderModel]) -> [FolderModel] {
        var seen = Set<PersistentIdentifier>()
        var unique: [FolderModel] = []

        for folder in folders {
            let id = folder.persistentModelID
            if seen.insert(id).inserted {
                unique.append(folder)
            }
        }

        return unique
    }
}
