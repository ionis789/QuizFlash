//
//  LibraryViewModel.swift
//  QuizFlash
//
//  Created by Ion Socol on 16.02.2026.
//
import SwiftUI
import SwiftData

@Observable
@MainActor
final class LibraryViewModel {
    
    // MARK: - View Preferences
    var sortOrder: SortOrder = .newest
    var viewMode: ViewMode = .list
    
    // MARK: - Selection State
    var isSelecting = false
    var selectedDecks: Set<PersistentIdentifier> = []
    var showDeleteConfirmation = false
    
    // MARK: - Action States
    var deckToDelete: DeckModel?
    var deckToEditColor: DeckModel?
    
    // MARK: - Import State
    var showFileImporter = false
    var isImporting = false
    var showImportError = false
    var importErrorMessage = ""
    var showImportSuccess = false
    var importedDeckName = ""
    
    // MARK: - Export State
    var isExporting = false
    var exportedURLs: [URL] = []
    var showShareSheet = false
    var showExportError = false
    var exportErrorMessage = ""
    
    // MARK: - Selection Actions
    func toggleSelection(for deck: DeckModel) {
        if selectedDecks.contains(deck.id) {
            selectedDecks.remove(deck.id)
        } else {
            selectedDecks.insert(deck.id)
        }
    }
    
    func exitSelectionMode() {
        isSelecting = false
        selectedDecks.removeAll()
    }
    
    // MARK: - Delete Actions
    func deleteSelectedDecks(from allDecks: [DeckModel], context: ModelContext) {
        for deck in allDecks where selectedDecks.contains(deck.id) {
            context.delete(deck)
        }
        selectedDecks.removeAll()
        isSelecting = false
    }
    
    func confirmSingleDeletion(context: ModelContext) {
        if let deck = deckToDelete {
            context.delete(deck)
        }
        deckToDelete = nil
    }
    
    // MARK: - Import Logic
    func handleFileImport(_ result: Result<[URL], Error>, context: ModelContext) {
        switch result {
        case .success(let urls):
            let qflashURLs = urls.filter { $0.pathExtension.lowercased() == "qflash" }
            
            guard !qflashURLs.isEmpty else {
                importErrorMessage = "Please select .qflash files"
                showImportError = true
                return
            }
            
            isImporting = true
            
            Task {
                var importedCount = 0
                var lastImportedName = ""
                var errors: [String] = []
                
                for url in qflashURLs {
                    do {
                        let importedDeck = try await DeckSharingManager.shared.importDeck(from: url, into: context)
                        importedCount += 1
                        lastImportedName = importedDeck.title
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
    
    // MARK: - Export Logic
    func exportSelectedDecks(from allDecks: [DeckModel]) {
        let selectedDecksList = allDecks.filter { selectedDecks.contains($0.id) }
        guard !selectedDecksList.isEmpty else { return }
        
        isExporting = true
        
        Task {
            var exportedFiles: [URL] = []
            var errors: [String] = []
            
            for deck in selectedDecksList {
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
}
