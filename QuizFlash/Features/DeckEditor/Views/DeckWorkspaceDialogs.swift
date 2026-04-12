//
//  DeckWorkspaceDialogs.swift
//  QuizFlash
//

import SwiftUI

struct AISourcePreparationOverlay: View {
    let state: AISourcePreparationState
    let accent: Color

    @State var animatePulse = false

    var title: String {
        switch state {
        case .photos:
            return "Preparing images"
        case .pdf:
            return "Preparing document"
        }
    }

    var subtitle: String {
        switch state {
        case .photos(let itemCount):
            return itemCount == 1
                ? "Running OCR and building the AI preview."
                : "Running OCR across \(itemCount) images and building the AI preview."
        case .pdf:
            return "Reading pages, generating thumbnails and checking text quality."
        }
    }

    var eyebrow: String {
        switch state {
        case .photos(let itemCount):
            return itemCount == 1 ? "1 image selected" : "\(itemCount) images selected"
        case .pdf:
            return "PDF selected"
        }
    }

    var symbolName: String {
        switch state {
        case .photos:
            return "photo.on.rectangle.angled"
        case .pdf:
            return "doc.text.viewfinder"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.14))
                        .frame(width: 46, height: 46)
                        .scaleEffect(animatePulse ? 1.04 : 0.96)

                    Circle()
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                        .frame(width: 46, height: 46)

                    Image(systemName: symbolName)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                        .lineLimit(1)

                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: UIConstants.Spacing.small)

                AIPreparationDots(tint: accent)
            }

            Text(subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AIPreparationIndeterminateBar(tint: accent)
        }
        .padding(20)
        .frame(maxWidth: 360, alignment: .leading)
        .flashcardStyle(cornerRadius: 30, surfaceRole: .widget)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                animatePulse = true
            }
        }
    }
}

struct AIPreparationDots: View {
    let tint: Color

    @State var activeIndex = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(tint.opacity(activeIndex == index ? 0.95 : 0.28))
                    .frame(width: activeIndex == index ? 7 : 6, height: activeIndex == index ? 7 : 6)
                    .offset(y: activeIndex == index ? -1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: activeIndex)
            }
        }
        .frame(width: 34, height: 18)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                activeIndex = (activeIndex + 1) % 3
            }
        }
    }
}

struct AIPreparationIndeterminateBar: View {
    let tint: Color

    @State var animateIndicator = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(uiColor: .tertiarySystemFill))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                tint.opacity(0.75),
                                Color.white.opacity(0.16)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(48, proxy.size.width * 0.28))
                    .offset(x: animateIndicator ? proxy.size.width * 0.72 : 0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animateIndicator)
            }
        }
        .frame(height: 6)
        .onAppear { animateIndicator = true }
    }
}

struct DeckWorkspaceSelectionBottomBar: View {
    let selectedCount: Int
    let allSelected: Bool
    let onDone: () -> Void
    let onToggleSelectAll: () -> Void
    let onDelete: () -> Void

    var hasSelection: Bool {
        selectedCount > 0
    }

    var selectionSummary: String {
        if selectedCount == 0 {
            return "Tap cards"
        }
        return selectedCount == 1 ? "1 selected" : "\(selectedCount) selected"
    }

    var summaryTint: Color {
        selectedCount == 0 ? .secondary : .primary
    }

    var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    var body: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            SelectionToolbarCapsuleButton(
                action: onDone,
                accessibilityLabel: "Done selecting draft cards"
            ) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .layoutPriority(1)

            Text(selectionSummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(summaryTint)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .monospacedDigit()
                .frame(width: 118, alignment: .leading)

            SelectionToolbarTextButton(
                title: allSelected ? "Clear" : "Select All",
                accessibilityLabel: allSelected ? "Clear all selected cards" : "Select all cards",
                tint: allSelected ? .primary : accent,
                action: onToggleSelectAll
            )

            Spacer(minLength: 0)

            SelectionToolbarIconButton(
                isEnabled: hasSelection,
                accessibilityLabel: "Delete \(selectedCount) selected card\(selectedCount == 1 ? "" : "s")",
                action: onDelete
            ) {
                Image(systemName: "trash")
                    .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                    .foregroundStyle(hasSelection ? Color.red : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
