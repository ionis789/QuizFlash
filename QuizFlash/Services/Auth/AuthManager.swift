//
//  AuthManager.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//

import SwiftUI

@Observable
class AuthManager {



    var isAuthenticated: Bool {
        didSet {
            UserDefaults.standard.set(isAuthenticated, forKey: "is_authenticated")
        }
    }

    init() {
        self.isAuthenticated = UserDefaults.standard.bool(forKey: "is_authenticated")
    }

    func loginWithGoogle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                self.isAuthenticated = true
            }
        }
    }

    func logout() {
        withAnimation {
            self.isAuthenticated = false
        }
    }
}
