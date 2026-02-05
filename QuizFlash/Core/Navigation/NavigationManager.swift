//
//  NavigationManager.swift
//  QuizFlash
//
//  Created by Ion Socol on 01.02.2026.
//

import SwiftUI
import SwiftData
import Combine

class NavigationManager: ObservableObject {
    
    @Published var libraryPath = NavigationPath()
    
    
    func popToRoot() {
        libraryPath = NavigationPath()
    }
}
