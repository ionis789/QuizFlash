//
//  QuizFlashLog.swift
//  QuizFlash
//
//  Shared structured logging helpers for QuizFlash categories.
//

import Foundation
import OSLog

enum QuizFlashLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "QuizFlash"

    static func make(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
