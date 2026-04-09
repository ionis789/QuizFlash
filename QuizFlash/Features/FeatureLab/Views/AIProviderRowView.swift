//
//  AIProviderRowView.swift
//  QuizFlash
//
//  Development-only AI provider profile row used inside labs.
//

import SwiftUI

// MARK: - AI Provider Row

struct AIProviderRowView: View {
    let profile: AIProviderProfile
    let isActive: Bool
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.standard) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.trimmedName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(profile.endpointDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isActive {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Text: \(profile.trimmedTextModel)")
                Text("Vision: \(profile.trimmedVisionModel)")
                Text("Token: \(profile.maskedAPIKey)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: UIConstants.Spacing.small) {
                Button(action: onUse) {
                    Text(isActive ? "In Use" : "Use This")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                                .fill(isActive ? Color.accentColor.opacity(0.16) : Color.accentColor)
                        )
                        .foregroundStyle(isActive ? Color.accentColor : .white)
                }
                .buttonStyle(.plain)
                .disabled(isActive)

                NavigationLink {
                    AIProviderEditorView(initialProfile: profile, isNewProfile: false)
                } label: {
                    Text("Edit")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(UIConstants.Spacing.standard)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
