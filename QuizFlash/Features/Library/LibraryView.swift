//
//  Library.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//
import SwiftUI

struct LibraryView: View {
    
    @StateObject private var customManager =  CustomManager()
    
    var body: some View {
        VStack {
            Text("Home")
                .font(.largeTitle.bold())
            
            
            Button {
                customManager.toogleLogin()
            } label: {
                Text(customManager.isLoggedIn ? "Logged" : "Not logged")
            }
        }
      
    }
}
