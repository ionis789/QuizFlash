//
//  GamificationModels.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.02.2026.
//
import Foundation
import SwiftData

// MARK: - User Profile (Global Gamification Core)
@Model
class UserProfile {
    var totalXP: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastActiveDate: Date?
    
    // Nivelul este calculat dinamic (ex: creștem în nivel la fiecare 500 XP)
    // Poți schimba formula mai târziu dacă vrei să fie exponențială (stil RPG)
    var level: Int {
        return (totalXP / 500) + 1
    }
    
    init(totalXP: Int = 0, currentStreak: Int = 0, longestStreak: Int = 0, lastActiveDate: Date? = nil) {
        self.totalXP = totalXP
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastActiveDate = lastActiveDate
    }
}

// MARK: - Daily Activity Log (The Heatmap Feeder)
// Acest model este optimizat. Când desenăm calendarul, vom trage doar aceste obiecte.
@Model
class DailyActivityLog {
    @Attribute(.unique) var dateString: String // Format: "YYYY-MM-DD" pentru căutare exactă
    var date: Date
    var cardsReviewed: Int = 0
    var newCardsLearned: Int = 0
    var xpEarnedToday: Int = 0
    var dailyGoal: Int = 50 // Obiectivul zilnic (îl poți face setabil din Settings mai târziu)
    
    // Dacă userul și-a atins scopul pe ziua respectivă, se colorează intens în heatmap
    var isPerfectDay: Bool {
        return cardsReviewed >= dailyGoal
    }
    
    init(date: Date = Date(), dailyGoal: Int = 50) {
        self.date = date
        // Creăm un string unic pentru ziua de azi ca să nu avem duplicate per zi
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateString = formatter.string(from: date)
        
        self.dailyGoal = dailyGoal
    }
}
