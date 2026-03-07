//
//  SettingsView.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//

import SwiftUI
import SwiftData

// MARK: - Settings View
struct SettingsView: View {
    // MARK: - Environment & State
    @Environment(AuthManager.self) var authManager
    /// Enables view dismissal triggered purely by the custom edge swipe gesture.
    @Environment(\.dismiss) private var dismiss
    
    @State private var themeManager = ThemeManager.shared
    @Query private var decks: [DeckModel]

    var body: some View {
        // We render the List directly as the root view for a completely clean layout.
        List {
            Section {
                HStack(spacing: 14) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [themeManager.accentColor.color.opacity(0.7), themeManager.accentColor.color.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Text("IS")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ion Socol")
                            .font(.body.weight(.semibold))
                        Text("QuizFlash User")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                NavigationLink {
                    AccentColorPickerView()
                } label: {
                    HStack {
                        Label("Accent Color", systemImage: "paintpalette")

                        Spacer()

                        Circle()
                            .fill(themeManager.accentColor.color)
                            .frame(width: 22, height: 22)
                    }
                }

                NavigationLink {
                    SettingsCardAppearanceView()
                } label: {
                    Label("Card Appearance", systemImage: "rectangle.on.rectangle")
                }

                NavigationLink {
                    Text("Appearance Settings")
                } label: {
                    Label("Appearance", systemImage: "moon.fill")
                }
            } header: {
                Text("Appearance")
            }

            Section {
                NavigationLink {
                    Text("Notifications")
                    // If these child views also need to be entirely clean,
                    // they will need the same .toolbar(.hidden) and .swipeBack setup.
                } label: {
                    Label("Notifications", systemImage: "bell.fill")
                }

                NavigationLink {
                    StorageInfoView(decks: decks)
                } label: {
                    Label("Data & Storage", systemImage: "externaldrive.fill")
                }
            } header: {
                Text("Preferences")
            }

            Section {
                NavigationLink {
                    Text("Help")
                } label: {
                    Label("Help & Support", systemImage: "questionmark.circle")
                }

                NavigationLink {
                    Text("About")
                } label: {
                    Label("About QuizFlash", systemImage: "info.circle")
                }
            } header: {
                Text("About")
            }

            Section {
                Button {
                    authManager.logout()
                } label: {
                    HStack {
                        Spacer()
                        Text("Log Out")
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 90)
        }
        // Force hide the native navigation bar to keep the screen entirely clean
        .toolbar(.hidden, for: .navigationBar)
        // Bind the custom fluid gesture directly to the view's dismiss action
        .swipeBack {
            dismiss()
        }
    }
}

// MARK: - Accent Color Picker View
struct AccentColorPickerView: View {
    // MARK: - Environment & State
    @Environment(\.dismiss) private var dismiss
    @State private var themeManager = ThemeManager.shared

    private let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 100), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Preview card
                VStack(spacing: 12) {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        // Sample icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [themeManager.accentColor.color.opacity(0.7), themeManager.accentColor.color.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 48, height: 48)

                            Image(systemName: "book.closed.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sample Deck")
                                .font(.body.weight(.semibold))
                            Text("10 cards")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)

                // Color grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose Color")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AccentColorOption.allCases) { option in
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    themeManager.accentColor = option
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(option.color)
                                            .frame(width: 50, height: 50)
                                            .shadow(color: option.color.opacity(0.4), radius: 6, y: 3)

                                        if themeManager.accentColor == option {
                                            Image(systemName: "checkmark")
                                                .font(.body.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }

                                    Text(option.rawValue)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(themeManager.accentColor == option ? .primary : .secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // Keep the UI fully immersive by hiding the navigation bar
        .toolbar(.hidden, for: .navigationBar)
        // Only allow dismissing via the custom swipe back modifier
        .swipeBack {
            dismiss()
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager())
        .modelContainer(for: [DeckModel.self, CardModel.self], inMemory: true)
}
