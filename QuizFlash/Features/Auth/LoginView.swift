//
//  LoginView.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "bolt.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)
            
            Text("QuizFlash")
                .font(.largeTitle.bold())
            
            Text("Învață rapid și eficient.")
                .foregroundStyle(.gray)
            
            Spacer()
            
            Button(action: {
                authManager.loginWithGoogle()
            }) {
                HStack {
                    Image(systemName: "globe")
                    Text("Sign in with Google")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }
}
