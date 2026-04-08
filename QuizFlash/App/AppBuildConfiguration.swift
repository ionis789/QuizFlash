//
//  AppBuildConfiguration.swift
//  QuizFlash
//
//  Compile-time build flavor helpers used to gate development-only UI.
//

import Foundation

nonisolated enum AppBuildFlavor: String, Sendable {
    case development
    case production

    var title: String {
        switch self {
        case .development:
            return "Development"
        case .production:
            return "Production"
        }
    }

    var showsDevelopmentTools: Bool {
        self == .development
    }
}

nonisolated enum AppBuildConfiguration {
    static let current: AppBuildFlavor = {
#if DEBUG
        .development
#else
        .production
#endif
    }()
}
