//
//  SettingsView.swift
//  QuizFlash
//
//  Main settings hub for QuizFlash.
//

import SwiftData
import SwiftUI
import PhotosUI
import UIKit

private let kSettingsChromeSpace = "SettingsChromeSpace"
// MARK: - Settings View

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var keyboardMonitor = KeyboardMonitor.shared
    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0
    @State private var scrollContentHeight: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var selectedProfilePhoto: PhotosPickerItem?
    @State private var isPremiumSheetPresented = false
    @Query private var decks: [DeckModel]
    @Query private var userProfiles: [UserProfile]

    let allowsSwipeBack: Bool

    init(allowsSwipeBack: Bool = false) {
        self.allowsSwipeBack = allowsSwipeBack
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                themeManager.groupedScreenBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                        screenTitle
                        profileCard
                        settingsBlocks
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        scrollContentHeight = height
                    }
                    .tabBarAutoHideOnScroll()
                    .padding(.horizontal, UIConstants.Spacing.large)
                    .padding(.top, UIConstants.Spacing.small)
                    .padding(.bottom, keyboardMonitor.isVisible ? UIConstants.Spacing.large : UIConstants.Spacing.huge)
                }
                .scrollDisabled(!isSettingsScrollEnabled)
                .scrollBounceBehavior(.basedOnSize)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    scrollViewportHeight = height
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: settingsTopContentInset)
                }
            }
            .screenTopEdgeShadow(
                topHeight: structuralTopEdgeShadowHeight,
                topRevealProgress: isCollapsedTitleVisible ? 1 : 0,
                debugScreenID: "settings.root",
                style: .progressiveBlur()
            )

            navigationBar
        }
        .coordinateSpace(name: kSettingsChromeSpace)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: keyboardMonitor.isVisible ? 0 : 40)
        }
        .onChange(of: selectedProfilePhoto) { _, newValue in
            updateProfilePhoto(from: newValue)
        }
        .fullScreenSheet(
            isPresented: $isPremiumSheetPresented,
            configuration: .sheet(
                heightMode: .custom(0.62),
                showsCloseButton: true
            )
        ) { _ in
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } background: {
            themeManager.screenBackground
        }
        .swipeBack(enabled: allowsSwipeBack) {
            dismiss()
        }
    }

    private var isSettingsScrollEnabled: Bool {
        scrollContentHeight > scrollViewportHeight + 1
    }

    private var structuralTopEdgeShadowHeight: CGFloat {
        if navigationBarBottomY > 0 {
            return navigationBarBottomY
        }
        return UIConstants.Layout.topEdgeShadowHeight
    }

    private var settingsTopContentInset: CGFloat {
        allowsSwipeBack
            ? navigationBarHeight + UIConstants.Spacing.small
            : UIConstants.Spacing.medium
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
        VStack(spacing: UIConstants.Spacing.small) {
            PhotosPicker(
                selection: $selectedProfilePhoto,
                matching: .images,
                photoLibrary: .shared()
            ) {
                profileAvatar
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Text(profileName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.bottom, UIConstants.Spacing.extraLarge)

            VStack(spacing: UIConstants.Spacing.standard) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: UIConstants.Spacing.small) {
                        profileMetric(icon: "flame.fill", title: streakSummary)
                        profileMetric(icon: "square.stack.3d.up.fill", title: deckCountSummary)
                        profileMetric(icon: isPremiumUser ? "crown.fill" : nil, title: accountPlanSummary, alignment: .center)
                    }

                    VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                        HStack(spacing: UIConstants.Spacing.small) {
                            profileMetric(icon: "flame.fill", title: streakSummary)
                            profileMetric(icon: "square.stack.3d.up.fill", title: deckCountSummary)
                        }

                        profileMetric(icon: isPremiumUser ? "crown.fill" : nil, title: accountPlanSummary, alignment: .center)
                    }
                }

                if !isPremiumUser {
                    Button {
                        isPremiumSheetPresented = true
                    } label: {
                        Text(AppLocalization.string("Unlock full AI features", locale: appPreferences.resolvedLocale))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(themeManager.accentColor.color)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, UIConstants.Spacing.large)
                            .padding(.vertical, 12)
                            .background(themeManager.accentColor.color.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(UIConstants.Spacing.large)
            .settingsCardBackground(cornerRadius: UIConstants.Radius.maximum)
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        Group {
            if let image = profileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
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
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(Circle())
    }

    private var profileImage: UIImage? {
        guard let data = profile?.profileImageData else { return nil }
        return UIImage(data: data)
    }

    private var profileName: String {
        AppLocalization.string("QuizFlash User", locale: appPreferences.resolvedLocale)
    }

    private var accountPlanSummary: String {
        isPremiumUser
            ? AppLocalization.string("Premium", locale: appPreferences.resolvedLocale)
            : AppLocalization.string("Free", locale: appPreferences.resolvedLocale)
    }

    @ViewBuilder
    private var settingsBlocks: some View {
        VStack(spacing: 10) {
            settingsBlock {
                SettingsMenuPickerRow(
                    icon: "globe",
                    tint: .blue,
                    title: "Language",
                    selection: appLanguageBinding,
                    options: AppLanguagePreference.allCases,
                    titleForOption: { option, locale in
                        option.localizedTitle(locale: locale)
                    }
                )
            }

            settingsBlock {
                SettingsSliderRow(
                    icon: "textformat.size",
                    tint: themeManager.accentColor.color,
                    title: "Text Size",
                    detail: "Default size for editors and play modes.",
                    valueSuffix: "",
                    range: Double(FlashcardTextSize.minimumStep)...Double(FlashcardTextSize.maximumStep),
                    step: 1,
                    value: defaultTextSizeBinding
                )
            }

            settingsBlock {
                SettingsMenuPickerRow(
                    icon: "square.dashed",
                    tint: themeManager.accentColor.color,
                    title: "Zone Style",
                    detail: "Visual surface only.",
                    selection: zoneSurfaceStyleBinding,
                    options: AppZoneSurfaceStyle.allCases,
                    titleForOption: { option, locale in
                        option.localizedTitle(locale: locale)
                    }
                )
            }

            settingsBlock {
                SettingsMenuPickerRow(
                    icon: "calendar",
                    tint: themeManager.accentColor.color,
                    title: "Calendar",
                    selection: weekStartBinding,
                    options: AppWeekStartDayPreference.allCases,
                    titleForOption: { option, locale in
                        option.localizedTitle(locale: locale)
                    }
                )
            }

            if UIConstants.isPad {
                settingsBlock {
                    SettingsMenuPickerRow(
                        icon: "sidebar.leading",
                        tint: .purple,
                        title: "Navigation",
                        selection: padTabBarPositionBinding,
                        options: AppPadTabBarPosition.allCases,
                        titleForOption: { option, locale in
                            option.localizedTitle(locale: locale)
                        }
                    )
                }
            }

            settingsBlock {
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

                        Text("Log Out")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)

                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func settingsBlock<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.vertical, UIConstants.Spacing.standard)
            .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
    }

    private func updateProfilePhoto(from item: PhotosPickerItem?) {
        guard let item else { return }

        Task { @MainActor in
            defer { selectedProfilePhoto = nil }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }

            let resolvedProfile: UserProfile
            if let profile {
                resolvedProfile = profile
            } else {
                let newProfile = UserProfile()
                modelContext.insert(newProfile)
                resolvedProfile = newProfile
            }

            resolvedProfile.profileImageData = data
            try? modelContext.save()
        }
    }

    private func profileMetric(
        icon: String?,
        title: String,
        alignment: Alignment = .leading
    ) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeManager.accentColor.color.opacity(0.92))
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.horizontal, UIConstants.Spacing.standard)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: Capsule())
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

    private var streakSummary: String {
        AppLocalization.numbered(
            currentStreak,
            singular: "%d streak",
            plural: "%d streaks",
            locale: appPreferences.resolvedLocale
        )
    }

    private var deckCountSummary: String {
        AppLocalization.numbered(
            decks.count,
            singular: "%d Deck",
            plural: "%d Decks",
            locale: appPreferences.resolvedLocale
        )
    }

    private var profile: UserProfile? {
        userProfiles.first
    }

    private var currentStreak: Int {
        profile?.currentStreak ?? 0
    }

    private var isPremiumUser: Bool {
        false
    }

    private var appLanguageBinding: Binding<AppLanguagePreference> {
        Binding(
            get: { appPreferences.appLanguage },
            set: { appPreferences.appLanguage = $0 }
        )
    }

    private var weekStartBinding: Binding<AppWeekStartDayPreference> {
        Binding(
            get: { appPreferences.weekStartDay },
            set: { appPreferences.weekStartDay = $0 }
        )
    }

    private var defaultTextSizeBinding: Binding<Double> {
        Binding(
            get: { Double(appPreferences.defaultTextSize.step) },
            set: { appPreferences.defaultTextSize = FlashcardTextSize(step: Int($0.rounded())) }
        )
    }

    private var zoneSurfaceStyleBinding: Binding<AppZoneSurfaceStyle> {
        Binding(
            get: { appPreferences.zoneSurfaceStyle },
            set: { appPreferences.zoneSurfaceStyle = $0 }
        )
    }

    private var padTabBarPositionBinding: Binding<AppPadTabBarPosition> {
        Binding(
            get: { appPreferences.padTabBarPosition },
            set: { appPreferences.padTabBarPosition = $0 }
        )
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager.shared)
        .environment(ThemeManager.shared)
        .environment(AppPreferences.shared)
        .modelContainer(for: [DeckModel.self, CardModel.self], inMemory: true)
}
