//
//  FeatureLabView.swift
//  QuizFlash
//
//  Dedicated playground for high-risk feature experiments before app-wide rollout.
//

import SwiftUI

struct FeatureLabView: View {
    private var entries: [FeatureLabRoute] {
        FeatureLabRoute.visibleRoutes(in: .current)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                    Text("Experiments")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)

                    ForEach(entries, id: \.self) { route in
                        NavigationLink(value: route) {
                            FeatureLabEntryCard(route: route)
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

private struct FeatureLabEntryCard: View {
    let route: FeatureLabRoute

    var body: some View {
        HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                    .fill(route.tint.opacity(0.18))
                    .frame(width: 56, height: 56)

                Image(systemName: route.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(route.tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(route.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)

                Text(route.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.compact.right")
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
