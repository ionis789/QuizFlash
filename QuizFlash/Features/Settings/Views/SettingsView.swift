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

private func settingsNameTrace(_ event: String, details: @autoclosure () -> String = "") {
#if DEBUG
    let resolvedDetails = details()
    let suffix = resolvedDetails.isEmpty ? "" : " \(resolvedDetails)"
    print("SETTINGS_NAME_TRACE \(Date().timeIntervalSinceReferenceDate) \(event)\(suffix)")
#endif
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(CloudUserProfileService.self) private var cloudUserProfileService
    @Environment(CloudSyncCoordinator.self) private var cloudSyncCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var keyboardMonitor = KeyboardMonitor.shared
    @State private var scrollContentHeight: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var selectedProfilePhoto: PhotosPickerItem?
    @State private var displayNameDraft = ""
    @State private var isEditingDisplayName = false
    @State private var displayedProfileName: String?
    @State private var pendingDisplayNameFeedback: String?
    @State private var displayNameFeedbackToken: UUID?
    @State private var isPremiumSheetPresented = false
    @State private var showDeleteAccountConfirmation = false
    @State private var showDeleteAccountPasswordSheet = false
    @State private var deleteAccountPassword = ""
    @State private var authErrorMessage = ""
    @State private var showAuthError = false
    @State private var presentingViewController: UIViewController?
    @State private var cachedProfileImage: UIImage?
    @State private var cachedProfileImageSignature: Int?
    @State private var profileImageDecodeTask: Task<Void, Never>?
    @State private var cachedDeckCount = 0
    @State private var goalDraftEnabled = false
    @State private var goalDraftValue = AppPreferences.defaultDailyCardsGoal
    @State private var isCardsGoalExpanded = false
    @State private var isTextSizeExpanded = false
    @Query private var decks: [DeckModel]
    @Query private var userProfiles: [UserProfile]

    let allowsSwipeBack: Bool

    init(allowsSwipeBack: Bool = false) {
        self.allowsSwipeBack = allowsSwipeBack
    }

    var body: some View {
        ZStack {
            themeManager.groupedScreenBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
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
            topRevealProgress: 1,
            debugScreenID: "settings.root",
            style: .progressiveBlur()
        )
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: keyboardMonitor.isVisible ? 0 : 40)
        }
        .onChange(of: selectedProfilePhoto) { _, newValue in
            updateProfilePhoto(from: newValue)
        }
        .onChange(of: profileImageDataSignature) { _, _ in
            refreshCachedProfileImage()
        }
        .onChange(of: decks) { _, newDecks in
            cachedDeckCount = newDecks.count
        }
        .onChange(of: appPreferences.dailyCardsGoal) { _, _ in
            syncGoalDraftFromPreferences()
        }
        .onChange(of: profileName) { oldValue, newValue in
            let confirmsOptimisticUpdate = pendingDisplayNameFeedback == newValue
            settingsNameTrace(
                "profileName.changed",
                details: "oldCount=\(oldValue.count) newCount=\(newValue.count) equal=\(oldValue == newValue) confirmsOptimistic=\(confirmsOptimisticUpdate)"
            )
            displayedProfileName = newValue
            if confirmsOptimisticUpdate {
                pendingDisplayNameFeedback = nil
                settingsNameTrace("feedback.confirmed", details: "source=profileNameChange")
            }
        }
        .onChange(of: displayNameFeedbackToken) { oldValue, newValue in
            settingsNameTrace(
                "feedbackToken.changed",
                details: "old=\(oldValue?.uuidString ?? "nil") new=\(newValue?.uuidString ?? "nil")"
            )
        }
        .onChange(of: isEditingDisplayName) { oldValue, newValue in
            settingsNameTrace("sheet.presentation.changed", details: "old=\(oldValue) new=\(newValue)")
        }
        .task {
            if displayedProfileName == nil {
                displayedProfileName = profileName
            }
            cachedDeckCount = decks.count
            syncGoalDraftFromPreferences()
            refreshCachedProfileImage()
            await subscriptionManager.configure(for: authManager.currentUser)
            await subscriptionManager.refreshCloudAIUsageQuota()
        }
        .onDisappear {
            profileImageDecodeTask?.cancel()
            profileImageDecodeTask = nil
        }
        .background {
            AuthPresentingViewControllerReader { controller in
                presentingViewController = controller
            }
            .frame(width: 0, height: 0)
        }
        .confirmationDialog(
            AppLocalization.string("Delete Account", locale: appPreferences.resolvedLocale),
            isPresented: $showDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                AppLocalization.string("Delete Account", locale: appPreferences.resolvedLocale),
                role: .destructive
            ) {
                beginDeleteAccount()
            }

            if isPremiumUser {
                Button(AppLocalization.string("Manage Subscription", locale: appPreferences.resolvedLocale)) {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        openURL(url)
                    }
                }
            }

            Button(AppLocalization.string("Cancel", locale: appPreferences.resolvedLocale), role: .cancel) { }
        } message: {
            Text(AppLocalization.string("This permanently deletes your account and synced data. Deleting the account does not cancel an active Apple subscription.", locale: appPreferences.resolvedLocale))
        }
        .fullScreenSheet(
            isPresented: $showDeleteAccountPasswordSheet,
            configuration: .sheet(
                heightMode: .safeAreaAbsolute(250, maxFraction: 0.72),
                showsDefaultTopProgressiveBlur: false,
                avoidsKeyboard: true
            )
        ) { safeAreaInsets in
            KeyboardAdaptiveSheetContent {
                deleteAccountPasswordSheet
                    .padding(.bottom, safeAreaInsets.bottom)
            }
        } background: {
            themeManager.groupedScreenBackground
        }
        .fullScreenSheet(
            isPresented: $isEditingDisplayName,
            configuration: .sheet(
                heightMode: .safeAreaAbsolute(265, maxFraction: 0.60),
                showsDefaultTopProgressiveBlur: false,
                showsCloseButton: true,
                avoidsKeyboard: true
            )
        ) { safeAreaInsets in
            KeyboardAdaptiveSheetContent {
                SettingsDisplayNameEditSheet(
                    initialName: displayNameDraft,
                    safeAreaInsets: safeAreaInsets,
                    onSave: updateDisplayName
                )
            }
        } background: {
            themeManager.screenBackground
        }
        .alert(
            AppLocalization.string("Something went wrong", locale: appPreferences.resolvedLocale),
            isPresented: $showAuthError
        ) {
            Button(AppLocalization.string("Done", locale: appPreferences.resolvedLocale), role: .cancel) { }
        } message: {
            Text(authErrorMessage)
        }
        .fullScreenSheet(
            isPresented: $isPremiumSheetPresented,
            configuration: .sheet(
                heightMode: .custom(0.82),
                showsCloseButton: true
            )
        ) { _ in
            PremiumPaywallView {
                isPremiumSheetPresented = false
            }
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
        return UIConstants.Layout.topEdgeShadowHeight
    }

    private var settingsTopContentInset: CGFloat {
        allowsSwipeBack
            ? UIConstants.Size.actionButton + UIConstants.Spacing.extraLarge
            : UIConstants.Spacing.extraLarge
    }

    private var cardsGoalSettings: some View {
        VStack(alignment: .leading, spacing: isCardsGoalExpanded ? UIConstants.Spacing.medium : 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCardsGoalExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                    settingsGoalIcon

                    Text(AppLocalization.string("Cards Goal", locale: appPreferences.resolvedLocale))
                        .font(.body.weight(.bold))
                        .foregroundStyle(themeManager.textPrimary)

                    Spacer(minLength: UIConstants.Spacing.standard)

                    Text(appliedGoalSummary)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(themeManager.textPrimary)
                        .padding(.horizontal, UIConstants.Spacing.medium)
                        .frame(height: 34)
                        .background(
                            (appPreferences.dailyCardsGoal == nil ? Color.primary : themeManager.accentColor.color)
                                .opacity(0.10),
                            in: Capsule()
                        )
                }
                .contentShape(Rectangle())
            }
            .noPressEffectButtonStyle()

            if isCardsGoalExpanded {
                VStack(spacing: UIConstants.Spacing.medium) {
                    goalDraftControls

                    Button(action: applyGoalDraft) {
                        Text(AppLocalization.string("Update Goal", locale: appPreferences.resolvedLocale))
                            .font(.body.weight(.bold))
                            .foregroundStyle(goalDraftHasChanges ? themeManager.screenBackground : themeManager.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background {
                                Capsule()
                                    .fill(goalDraftHasChanges ? themeManager.accentColor.color : themeManager.roleColor(.widgetSurfaceFill))
                            }
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        goalDraftHasChanges
                                            ? themeManager.accentColor.color.opacity(0.24)
                                            : themeManager.roleColor(.widgetSurfaceBorder).opacity(0.14),
                                        lineWidth: 0.8
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!goalDraftHasChanges)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isCardsGoalExpanded)
    }

    private var goalDraftControls: some View {
        TickValuePicker(
            value: goalDraftTickSelection,
            range: 0 ... goalTickUpperBound,
            onChange: setGoalDraftTickSelection,
            isCompact: true
        ) { value in
            guard value > 0 else {
                return AppLocalization.string("No goal", locale: appPreferences.resolvedLocale)
            }

            return "\(value * AppPreferences.dailyCardsGoalStep)"
        }
        .padding(.top, UIConstants.Spacing.tiny)
    }

    private var settingsGoalIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                .fill(themeManager.accentColor.color.opacity(0.14))
                .frame(width: 40, height: 40)

            Image(systemName: "target")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(themeManager.accentColor.color)
        }
    }

    private var profileCard: some View {
        VStack(spacing: UIConstants.Spacing.standard) {
            PhotosPicker(
                selection: $selectedProfilePhoto,
                matching: .images,
                photoLibrary: .shared()
            ) {
                profileAvatar
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            profileNameButton
                .padding(.bottom, UIConstants.Spacing.standard)

            VStack(spacing: 0) {
                HStack(spacing: UIConstants.Spacing.standard) {
                    profileMetric(icon: "flame.fill", title: streakCountText)
                        .accessibilityLabel(streakSummary)

                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 1, height: 32)

                    profileMetric(icon: "rectangle.stack.fill", title: deckCountText)
                        .accessibilityLabel(deckCountSummary)
                }
                .padding(.bottom, UIConstants.Spacing.standard)

                profileDivider

                Button {
                    isPremiumSheetPresented = true
                } label: {
                    HStack(spacing: UIConstants.Spacing.small) {
                        profileMetric(
                            icon: accountPlanIcon,
                            title: accountPlanSummary
                        )

                        Image(systemName: "chevron.compact.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, UIConstants.Spacing.standard)

                if isPremiumUser {
                    profileDivider
                    premiumUsageProgressLine
                        .padding(.top, UIConstants.Spacing.standard)
                } else {
                    profileDivider
                    freeGenerationsProgressLine
                        .padding(.top, UIConstants.Spacing.standard)
                }
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.vertical, UIConstants.Spacing.standard)
            .settingsCardBackground(cornerRadius: UIConstants.Radius.maximum)
        }
    }

    private var profileNameButton: some View {
        Button {
            displayNameDraft = authManager.currentUser?.displayName ?? ""
            settingsNameTrace(
                "open.tapped",
                details: "profileCount=\(profileName.count) authDisplayCount=\(displayNameDraft.count)"
            )
            isEditingDisplayName = true
        } label: {
            HStack(spacing: UIConstants.Spacing.small) {
                Image(systemName: "pencil")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(themeManager.accentColor.color)
                    .opacity(0)
                    .accessibilityHidden(true)

                Text(displayedProfileName ?? profileName)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .statusTextMotion(trigger: displayNameFeedbackToken)

                Image(systemName: "pencil")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(themeManager.accentColor.color)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.string("Display Name", locale: appPreferences.resolvedLocale))
    }

    @ViewBuilder
    private var profileAvatar: some View {
        Group {
            if let image = profileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: 114, height: 114)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(themeManager.accentColor.color.opacity(0.32), lineWidth: 2)
        }
        .shadow(color: themeManager.accentColor.color.opacity(0.20), radius: 24, x: 0, y: 10)
    }

    private var placeholderAvatar: some View {
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

    private var profileImage: UIImage? {
        cachedProfileImage
    }

    private var profileImageDataSignature: Int? {
        guard let data = profile?.profileImageData else { return nil }
        return makeProfileImageSignature(for: data)
    }

    private var profileName: String {
        authManager.currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? authManager.currentUser?.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? AppLocalization.string("QuizFlash User", locale: appPreferences.resolvedLocale)
    }

    private var accountPlanSummary: String {
        isPremiumUser
            ? AppLocalization.string("Premium", locale: appPreferences.resolvedLocale)
            : AppLocalization.string("Free", locale: appPreferences.resolvedLocale)
    }

    private var accountPlanIcon: String? {
        isPremiumUser ? "bolt.fill" : nil
    }

    private var photoURL: URL? {
        guard let value = authManager.currentUser?.photoURLString else { return nil }
        return URL(string: value)
    }

    @ViewBuilder
    private var settingsBlocks: some View {
        VStack(spacing: 10) {
            settingsBlock {
                VStack(spacing: UIConstants.Spacing.standard) {
                    accountInfoRow(
                        icon: "envelope.fill",
                        tint: .blue,
                        title: AppLocalization.string("Email", locale: appPreferences.resolvedLocale),
                        value: authManager.currentUser?.email ?? AppLocalization.string("Unavailable", locale: appPreferences.resolvedLocale)
                    )
                }
            }

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
                cardsGoalSettings
            }

            settingsBlock {
                textSizeSettings
            }

            settingsBlock {
                SettingsMenuPickerRow(
                    icon: "rectangle.3.group",
                    tint: themeManager.accentColor.color,
                    title: "Zone Group Alignment",
                    selection: defaultZoneGroupAlignmentBinding,
                    options: ZoneBlockAlignment.explicitCases,
                    titleForOption: { option, locale in
                        option.localizedTitle(locale: locale)
                    }
                )
            }

            settingsBlock {
                SettingsMenuPickerRow(
                    icon: "text.alignleft",
                    tint: themeManager.accentColor.color,
                    title: "Inner Zone Alignment",
                    selection: defaultInnerZoneAlignmentBinding,
                    options: ZoneBlockAlignment.explicitCases,
                    titleForOption: { option, locale in
                        option.localizedTitle(locale: locale)
                    }
                )
            }

            settingsBlock {
                SettingsMenuPickerRow(
                    icon: "square.dashed",
                    tint: themeManager.accentColor.color,
                    title: "Zone Style",
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

#if DEBUG
            settingsBlock {
                NavigationLink {
                    LabsView()
                } label: {
                    SettingsNavigationRow(
                        icon: "wrench.and.screwdriver.fill",
                        tint: .orange,
                        title: SettingsTextContent.verbatim(
                            AppLocalization.string("Labs", locale: appPreferences.resolvedLocale)
                        ),
                        detail: SettingsTextContent.verbatim(
                            AppLocalization.string("Development tools", locale: appPreferences.resolvedLocale)
                        ),
                        value: nil
                    )
                }
                .noPressEffectButtonStyle()
            }
#endif

            settingsBlock {
                Button {
                    Task { @MainActor in
                        do {
                            try await authManager.logout()
                        } catch {
                            presentAuthError(error)
                        }
                    }
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

                        Text(AppLocalization.string("Log Out", locale: appPreferences.resolvedLocale))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)

                        Spacer(minLength: 0)
                    }
                }
                .noPressEffectButtonStyle()
            }

            settingsBlock {
                Button(role: .destructive) {
                    showDeleteAccountConfirmation = true
                } label: {
                    HStack(spacing: UIConstants.Spacing.medium) {
                        ZStack {
                            RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                                .fill(Color.red.opacity(0.12))
                                .frame(width: 40, height: 40)

                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.red)
                        }

                        Text(AppLocalization.string("Delete Account", locale: appPreferences.resolvedLocale))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)

                        Spacer(minLength: 0)
                    }
                }
                .noPressEffectButtonStyle()
            }
        }
    }

    private var deleteAccountPasswordSheet: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            Text(AppLocalization.string("Confirm Password", locale: appPreferences.resolvedLocale))
                .font(.title3.weight(.bold))

            AuthIconTextField(
                title: AppLocalization.string("Password", locale: appPreferences.resolvedLocale),
                icon: "lock",
                isPassword: true,
                text: $deleteAccountPassword
            )
            .textContentType(.password)

            AuthAsyncButton(
                title: AppLocalization.string("Delete Account", locale: appPreferences.resolvedLocale),
                icon: "trash",
                tint: .red,
                isEnabled: !deleteAccountPassword.isEmpty
            ) {
                try await deleteAccount(reauthentication: .password(deleteAccountPassword))
                deleteAccountPassword = ""
                showDeleteAccountPasswordSheet = false
            } onError: { error in
                presentAuthError(error)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .padding(.top, UIConstants.Spacing.extraLarge)
    }

    private func settingsBlock<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.vertical, UIConstants.Spacing.standard)
            .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
    }

    private func beginDeleteAccount() {
        guard let user = authManager.currentUser else { return }
        let providers = Set(user.providers)

        if providers.contains(AuthProviderID.password.rawValue) {
            deleteAccountPassword = ""
            showDeleteAccountPasswordSheet = true
            return
        }

        Task { @MainActor in
            do {
                if providers.contains(AuthProviderID.google.rawValue) {
                    guard let presentingViewController else {
                        throw AuthManagerError.missingPresenter
                    }
                    try await deleteAccount(reauthentication: .google(presentingViewController))
                } else if providers.contains(AuthProviderID.apple.rawValue) {
                    try await deleteAccount(reauthentication: .apple)
                } else {
                    throw AuthManagerError.missingCredential
                }
            } catch {
                presentAuthError(error)
            }
        }
    }

    private func deleteAccount(reauthentication: AuthReauthenticationRequest) async throws {
        try await authManager.reauthenticateForAccountDeletion(reauthentication)
        cloudSyncCoordinator.stop()

        do {
            try await cloudUserProfileService.deleteUserData()
            try deleteLocalAccountData()
            try await authManager.deleteReauthenticatedAccount()
        } catch {
            cloudSyncCoordinator.configure(
                for: authManager.currentUser,
                modelContainer: modelContext.container
            )
            throw error
        }
    }

    private func deleteLocalAccountData() throws {
        try modelContext.delete(model: ReviewEvent.self)
        try modelContext.delete(model: DailyActivityLog.self)
        try modelContext.delete(model: HomeDailyCardAggregate.self)
        try modelContext.delete(model: HomeDailyDeckAggregate.self)
        try modelContext.delete(model: HomeDailyStudyAggregate.self)
        try modelContext.delete(model: DeckPlayModeSettingsModel.self)
        try modelContext.delete(model: CardModel.self)
        try modelContext.delete(model: DeckModel.self)
        try modelContext.delete(model: FolderModel.self)
        try modelContext.delete(model: UserProfile.self)
        try modelContext.save()
    }

    private func presentAuthError(_ error: Error) {
        authErrorMessage = AuthErrorPresentation.message(
            for: error,
            locale: appPreferences.resolvedLocale
        )
        showAuthError = true
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
            refreshCachedProfileImage(from: data)
            try? modelContext.save()
        }
    }

    private func refreshCachedProfileImage(from overrideData: Data? = nil) {
        profileImageDecodeTask?.cancel()

        let data = overrideData ?? profile?.profileImageData
        guard let data else {
            cachedProfileImage = nil
            cachedProfileImageSignature = nil
            profileImageDecodeTask = nil
            return
        }

        let signature = makeProfileImageSignature(for: data)
        cachedProfileImageSignature = signature

        profileImageDecodeTask = Task { @MainActor in
            let decodedImage = await Task.detached(priority: .utility) {
                UIImage(data: data)
            }.value

            guard !Task.isCancelled, cachedProfileImageSignature == signature else { return }
            cachedProfileImage = decodedImage
        }
    }

    private func makeProfileImageSignature(for data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data.count)
        data.withUnsafeBytes { rawBuffer in
            guard rawBuffer.count > 0 else { return }
            hasher.combine(rawBuffer.load(fromByteOffset: 0, as: UInt8.self))
            hasher.combine(rawBuffer.load(fromByteOffset: rawBuffer.count / 2, as: UInt8.self))
            hasher.combine(rawBuffer.load(fromByteOffset: rawBuffer.count - 1, as: UInt8.self))
        }
        return hasher.finalize()
    }

    private func updateDisplayName(_ normalizedDisplayName: String) {
        let previousDisplayName = authManager.currentUser?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        settingsNameTrace(
            "update.requested",
            details: "previousCount=\(previousDisplayName?.count ?? 0) submittedCount=\(normalizedDisplayName.count) equal=\(previousDisplayName == normalizedDisplayName)"
        )
        if previousDisplayName != normalizedDisplayName {
            pendingDisplayNameFeedback = normalizedDisplayName
            displayedProfileName = normalizedDisplayName
            let nextToken = UUID()
            settingsNameTrace("feedback.triggered", details: "token=\(nextToken.uuidString) source=optimisticUpdate")
            displayNameFeedbackToken = nextToken
        }
        Task { @MainActor in
            do {
                try await authManager.updateDisplayName(normalizedDisplayName)
                let authDisplayName = authManager.currentUser?.displayName?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                settingsNameTrace(
                    "update.succeeded",
                    details: "authCount=\(authDisplayName?.count ?? 0) profileCount=\(profileName.count) authMatchesSubmitted=\(authDisplayName == normalizedDisplayName) profileMatchesSubmitted=\(profileName == normalizedDisplayName)"
                )
                if pendingDisplayNameFeedback == normalizedDisplayName {
                    pendingDisplayNameFeedback = nil
                }
                guard previousDisplayName != normalizedDisplayName else {
                    settingsNameTrace("feedback.skipped", details: "reason=unchanged")
                    return
                }
            } catch {
                if pendingDisplayNameFeedback == normalizedDisplayName {
                    pendingDisplayNameFeedback = nil
                }
                displayedProfileName = previousDisplayName ?? profileName
                let rollbackToken = UUID()
                settingsNameTrace("feedback.rolledBack", details: "token=\(rollbackToken.uuidString)")
                displayNameFeedbackToken = rollbackToken
                settingsNameTrace("update.failed", details: "errorType=\(String(describing: type(of: error)))")
                presentAuthError(error)
            }
        }
    }

    @ViewBuilder
    private var premiumUsageProgressLine: some View {
        if let quota = subscriptionManager.cloudAIUsageQuotaForDisplay,
           let limitMicroUSD = quota.limitMicroUSD,
           limitMicroUSD > 0 {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Text(AppLocalization.string("AI usage", locale: appPreferences.resolvedLocale))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: UIConstants.Spacing.small)

                    Text(formattedUsagePercent(quota.usageProgress))
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))

                        Capsule()
                            .fill(themeManager.accentColor.color.opacity(0.88))
                            .frame(width: proxy.size.width * max(0, min(quota.usageProgress, 1)))
                    }
                }
                .frame(height: 6)

                if let renewalText = premiumUsageRenewalText(quota) {
                    Text(renewalText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(AppLocalization.string("AI usage", locale: appPreferences.resolvedLocale))
            .accessibilityValue(
                [formattedUsagePercent(quota.usageProgress), premiumUsageRenewalText(quota)]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            )
        }
    }

    private var freeGenerationsProgressLine: some View {
        let limit = max(subscriptionManager.freeGenerationsLimit ?? SubscriptionManager.defaultFreeGenerationsLimit, 1)
        let used = min(max(subscriptionManager.freeGenerationsUsed ?? 0, 0), limit)
        let segmentCount = SubscriptionManager.defaultFreeGenerationsLimit
        let filledSegments = min(
            segmentCount,
            Int(ceil((Double(used) / Double(limit)) * Double(segmentCount)))
        )

        return VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(spacing: UIConstants.Spacing.small) {
                Text(AppLocalization.string("AI usage", locale: appPreferences.resolvedLocale))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: UIConstants.Spacing.small)

                Text("\(used) / \(limit)")
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }

            HStack(spacing: 7) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    Capsule()
                        .fill(
                            index < filledSegments
                                ? themeManager.accentColor.color.opacity(0.88)
                                : Color.primary.opacity(0.12)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 6)
                }
            }
            .frame(height: 6)
        }
        .accessibilityLabel(AppLocalization.string("AI usage", locale: appPreferences.resolvedLocale))
        .accessibilityValue("\(used) / \(limit)")
    }

    private var profileDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
    }

    private func profileMetric(
        icon: String?,
        title: String
    ) -> some View {
        HStack(spacing: UIConstants.Spacing.small) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: UIConstants.Size.iconStandard)
            }

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func accountInfoRow(
        icon: String,
        tint: Color,
        title: String,
        value: String,
        showsDisclosure: Bool = false
    ) -> some View {
        accountInfoRow(
            icon: icon,
            tint: tint,
            title: title,
            showsDisclosure: showsDisclosure
        ) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.trailing)
        }
    }

    private func accountInfoRow<Trailing: View>(
        icon: String,
        tint: Color,
        title: String,
        showsDisclosure: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
            }

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: UIConstants.Spacing.medium)

            trailing()

            if showsDisclosure {
                Image(systemName: "chevron.compact.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
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

    private var streakCountText: String {
        currentStreak.formatted(.number)
    }

    private var deckCountSummary: String {
        AppLocalization.numbered(
            cachedDeckCount,
            singular: "%d Deck",
            plural: "%d Decks",
            locale: appPreferences.resolvedLocale
        )
    }

    private var deckCountText: String {
        cachedDeckCount.formatted(.number)
    }

    private var profile: UserProfile? {
        userProfiles.first
    }

    private var currentStreak: Int {
        profile?.currentStreak ?? 0
    }

    private var isPremiumUser: Bool {
        subscriptionManager.isPremium
    }

    private var providerSummary: String {
        guard let providers = authManager.currentUser?.providers, !providers.isEmpty else {
            return AppLocalization.string("Unavailable", locale: appPreferences.resolvedLocale)
        }

        return providers
            .map { provider in
                switch provider {
                case AuthProviderID.password.rawValue:
                    return AppLocalization.string("Email", locale: appPreferences.resolvedLocale)
                case AuthProviderID.google.rawValue:
                    return "Google"
                case AuthProviderID.apple.rawValue:
                    return "Apple"
                default:
                    return provider
                }
            }
            .joined(separator: ", ")
    }

    private var textSizeSettings: some View {
        VStack(alignment: .leading, spacing: isTextSizeExpanded ? UIConstants.Spacing.medium : 0) {
            Button {
                withAnimation(.compactExpansion) {
                    isTextSizeExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                    SettingsRowIcon(icon: "textformat.size", tint: themeManager.accentColor.color)

                    Text(AppLocalization.string("Text Size", locale: appPreferences.resolvedLocale))
                        .font(.body.weight(.bold))
                        .foregroundStyle(themeManager.textPrimary)

                    Spacer(minLength: UIConstants.Spacing.standard)

                    Image(
                        systemName: isTextSizeExpanded
                            ? "chevron.compact.up"
                            : "chevron.compact.down"
                    )
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(themeManager.accentColor.color)
                    .frame(width: 30, height: 30)
                }
                .contentShape(Rectangle())
            }
            .noPressEffectButtonStyle()

            if isTextSizeExpanded {
                TextSizeScalePicker(
                    textSize: appPreferences.defaultTextSize,
                    previewText: AppLocalization.string("Comfortable reading", locale: appPreferences.resolvedLocale),
                    onChange: { appPreferences.defaultTextSize = $0 }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }

    private func formattedUsagePercent(_ progress: Double) -> String {
        let boundedProgress = max(0, min(progress, 1))
        return boundedProgress.formatted(.percent.precision(.fractionLength(0)))
    }

    private func premiumUsageRenewalText(_ quota: CloudAIQuotaState) -> String? {
        guard let endMilliseconds = quota.billingWindowEndMs, endMilliseconds > 0 else {
            return nil
        }
        let date = Date(timeIntervalSince1970: TimeInterval(endMilliseconds) / 1_000)
        let formattedDate = date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .year()
                .locale(appPreferences.resolvedLocale)
        )
        let format = AppLocalization.string("Renews %@", locale: appPreferences.resolvedLocale)
        return String.localizedStringWithFormat(format, formattedDate)
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

    private var appliedGoalSummary: String {
        guard let dailyGoal = appPreferences.dailyCardsGoal else {
            return AppLocalization.string("No goal", locale: appPreferences.resolvedLocale)
        }

        let format = AppLocalization.string("%d cards", locale: appPreferences.resolvedLocale)
        return String(format: format, locale: appPreferences.resolvedLocale, dailyGoal)
    }

    private var goalDraftHasChanges: Bool {
        let draftGoal = goalDraftEnabled ? goalDraftValue : nil
        return appPreferences.dailyCardsGoal != draftGoal
    }

    private var goalTickUpperBound: Int {
        AppPreferences.dailyCardsGoalRange.upperBound / AppPreferences.dailyCardsGoalStep
    }

    private var goalDraftTickSelection: Int {
        guard goalDraftEnabled else { return 0 }
        return min(
            max(goalDraftValue / AppPreferences.dailyCardsGoalStep, 1),
            goalTickUpperBound
        )
    }

    private func syncGoalDraftFromPreferences() {
        if let dailyCardsGoal = appPreferences.dailyCardsGoal {
            goalDraftEnabled = true
            goalDraftValue = dailyCardsGoal
        } else {
            goalDraftEnabled = false
            goalDraftValue = AppPreferences.defaultDailyCardsGoal
        }
    }

    private func applyGoalDraft() {
        appPreferences.dailyCardsGoal = goalDraftEnabled ? goalDraftValue : nil
    }

    private func setGoalDraftTickSelection(_ selection: Int) {
        guard selection > 0 else {
            goalDraftEnabled = false
            return
        }

        goalDraftEnabled = true
        goalDraftValue = min(selection, goalTickUpperBound) * AppPreferences.dailyCardsGoalStep
    }

    private var zoneSurfaceStyleBinding: Binding<AppZoneSurfaceStyle> {
        Binding(
            get: { appPreferences.zoneSurfaceStyle },
            set: { appPreferences.zoneSurfaceStyle = $0 }
        )
    }

    private var defaultZoneGroupAlignmentBinding: Binding<ZoneBlockAlignment> {
        Binding(
            get: { appPreferences.defaultZoneGroupAlignment },
            set: { appPreferences.defaultZoneGroupAlignment = $0 }
        )
    }

    private var defaultInnerZoneAlignmentBinding: Binding<ZoneBlockAlignment> {
        Binding(
            get: { appPreferences.defaultInnerZoneAlignment },
            set: { appPreferences.defaultInnerZoneAlignment = $0 }
        )
    }

    private var padTabBarPositionBinding: Binding<AppPadTabBarPosition> {
        Binding(
            get: { appPreferences.padTabBarPosition },
            set: { appPreferences.padTabBarPosition = $0 }
        )
    }
}

// MARK: - Display Name Sheet

private struct SettingsDisplayNameEditSheet: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(\.fullScreenSheetDismiss) private var dismissSheet
    @Environment(\.fullScreenSheetTopChromeClearance) private var topChromeClearance
    @State private var keyboardMonitor = KeyboardMonitor.shared
    @FocusState private var isNameFocused: Bool

    let safeAreaInsets: UIEdgeInsets
    let onSave: (String) -> Void

    @State private var name: String
    @State private var isSubmitting = false
    private let initialNormalizedName: String

    init(
        initialName: String,
        safeAreaInsets: UIEdgeInsets,
        onSave: @escaping (String) -> Void
    ) {
        self.safeAreaInsets = safeAreaInsets
        self.onSave = onSave

        let normalizedName = initialName.trimmingCharacters(in: .whitespacesAndNewlines)
        initialNormalizedName = normalizedName
        _name = State(initialValue: initialName)
    }

    private var locale: Locale { appPreferences.resolvedLocale }
    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool {
        !normalizedName.isEmpty
            && normalizedName != initialNormalizedName
            && !isSubmitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            Text(AppLocalization.string("Display Name", locale: locale))
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(themeManager.textPrimary)

            TextField(
                AppLocalization.string("Display Name", locale: locale),
                text: $name
            )
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(themeManager.textPrimary)
            .tint(themeManager.roleColor(.buttonPrimaryFill))
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($isNameFocused)
            .padding(UIConstants.Spacing.large)
            .duoSurface(cornerRadius: 24)

            Button(action: saveChanges) {
                Text(AppLocalization.string("Save", locale: locale))
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(
                        canSave
                            ? themeManager.roleColor(.buttonPrimaryForeground)
                            : themeManager.textSecondary
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Capsule().fill(
                            canSave
                                ? themeManager.roleColor(.buttonPrimaryFill)
                                : themeManager.roleColor(.widgetSurfaceFill)
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .padding(.top, max(topChromeClearance + 24, safeAreaInsets.top + 24))
        .padding(.bottom, max(safeAreaInsets.bottom, UIConstants.Spacing.standard))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            settingsNameTrace(
                "editor.appeared",
                details: "initialCount=\(initialNormalizedName.count) currentCount=\(normalizedName.count)"
            )
            isNameFocused = true
        }
        .onDisappear {
            settingsNameTrace(
                "editor.disappeared",
                details: "currentCount=\(normalizedName.count) submitting=\(isSubmitting)"
            )
        }
    }

    private func saveChanges() {
        guard canSave else { return }
        isSubmitting = true
        let submittedName = normalizedName
        settingsNameTrace(
            "save.tapped",
            details: "initialCount=\(initialNormalizedName.count) submittedCount=\(submittedName.count) focused=\(isNameFocused) keyboardVisible=\(keyboardMonitor.isVisible)"
        )

        Task { @MainActor in
            let shouldWaitForKeyboard = isNameFocused || keyboardMonitor.isVisible
            settingsNameTrace("keyboard.dismiss.decision", details: "shouldWait=\(shouldWaitForKeyboard)")
            if shouldWaitForKeyboard {
                isNameFocused = false
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
                try? await Task.sleep(for: .seconds(FullScreenSheetMotion.duration))
                settingsNameTrace(
                    "keyboard.dismiss.waitFinished",
                    details: "keyboardVisible=\(keyboardMonitor.isVisible)"
                )
            }

            if let dismissSheet {
                settingsNameTrace("sheet.dismiss.requested", details: "path=environment")
                dismissSheet {
                    settingsNameTrace("sheet.dismiss.completed", details: "path=environment")
                    onSave(submittedName)
                }
            } else {
                settingsNameTrace("sheet.dismiss.unavailable", details: "savingImmediately=true")
                onSave(submittedName)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager.shared)
        .environment(ThemeManager.shared)
        .environment(AppPreferences.shared)
        .environment(OnboardingStateStore.shared)
        .environment(SubscriptionManager.shared)
        .environment(CloudUserProfileService.shared)
        .modelContainer(for: [DeckModel.self, CardModel.self], inMemory: true)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
