//
//  TestModelContainer.swift
//  QuizFlashTests
//
//  In-memory SwiftData helpers shared by mutation tests.
//

import SwiftData
@testable import QuizFlash
import XCTest

@MainActor
enum TestModelContainerFactory {
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            FolderModel.self,
            DeckModel.self,
            CardModel.self,
            ReviewEvent.self,
            UserProfile.self,
            DailyActivityLog.self,
            HomeDailyStudyAggregate.self,
            HomeDailyDeckAggregate.self,
            HomeDailyCardAggregate.self,
            DeckPlayModeSettingsModel.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    static func makeContext() throws -> ModelContext {
        ModelContext(try makeInMemoryContainer())
    }
}

@MainActor
enum TestMutationFactory {
    static func flashcard(front: String, back: String) -> DraftCardContent {
        .flashcard(
            FlashcardCardContent(
                frontZone: .text(front),
                backZone: .text(back),
                frontType: .text,
                backType: .text
            )
        )
    }

    static func quiz(
        question: String,
        correctAnswers: [String],
        incorrectAnswers: [String] = [],
        explanation: String? = nil
    ) -> DraftCardContent {
        let correctChoices = correctAnswers.map {
            QuizChoiceDraft(contentZone: .text($0), isCorrect: true)
        }
        let incorrectChoices = incorrectAnswers.map {
            QuizChoiceDraft(contentZone: .text($0), isCorrect: false)
        }

        return .quiz(
            QuizCardContent(
                questionZone: .text(question),
                choices: correctChoices + incorrectChoices,
                explanationZone: explanation.map(ZoneModel.text),
                allowsMultipleCorrect: correctAnswers.count > 1
            )
        )
    }

    static func write(prompt: String, answer: String) -> DraftCardContent {
        let zone = ZoneModel.text(prompt)
        return .write(
            WriteCardContent(
                sourceZone: zone,
                blankSelection: .init(
                    zoneID: zone.id,
                    utf16Range: 0..<max(answer.utf16.count, 1),
                    omittedText: answer
                )
            )
        )
    }

    static func match(prompt: String, answer: String) -> DraftCardContent {
        .match(MatchCardContent(prompt: prompt, answer: answer))
    }

    static func makePersistedCard(
        content: DraftCardContent,
        cardNumber: Int,
        isPinned: Bool = false,
        creationSource: CardCreationSource = .manual,
        conversionMetadata: CardConversionMetadata? = nil
    ) -> CardModel {
        CardModel(
            content: content,
            cardNumber: cardNumber,
            isPinned: isPinned,
            creationSource: creationSource,
            conversionMetadata: conversionMetadata
        )
    }
}

extension ModelContext {
    @MainActor
    func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try fetch(FetchDescriptor<T>())
    }
}

@MainActor
enum TestAsyncHelpers {
    static func waitUntil(
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(20),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout

        while !condition() {
            if ContinuousClock.now >= deadline {
                XCTFail("Timed out waiting for async condition", file: file, line: line)
                return
            }
            try? await Task.sleep(for: pollInterval)
        }
    }
}

enum TestFileSystemFactory {
    static func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directoryURL
    }
}
