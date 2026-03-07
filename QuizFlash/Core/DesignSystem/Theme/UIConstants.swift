//
//  UIConstants.swift.swift
//  QuizFlash
//
//  Created by Ion Socol on 17.02.2026.
//

import Foundation
import CoreGraphics

enum UIConstants {
    
    // MARK: - Layout & Spacing
    enum Spacing {
        static let tiny: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let standard: CGFloat = 16
        static let large: CGFloat = 20
        static let extraLarge: CGFloat = 24
        static let huge: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let card: CGFloat = 16
        static let large: CGFloat = 22
        static let maximum: CGFloat = 32
    }
    
    // MARK: - Shadows
    enum Shadow {
        static let lightRadius: CGFloat = 4
        static let mediumRadius: CGFloat = 12
        static let heavyRadius: CGFloat = 24
        
        static let yOffset: CGFloat = 4
    }
    
    // MARK: - Icon & Button Sizes
    enum Size {
        static let iconSmall: CGFloat = 16
        static let iconStandard: CGFloat = 24
        static let iconLarge: CGFloat = 32
        
        static let buttonHeight: CGFloat = 50
        static let cardMinHeight: CGFloat = 120
    }
}
