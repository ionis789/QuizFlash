//
//  ReviewModels.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.02.2026.
//

import Foundation
import SwiftData

// MARK: - Review Difficulty
enum ReviewDifficulty: Int, Codable {
    case again = 0
    case hard = 1
    case good = 2
    case easy = 3
}

// MARK: - Review Event (Istoricul Incoruptibil)
@Model
class ReviewEvent {
    var timestamp: Date = Date()
    var timeSpent: TimeInterval // Cât timp s-a gândit userul
    var difficultyRaw: Int // Salvăm rawValue pentru enum
    var xpAwarded: Int
    
    // Relație inversă către card
    var card: CardModel?
    
    var difficulty: ReviewDifficulty {
        get { ReviewDifficulty(rawValue: difficultyRaw) ?? .good }
        set { difficultyRaw = newValue.rawValue }
    }
    
    init(timeSpent: TimeInterval, difficulty: ReviewDifficulty, xpAwarded: Int) {
        self.timeSpent = timeSpent
        self.difficultyRaw = difficulty.rawValue
        self.xpAwarded = xpAwarded
        self.timestamp = Date()
    }
}
