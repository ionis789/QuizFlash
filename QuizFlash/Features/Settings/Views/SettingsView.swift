//
//  SettingsView.swift
//  QuizFlash
//
//  Main settings hub for QuizFlash.
//

import SwiftData
import SwiftUI

private let kSettingsChromeSpace = "SettingsChromeSpace"
private let kSettingsInfoChromeSpace = "SettingsInfoChromeSpace"

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager
    @Environment(CardAppearancePreferences.self) private var cardAppearancePreferences
    @Environment(\.dismiss) private var dismiss

    @State private var keyboardMonitor = KeyboardMonitor.shared
    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0
    @Query private var decks: [DeckModel]
    @Query private var userProfiles: [UserProfile]

    let allowsSwipeBack: Bool

    init(allowsSwipeBack: Bool = false) {
        self.allowsSwipeBack = allowsSwipeBack
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                    screenTitle
                    profileCard
                    personalizationSection
                    studyDefaultsSection
                    workflowSection
                    supportSection
                    accountSection
                }
                .tabBarAutoHideOnScroll()
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, UIConstants.Spacing.large)
                .padding(.bottom, keyboardMonitor.isVisible ? UIConstants.Spacing.large : UIConstants.Spacing.huge * 1.5)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: navigationBarHeight + UIConstants.Spacing.small)
            }

            navigationBar
        }
        .coordinateSpace(name: kSettingsChromeSpace)
        .background(themeManager.groupedScreenBackground)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: keyboardMonitor.isVisible ? 0 : 40)
        }
        .swipeBack(enabled: allowsSwipeBack) {
            dismiss()
        }
    }

    private var screenTitle: some View {
        LargeScreenTitle(title: "Settings")
            .collapsibleTitleRevealAnchor(
                in: kSettingsChromeSpace,
                navigationBarBottomY: navigationBarBottomY,
                revealClearance: SettingsChromeMetrics.pillRevealClearance,
                isVisible: $isCollapsedTitleVisible
            )
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeManager.accentColor.color.opacity(0.84),
                                    themeManager.accentColor.color.opacity(0.34)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)

                    Image(systemName: "person.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("QuizFlash User")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text("Level \(userLevel)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                premiumBadge
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: UIConstants.Spacing.small) {
                    profileMetric(icon: "bolt.fill", title: "Lvl \(userLevel)")
                    profileMetric(icon: "flame.fill", title: "\(currentStreak) streak")
                    profileMetric(icon: "square.stack.3d.up.fill", title: "\(decks.count) decks")
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    HStack(spacing: UIConstants.Spacing.small) {
                        profileMetric(icon: "bolt.fill", title: "Lvl \(userLevel)")
                        profileMetric(icon: "flame.fill", title: "\(currentStreak) streak")
                    }

                    profileMetric(icon: "square.stack.3d.up.fill", title: "\(decks.count) decks")
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.maximum)
    }

    private var premiumBadge: some View {
        Text(isPremiumUser ? "Premium" : "Free")
            .font(.caption.weight(.bold))
            .foregroundStyle(isPremiumUser ? .yellow : .secondary)
            .padding(.horizontal, UIConstants.Spacing.standard)
            .padding(.vertical, 6)
            .background(
                (isPremiumUser ? Color.yellow.opacity(0.14) : Color.white.opacity(0.06)),
                in: Capsule()
            )
    }

    private func profileMetric(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.accentColor.color.opacity(0.92))

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UIConstants.Spacing.standard)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    private var personalizationSection: some View {
        SettingsSectionCard(
            title: "Personalization",
            subtitle: nil
        ) {
            NavigationLink {
                AccentColorPickerView()
            } label: {
                SettingsNavigationRow(
                    icon: "paintpalette.fill",
                    tint: themeManager.accentColor.color,
                    title: "Accent Color",
                    detail: nil,
                    value: themeManager.accentColor.rawValue
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            NavigationLink {
                SettingsCardAppearanceView()
            } label: {
                SettingsNavigationRow(
                    icon: "rectangle.on.rectangle",
                    tint: .cyan,
                    title: "Card Appearance",
                    detail: nil,
                    value: currentCardAppearanceTitle
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var studyDefaultsSection: some View {
        SettingsSectionCard(
            title: "Study Defaults",
            subtitle: nil
        ) {
            NavigationLink {
                AppPreferencesSettingsView()
            } label: {
                SettingsNavigationRow(
                    icon: "gearshape.2.fill",
                    tint: .blue,
                    title: "App Defaults",
                    detail: nil,
                    value: appPreferences.weekStartDay.title
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            NavigationLink {
                PlayModeDefaultsSettingsView(mode: .flashcards)
            } label: {
                SettingsNavigationRow(
                    icon: SettingsStudyModeKind.flashcards.systemImage,
                    tint: SettingsStudyModeKind.flashcards.tint,
                    title: "Flashcards",
                    detail: nil,
                    value: flashcardsSummary
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            NavigationLink {
                PlayModeDefaultsSettingsView(mode: .quiz)
            } label: {
                SettingsNavigationRow(
                    icon: SettingsStudyModeKind.quiz.systemImage,
                    tint: SettingsStudyModeKind.quiz.tint,
                    title: "Quiz",
                    detail: nil,
                    value: quizSummary
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            NavigationLink {
                PlayModeDefaultsSettingsView(mode: .match)
            } label: {
                SettingsNavigationRow(
                    icon: SettingsStudyModeKind.match.systemImage,
                    tint: SettingsStudyModeKind.match.tint,
                    title: "Match",
                    detail: nil,
                    value: matchSummary
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            NavigationLink {
                PlayModeDefaultsSettingsView(mode: .write)
            } label: {
                SettingsNavigationRow(
                    icon: SettingsStudyModeKind.write.systemImage,
                    tint: SettingsStudyModeKind.write.tint,
                    title: "Write",
                    detail: nil,
                    value: writeSummary
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var workflowSection: some View {
        SettingsSectionCard(
            title: "Data & Tools",
            subtitle: nil
        ) {
            NavigationLink {
                StorageInfoView(decks: decks)
            } label: {
                SettingsNavigationRow(
                    icon: "externaldrive.fill",
                    tint: .orange,
                    title: "Data & Storage",
                    detail: nil,
                    value: "\(decks.count) Decks"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var supportSection: some View {
        SettingsSectionCard(
            title: "About",
            subtitle: nil
        ) {
            NavigationLink {
                SettingsInfoDetailView(
                    title: "Help & Support",
                    icon: "questionmark.circle.fill",
                    tint: .teal,
                    message: "Support content can live here later."
                )
            } label: {
                SettingsNavigationRow(
                    icon: "questionmark.circle.fill",
                    tint: .teal,
                    title: "Help & Support",
                    detail: nil,
                    value: nil
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            NavigationLink {
                SettingsInfoDetailView(
                    title: "About QuizFlash",
                    icon: "info.circle.fill",
                    tint: .blue,
                    message: "Version, credits, and release notes can live here."
                )
            } label: {
                SettingsNavigationRow(
                    icon: "info.circle.fill",
                    tint: .blue,
                    title: "About QuizFlash",
                    detail: nil,
                    value: nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var accountSection: some View {
        SettingsSectionCard(
            title: "Account",
            subtitle: nil
        ) {
            Button {
                authManager.logout()
            } label: {
                HStack(spacing: UIConstants.Spacing.medium) {
                    ZStack {
                        RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                            .fill(Color.red.opacity(0.12))
                            .frame(width: 40, height: 40)

                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.red)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Log Out")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)

                        Text("Sign out of the current QuizFlash session on this device.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var navigationBar: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: kSettingsChromeSpace,
            onHeightChange: { navigationBarHeight = $0 },
            onBottomChange: { navigationBarBottomY = $0 }
        ) {
            if allowsSwipeBack {
                ChromeCircleIconButton(systemName: "chevron.left") {
                    dismiss()
                }
            } else {
                ChromeCirclePlaceholder()
            }
        } center: { maxWidth in
            CollapsibleTitlePill(
                title: "Settings",
                maxWidth: maxWidth,
                isVisible: isCollapsedTitleVisible
            )
        } trailing: {
            ChromeCirclePlaceholder()
        }
    }

    private var currentCardAppearanceTitle: String {
        cardAppearancePreferences.cardContentMode.label
    }

    private var flashcardsSummary: String {
        "\(appPreferences.flashcardsProgressStyle.title) Progress"
    }

    private var quizSummary: String {
        appPreferences.quizAutoAdvanceCorrectAnswers ? "Auto Advance" : "Manual Pace"
    }

    private var matchSummary: String {
        appPreferences.matchShowsRoundCountdown ? "Countdown On" : "Countdown Off"
    }

    private var writeSummary: String {
        appPreferences.writeAutoFocusesAnswerField ? "Auto Focus" : "Manual Focus"
    }

    private var profile: UserProfile? {
        userProfiles.first
    }

    private var userLevel: Int {
        profile?.level ?? 1
    }

    private var currentStreak: Int {
        profile?.currentStreak ?? 0
    }

    private var isPremiumUser: Bool {
        false
    }
}

// MARK: - Accent Color Picker View

struct AccentColorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    private let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 100), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 12) {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
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
        .appScreenBackground(.grouped)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack {
            dismiss()
        }
    }
}

// MARK: - Settings Info Detail View

private struct SettingsInfoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0

    let title: String
    let icon: String
    let tint: Color
    let message: String

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                    LargeScreenTitle(title: title)
                        .collapsibleTitleRevealAnchor(
                            in: kSettingsInfoChromeSpace,
                            navigationBarBottomY: navigationBarBottomY,
                            revealClearance: SettingsChromeMetrics.pillRevealClearance,
                            isVisible: $isCollapsedTitleVisible
                        )

                    SettingsInfoCard(
                        icon: icon,
                        tint: tint,
                        text: message
                    )

                    SettingsInfoCard(
                        icon: "clock.arrow.circlepath",
                        tint: themeManager.accentColor.color,
                        text: "This destination is now organized and visually aligned with the rest of Settings, even though the underlying support content can be expanded later."
                    )
                }
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, UIConstants.Spacing.large)
                .padding(.bottom, UIConstants.Spacing.huge)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: navigationBarHeight + UIConstants.Spacing.small)
            }

            CollapsibleTitleNavigationBar(
                coordinateSpaceName: kSettingsInfoChromeSpace,
                onHeightChange: { navigationBarHeight = $0 },
                onBottomChange: { navigationBarBottomY = $0 }
            ) {
                ChromeCircleIconButton(systemName: "chevron.left") {
                    dismiss()
                }
            } center: { maxWidth in
                CollapsibleTitlePill(
                    title: title,
                    maxWidth: maxWidth,
                    isVisible: isCollapsedTitleVisible
                )
            } trailing: {
                ChromeCirclePlaceholder()
            }
        }
        .coordinateSpace(name: kSettingsInfoChromeSpace)
        .background(themeManager.groupedScreenBackground)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager.shared)
        .environment(ThemeManager.shared)
        .environment(AppPreferences.shared)
        .environment(CardAppearancePreferences.shared)
        .modelContainer(for: [DeckModel.self, CardModel.self], inMemory: true)
}
