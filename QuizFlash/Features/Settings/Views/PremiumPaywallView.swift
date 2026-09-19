//
//  PremiumPaywallView.swift
//  QuizFlash
//


import RevenueCat
import SwiftUI

struct PremiumPaywallView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(ThemeManager.self) private var themeManager

    let onPurchaseCompleted: () -> Void

    @State private var selectedPeriod: SubscriptionBillingPeriod = .annual
    @State private var errorMessage: String?

    private let privacyURL = URL(string: "https://quizflash.app/privacy")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                header
                benefits

                if subscriptionManager.isPremium {
                    activeSubscriptionContent
                } else {
                    planSelector
                    purchaseButton
                    restoreButton
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                legalLinks
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.small)
            .padding(.bottom, UIConstants.Spacing.huge)
        }
        .scrollIndicators(.hidden)
        .task {
            guard !subscriptionManager.isPremium,
                  subscriptionManager.monthlyPackage == nil,
                  subscriptionManager.annualPackage == nil else { return }
            await loadOfferings()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(themeManager.accentColor.color)
                .frame(width: 54, height: 54)
                .background(themeManager.accentColor.color.opacity(0.14), in: Circle())

            Text(localized("QuizFlash Premium"))
                .font(.title2.weight(.bold))
                .foregroundStyle(themeManager.textPrimary)

            Text(localized("Create larger decks and keep generating with a rolling AI budget."))
                .font(.body.weight(.medium))
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            benefit(icon: "rectangle.stack.fill", text: localized("Up to 100 cards per generation"))
            benefit(icon: "sparkles", text: localized("AI usage included"))
            benefit(icon: "arrow.triangle.2.circlepath", text: localized("The limit renews continuously"))
        }
        .padding(UIConstants.Spacing.standard)
        .background(themeManager.roleColor(.widgetSurfaceFill), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
    }

    private func benefit(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(themeManager.accentColor.color)
                .frame(width: UIConstants.Size.iconStandard)

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planSelector: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            planButton(
                period: .monthly,
                title: localized("Monthly"),
                package: subscriptionManager.monthlyPackage
            )
            planButton(
                period: .annual,
                title: localized("Yearly"),
                package: subscriptionManager.annualPackage
            )
        }
    }

    private func planButton(
        period: SubscriptionBillingPeriod,
        title: String,
        package: Package?
    ) -> some View {
        Button {
            selectedPeriod = period
            errorMessage = nil
        } label: {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text(title)
                    .font(.headline.weight(.bold))
                Text(package?.storeProduct.localizedPriceString ?? localized("Unavailable"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedPeriod == period ? themeManager.textPrimary : themeManager.textSecondary)
                Text(period == .annual ? localized("Billed annually") : localized("Billed monthly"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(themeManager.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UIConstants.Spacing.standard)
            .background(
                selectedPeriod == period
                    ? themeManager.accentColor.color.opacity(0.16)
                    : themeManager.roleColor(.widgetSurfaceFill),
                in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                    .strokeBorder(
                        selectedPeriod == period ? themeManager.accentColor.color : .clear,
                        lineWidth: 2
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(package == nil)
        .opacity(package == nil ? 0.62 : 1)
    }

    private var purchaseButton: some View {
        Button {
            Task { @MainActor in
                errorMessage = nil
                do {
                    if try await subscriptionManager.purchase(selectedPeriod) {
                        onPurchaseCompleted()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } label: {
            HStack(spacing: UIConstants.Spacing.small) {
                if subscriptionManager.isPurchaseInProgress {
                    ProgressView()
                        .tint(.white)
                }
                Text(purchaseButtonTitle)
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: UIConstants.Size.buttonHeight)
            .background(themeManager.accentColor.color, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selectedPackage == nil || subscriptionManager.isPurchaseInProgress)
        .opacity(selectedPackage == nil ? 0.55 : 1)
    }

    private var restoreButton: some View {
        Button(localized("Restore Purchases")) {
            Task { @MainActor in
                errorMessage = nil
                do {
                    try await subscriptionManager.restorePurchases()
                    if subscriptionManager.isPremium {
                        onPurchaseCompleted()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(themeManager.accentColor.color)
        .frame(maxWidth: .infinity)
        .disabled(subscriptionManager.isPurchaseInProgress)
    }

    private var activeSubscriptionContent: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Label(localized("Premium is active"), systemImage: "checkmark.seal.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.green)

            Link(destination: manageSubscriptionsURL) {
                Text(localized("Manage Subscription"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(themeManager.accentColor.color)
            }
        }
    }

    private var legalLinks: some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Text(localized("Subscriptions renew automatically unless canceled at least 24 hours before the current period ends."))
                .font(.caption)
                .foregroundStyle(themeManager.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: UIConstants.Spacing.large) {
                Link(localized("Terms of Use"), destination: termsURL)
                Link(localized("Privacy Policy"), destination: privacyURL)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(themeManager.accentColor.color)
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedPackage: Package? {
        selectedPeriod == .monthly
            ? subscriptionManager.monthlyPackage
            : subscriptionManager.annualPackage
    }

    private var purchaseButtonTitle: String {
        guard let selectedPackage else {
            return subscriptionManager.isLoadingOfferings
                ? localized("Loading Plans…")
                : localized("Subscriptions Unavailable")
        }
        return "\(localized("Continue")) — \(selectedPackage.storeProduct.localizedPriceString)"
    }

    private func loadOfferings() async {
        errorMessage = nil
        do {
            try await subscriptionManager.loadOfferings()
            if subscriptionManager.annualPackage == nil {
                selectedPeriod = .monthly
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: appPreferences.resolvedLocale)
    }
}
