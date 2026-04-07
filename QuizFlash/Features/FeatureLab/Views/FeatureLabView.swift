//
//  FeatureLabView.swift
//  QuizFlash
//
//  Dedicated playground for high-risk feature experiments before app-wide rollout.
//

import SwiftUI

struct FeatureLabView: View {
    private let entries: [FeatureLabEntry] = [
        .init(
            title: "Context Menu Lab",
            subtitle: "Experiment with custom context menu positioning, preview motion, and test surfaces in isolation.",
            icon: "ellipsis.rectangle",
            tint: .red,
            route: .contextMenu
        )
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                    Text("Experiments")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    ForEach(entries) { entry in
                        NavigationLink(value: entry.route) {
                            FeatureLabEntryCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Size.bottomChromeBarHeight + 80)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Labs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FeatureLabEntry: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let route: FeatureLabRoute
}

private struct FeatureLabEntryCard: View {
    let entry: FeatureLabEntry

    var body: some View {
        HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                    .fill(entry.tint.opacity(0.18))
                    .frame(width: 56, height: 56)

                Image(systemName: entry.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(entry.tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(entry.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .padding(UIConstants.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.maximum, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
