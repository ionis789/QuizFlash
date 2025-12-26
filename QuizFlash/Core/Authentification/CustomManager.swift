//
//  CustomManager.swift
//  QuizFlash
//
//  Created by Ion Socol on 26.12.2025.
//

import SwiftUI
import Combine

class CustomManager: ObservableObject {
    var isLoggedIn:Bool = false
    
    func toogleLogin() {
        objectWillChange.send()
        isLoggedIn.toggle()
    }
}
