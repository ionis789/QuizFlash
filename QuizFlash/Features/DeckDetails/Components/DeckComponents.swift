//
//  DeckComponents.swift
//  QuizFlash
//
//  Created by Ion Socol on 08.02.2026.
//

import SwiftUI

// MARK: - 1. Deck Header View
struct DeckHeaderView: View {
    let deck: DeckModel
    var onEdit: () -> Void

    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? .blue
    }

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }


    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: deck.createdAt)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {

                ZStack {
                    Circle()
                        .fill(
                        LinearGradient(
                            colors: [deckColor.opacity(0.7), deckColor.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                        .frame(width: 56, height: 56)

                    Image(systemName: deck.icon.isEmpty ? "sparkles.rectangle.stack.fill" : deck.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                // Title & Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.title)
                        .font(.title.weight(.bold)).fontDesign(.rounded)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label("\(deck.cardCount)", systemImage: "rectangle.stack")
                        Text("•")
                        Text(formattedDate)
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Edit Button (Deck details)
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - 2. Play Modes View (Premium 2×2 Grid)
struct DeckPlayModesView: View {
    let deck: DeckModel
    var onPlay: () -> Void

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var isEmpty: Bool { deck.cardCount == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PLAY MODES")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 24)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                spacing: 16
            ) {
                PlayModeCard(
                    title: "Default",
                    subtitle: "Swipe review",
                    systemImage: "play.fill",
                    color: accentColor,
                    isAvailable: !isEmpty,
                    action: onPlay
                )
                PlayModeCard(
                    title: "Quiz",
                    subtitle: "Multi choice",
                    systemImage: "questionmark.square.dashed",
                    color: .purple,
                    isAvailable: !isEmpty,
                    action: onPlay
                )
                PlayModeCard(
                    title: "Learn",
                    subtitle: "Spaced rep",
                    systemImage: "brain.head.profile", // Switched to a more organic icon
                    color: .teal,
                    isAvailable: !isEmpty,
                    action: onPlay
                )
                PlayModeCard(
                    title: "Match",
                    subtitle: "Coming soon",
                    systemImage: "square.grid.2x2",
                    color: .gray,
                    isAvailable: false,
                    action: { }
                )
            }
                .padding(.horizontal, 20)
        }
    }
}

private struct PlayModeCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                // Top section: Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(isAvailable ? 0.15 : 0.05))
                        .frame(width: 44, height: 44) // Larger touch target for the icon

                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isAvailable ? color : color.opacity(0.30))
                }

                // Bottom section: Texts
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(isAvailable ? .primary : .tertiary)

                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(
                    Color.libraryDeckRow
                        .shadow(.inner(color: Color.white.opacity(0.15), radius: 1, x: 0, y: 0))
                )
            }
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        }
            .buttonStyle(.plain) // Prevent default dimming, handle custom if needed
        .disabled(!isAvailable)
        // Springy scale effect when pressed is natively handled by UI if you wrap in an animated button style,
        // but for now opacity handles the disabled state beautifully.
        .opacity(isAvailable ? 1.0 : 0.5)
    }
}
/// Pinned section header showing only the card count label.
/// Action buttons (add, menu) have been promoted to DeckActionOverlay so they
/// remain accessible at a fixed position regardless of scroll depth.
struct DeckSectionToolbar: View {
    let deck: DeckModel
    /// When `true` the deck title pill is visible — fade the label to avoid redundancy.
    var pillVisible: Bool = false

    var body: some View {
        HStack {
            Text("CARDS(\(deck.cardCount))")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            // Fade and slide the label away while the title pill is showing.
            .opacity(pillVisible ? 0 : 1)
                .offset(x: pillVisible ? -8 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pillVisible)
            Spacer()
        }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }
}

// MARK: - 5. Action Buttons Overlay (top-trailing)

/// Floating action buttons rendered as a top-trailing overlay on DeckContentView.
///
/// Mirrors the visual style of the back-button overlay (top-leading):
/// each button is a standalone capsule with ultraThinMaterial fill and an
/// accent-tinted overlay, matching the exact padding and height of the back button.
///
/// The ellipsis button tracks its own frame via onGeometryChange so that
/// DeckContentView can position the DeckMenuControls dropdown correctly
/// relative to the button regardless of device size or orientation.
struct DeckActionOverlay: View {
    let deck: DeckModel
    let isSelecting: Bool
    @Binding var isMenuExpanded: Bool
    @Binding var menuPosition: CGRect
    let menuTracker: MenuPositionTracker
    let onAdd: () -> Void
    let onStartSelection: () -> Void
    let onExport: () -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }
    /// True when the ellipsis button should render in its active (filled) state.
    private var isMenuActive: Bool { isSelecting || isMenuExpanded }

    var body: some View {
        HStack(spacing: 8) {
            addButton

            menuButton
                .scaleEffect(isMenuActive ? 1.1 : 1.0)
        }
    }

    // MARK: Add Button

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(width: 50, height: 50)
                .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .blur(radius: 10)
                        .mask(
                        Circle()
                            .stroke(lineWidth: 4)
                    )
                        .blendMode(.overlay)
                }
            }
        }
            .buttonStyle(.plain)
    }

    // MARK: Menu Button

    /// Ellipsis button that triggers DeckMenuControls.
    /// onGeometryChange feeds menuPosition so the dropdown is anchored to this button.
    private var menuButton: some View {
        Button {
            menuPosition = menuTracker.rect
            withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                isMenuExpanded.toggle()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .bold))
            // Active state: white icon on solid-accent background.
            // Inactive state: accent icon on tinted-material background.
            .foregroundStyle(isMenuActive ? .white : accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(width: 50, height: 50)
                .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .blur(radius: 10)
                        .mask(
                        Circle()
                            .stroke(lineWidth: 4)
                    )
                        .blendMode(.overlay)
                }
            }
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isMenuActive)
        }
            .buttonStyle(.plain)
        // Track the button's global frame so menuOverlay can place the dropdown
        // directly below (or above) this button without hard-coded offsets.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newValue in
            menuTracker.rect = newValue
        }
    }
}

// MARK: - 4. Selection Bottom Bar (Floating)
struct DeckSelectionBottomBar: View {
    let selectedCount: Int
    var onDone: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDone) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                HStack(spacing: 8) {
                    Text("Delete(\(selectedCount))")
                        .fontWeight(.semibold)
                }
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
                .disabled(selectedCount == 0)
                .opacity(selectedCount == 0 ? 0.5 : 1)
        }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, 20)
    }
}
