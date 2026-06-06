//
//  QuizModeViewModelEvaluationTests.swift
//  QuizFlashTests
//
//  Covers quiz scoring edge cases that depend on first-pass answer semantics.
//

import SwiftData
import XCTest
@testable import QuizFlash

@MainActor
final class QuizModeViewModelEvaluationTests: XCTestCase {
    func testPartialMultiAnswerWithoutWrongChoiceIsQueuedForRetryWithoutScoringWrong() throws {
        let fixture = try makeQuizFixture(
            choices: [
                QuizChoiceDraft(contentZone: .text("A"), isCorrect: true),
                QuizChoiceDraft(contentZone: .text("B"), isCorrect: true),
                QuizChoiceDraft(contentZone: .text("C"), isCorrect: false)
            ],
            allowsMultipleCorrect: true
        )
        var settings = QuizModeSettings()
        settings.answerValidation = .submit
        let viewModel = makeViewModel(deck: fixture.deck, settings: settings, card: fixture.playableCard)

        viewModel.selectChoice(fixture.playableCard.choices[0].id)
        viewModel.submitAnswer()

        XCTAssertTrue(viewModel.isEvaluated)
        XCTAssertNil(viewModel.lastEvaluationWasCorrect)
        XCTAssertEqual(viewModel.correctCount, 0)
        XCTAssertEqual(viewModel.wrongCount, 0)
        XCTAssertEqual(viewModel.wrongCards.map(\.id), [fixture.playableCard.id])
        XCTAssertEqual(viewModel.missedCorrectChoiceIDs, [fixture.playableCard.choices[1].id])
        XCTAssertTrue(viewModel.canRevealMissedCorrectChoices)

        viewModel.revealMissedCorrectChoices()

        XCTAssertEqual(viewModel.revealedMissedCorrectChoiceIDs, [fixture.playableCard.choices[1].id])
    }

    func testSingleAnswerCorrectAfterWrongFirstAttemptDoesNotScoreAsCorrect() throws {
        let fixture = try makeQuizFixture(
            choices: [
                QuizChoiceDraft(contentZone: .text("Correct"), isCorrect: true),
                QuizChoiceDraft(contentZone: .text("Wrong 1"), isCorrect: false),
                QuizChoiceDraft(contentZone: .text("Wrong 2"), isCorrect: false)
            ],
            allowsMultipleCorrect: false
        )
        var settings = QuizModeSettings()
        settings.answerValidation = .instantCheck
        let viewModel = makeViewModel(deck: fixture.deck, settings: settings, card: fixture.playableCard)

        viewModel.selectChoice(fixture.playableCard.choices[1].id)

        XCTAssertEqual(viewModel.correctCount, 0)
        XCTAssertEqual(viewModel.wrongCount, 1)
        XCTAssertEqual(viewModel.wrongCards.map(\.id), [fixture.playableCard.id])
        XCTAssertEqual(viewModel.missedCorrectChoiceIDs, [fixture.playableCard.choices[0].id])

        viewModel.selectChoice(fixture.playableCard.choices[0].id)

        XCTAssertEqual(viewModel.lastEvaluationWasCorrect, true)
        XCTAssertEqual(viewModel.correctCount, 0)
        XCTAssertEqual(viewModel.wrongCount, 1)
        XCTAssertEqual(viewModel.wrongCards.map(\.id), [fixture.playableCard.id])
    }

    private func makeViewModel(
        deck: DeckModel,
        settings: QuizModeSettings,
        card: QuizPlayableCard
    ) -> QuizModeViewModel {
        let viewModel = QuizModeViewModel(deck: deck, settings: settings)
        viewModel.cards = [card]
        viewModel.loadState = .ready
        return viewModel
    }

    private func makeQuizFixture(
        choices: [QuizChoiceDraft],
        allowsMultipleCorrect: Bool
    ) throws -> (deck: DeckModel, playableCard: QuizPlayableCard) {
        let context = try TestModelContainerFactory.makeContext()
        let deck = DeckModel(title: "Quiz", colorHex: "#111111")
        let card = CardModel(
            content: .quiz(
                QuizCardContent(
                    questionZone: .text("Question"),
                    choices: choices,
                    explanationZone: nil,
                    allowsMultipleCorrect: allowsMultipleCorrect
                )
            ),
            cardNumber: 1
        )

        context.insert(deck)
        context.insert(card)
        card.deck = deck
        deck.cards = [card]
        deck.cardCount = 1
        try context.save()

        return (
            deck,
            QuizPlayableCard(
                id: card.persistentModelID,
                cardNumber: card.cardNumber,
                interval: card.interval,
                questionZone: .text("Question"),
                choices: choices,
                explanationZone: nil,
                allowsMultipleCorrect: allowsMultipleCorrect
            )
        )
    }
}
