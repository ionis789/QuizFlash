//
//  SettingsView.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            // Testing tabMenu background glass feature above a list of something
            List {

                Section {
                    VStack(alignment: .center) {
                        Circle().frame(width: 60, height: 60).foregroundStyle(.blue)
                        Text("Ion Socol").font(.caption.bold())
                    }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }

                Section {
                    NavigationLink("Notifications and Sounds", destination: Text("Notifications"))
                    NavigationLink("Data and Storage", destination: Text("Data"))
                    NavigationLink("Appearance", destination: Text("Dark"))
                }
                Section {
                    NavigationLink("Notifications and Sounds", destination: Text("Notifications"))
                    NavigationLink("Data and Storage", destination: Text("Data"))
                    NavigationLink("Appearance", destination: Text("Dark"))
                }
                Section {
                    NavigationLink("Notifications and Sounds", destination: Text("Notifications"))
                    NavigationLink("Data and Storage", destination: Text("Data"))
                    NavigationLink("Appearance", destination: Text("Dark"))
                }

                Section {
                    Button("Log Out") {
                        authManager.logout()
                    }
                        .foregroundStyle(.red)
                }
            }
                .navigationTitle("Settings")
                .listStyle(.insetGrouped)
                .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: 90)
            }

        }
    }
}


#Preview {
    SettingsView()
}
