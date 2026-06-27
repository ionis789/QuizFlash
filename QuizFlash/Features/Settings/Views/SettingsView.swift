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
// MARK: - Settings View

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(CloudUserProfileService.self) private var cloudUserProfileService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var keyboardMonitor = KeyboardMonitor.shared
    @State private var scrollContentHeight: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var selectedProfilePhoto: PhotosPickerItem?
    @State private var displayNameDraft = ""
    @State private var isEditingDisplayName = false
    @State private var isSavingDisplayName = false
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
        .task {
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

            Button(AppLocalization.string("Cancel", locale: appPreferences.resolvedLocale), role: .cancel) { }
        } message: {
            Text(AppLocalization.string("This deletes your Firebase account. Local decks stay on this device.", locale: appPreferences.resolvedLocale))
        }
        .sheet(isPresented: $showDeleteAccountPasswordSheet) {
            deleteAccountPasswordSheet
                .presentationDetents([.height(250)])
                .presentationBackground(.background)
        }
        .sheet(isPresented: $isEditingDisplayName) {
            editDisplayNameSheet
                .presentationDetents([.height(220)])
                .presentationBackground(.background)
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
                heightMode: .custom(0.62),
                showsCloseButton: true
            )
        ) { _ in
            manualPremiumSheet
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
            .buttonStyle(.plain)

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

            VStack(spacing: UIConstants.Spacing.standard) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: UIConstants.Spacing.small) {
                        profileMetric(icon: "flame.fill", title: streakSummary, tint: .orange)
                        profileMetric(icon: "rectangle.stack.fill", title: deckCountSummary, tint: themeManager.accentColor.color)
                        profileMetric(
                            icon: accountPlanIcon,
                            title: accountPlanSummary,
                            tint: isPremiumUser ? .yellow : themeManager.accentColor.color,
                            alignment: .center
                        )
                    }

                    VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                        HStack(spacing: UIConstants.Spacing.small) {
                            profileMetric(icon: "flame.fill", title: streakSummary, tint: .orange)
                            profileMetric(icon: "rectangle.stack.fill", title: deckCountSummary, tint: themeManager.accentColor.color)
                        }

                        profileMetric(
                            icon: accountPlanIcon,
                            title: accountPlanSummary,
                            tint: isPremiumUser ? .yellow : themeManager.accentColor.color,
                            alignment: .center
                        )
                    }
                }

                if isPremiumUser {
                    premiumUsageProgressLine
                } else {
                    freeGenerationsProgressLine
                }
            }
            .padding(UIConstants.Spacing.large)
            .settingsCardBackground(cornerRadius: UIConstants.Radius.maximum)
        }
    }

    private var profileNameButton: some View {
        Button {
            displayNameDraft = authManager.currentUser?.displayName ?? ""
            isEditingDisplayName = true
        } label: {
            HStack(spacing: UIConstants.Spacing.small) {
                Image(systemName: "pencil")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(themeManager.accentColor.color)
                    .opacity(0)
                    .accessibilityHidden(true)

                Text(profileName)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.identity)

                Image(systemName: "pencil")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(themeManager.accentColor.color)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .animation(nil, value: profileName)
            .transaction { transaction in
                transaction.animation = nil
            }
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

            if !FeatureLabRoute.visibleRoutes(in: .current).isEmpty {
                settingsBlock {
                    NavigationLink {
                        FeatureLabView()
                    } label: {
                        SettingsNavigationRow(
                            icon: "testtube.2",
                            tint: themeManager.accentColor.color,
                            title: "Labs",
                            detail: nil,
                            value: nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

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
                .buttonStyle(.plain)
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
                .buttonStyle(.plain)
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
                try await cloudUserProfileService.deleteUserData()
                try await authManager.deleteAccount(
                    reauthentication: .password(deleteAccountPassword)
                )
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

    private var editDisplayNameSheet: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            Text(AppLocalization.string("Display Name", locale: appPreferences.resolvedLocale))
                .font(.title3.weight(.bold))

            TextField(
                AppLocalization.string("Display Name", locale: appPreferences.resolvedLocale),
                text: $displayNameDraft
            )
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .padding(.horizontal, UIConstants.Spacing.standard)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: UIConstants.Radius.medium))

            HStack(spacing: UIConstants.Spacing.standard) {
                Button(AppLocalization.string("Cancel", locale: appPreferences.resolvedLocale), role: .cancel) {
                    isEditingDisplayName = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    saveDisplayName()
                } label: {
                    if isSavingDisplayName {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(AppLocalization.string("Save", locale: appPreferences.resolvedLocale))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.accentColor.color)
                .disabled(isSavingDisplayName)
            }
        }
        .padding(UIConstants.Spacing.large)
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
                    try await cloudUserProfileService.deleteUserData()
                    try await authManager.deleteAccount(
                        reauthentication: .google(presentingViewController)
                    )
                } else {
                    throw AuthManagerError.missingCredential
                }
            } catch {
                presentAuthError(error)
            }
        }
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

    private func saveDisplayName() {
        guard !isSavingDisplayName else { return }
        isSavingDisplayName = true

        Task { @MainActor in
            defer { isSavingDisplayName = false }
            do {
                try await authManager.updateDisplayName(displayNameDraft)
                isEditingDisplayName = false
            } catch {
                presentAuthError(error)
            }
        }
    }

    @ViewBuilder
    private var premiumUsageProgressLine: some View {
        if let quota = subscriptionManager.cloudAIUsageQuotaForDisplay,
           let limitMicroUSD = quota.limitMicroUSD,
           limitMicroUSD > 0 {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Text(AppLocalization.string("AI usage", locale: appPreferences.resolvedLocale))
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: UIConstants.Spacing.small)

                    Text(formattedUsagePercent(quota.usageProgress))
                        .font(.subheadline.weight(.black).monospacedDigit())
                        .foregroundStyle(themeManager.accentColor.color)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))

                        Capsule()
                            .fill(themeManager.accentColor.color.gradient)
                            .frame(width: proxy.size.width * max(0, min(quota.usageProgress, 1)))
                    }
                }
                .frame(height: 8)
            }
            .padding(.top, UIConstants.Spacing.small)
            .accessibilityLabel(AppLocalization.string("AI usage", locale: appPreferences.resolvedLocale))
            .accessibilityValue("\(formattedUsagePercent(quota.usageProgress)), \(formattedMicroUSD(quota.consumedMicroUSD + quota.reservedMicroUSD)) / \(formattedMicroUSD(limitMicroUSD))")
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

        return VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
            HStack(spacing: UIConstants.Spacing.small) {
                Text(AppLocalization.string("AI usage", locale: appPreferences.resolvedLocale))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.secondary)

                Spacer(minLength: UIConstants.Spacing.small)

                Text("\(used) / \(limit)")
                    .font(.subheadline.weight(.black).monospacedDigit())
                    .foregroundStyle(themeManager.accentColor.color)
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
                                ? themeManager.accentColor.color
                                : Color.white.opacity(0.14)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.top, UIConstants.Spacing.small)
        .accessibilityLabel(AppLocalization.string("AI usage", locale: appPreferences.resolvedLocale))
        .accessibilityValue("\(used) / \(limit)")
    }

    private func profileMetric(
        icon: String?,
        title: String,
        tint: Color,
        alignment: Alignment = .center
    ) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(tint)
            }

            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(themeManager.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.horizontal, UIConstants.Spacing.standard)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10), in: Capsule())
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

    private var manualPremiumSheet: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            Text(AppLocalization.string("Premium access", locale: appPreferences.resolvedLocale))
                .font(.title2.weight(.bold))

            Text(AppLocalization.string("Premium is managed manually until App Store Connect is ready.", locale: appPreferences.resolvedLocale))
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { @MainActor in
                    await subscriptionManager.refresh()
                    isPremiumSheetPresented = false
                }
            } label: {
                Text(AppLocalization.string("Refresh Plan", locale: appPreferences.resolvedLocale))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, UIConstants.Spacing.standard)
                    .background(themeManager.accentColor.color, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(UIConstants.Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            cachedDeckCount,
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
                withAnimation(.easeInOut(duration: 0.18)) {
                    isTextSizeExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                    SettingsRowIcon(icon: "textformat.size", tint: themeManager.accentColor.color)

                    Text(AppLocalization.string("Text Size", locale: appPreferences.resolvedLocale))
                        .font(.body.weight(.bold))
                        .foregroundStyle(themeManager.textPrimary)

                    Spacer(minLength: UIConstants.Spacing.standard)

                    Text("\(appPreferences.defaultTextSize.step)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(themeManager.textPrimary)
                        .padding(.horizontal, UIConstants.Spacing.medium)
                        .frame(height: 34)
                        .background(themeManager.accentColor.color.opacity(0.10), in: Capsule())
                        .contentTransition(.numericText())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isTextSizeExpanded {
                TickValuePicker(
                    value: appPreferences.defaultTextSize.step,
                    range: FlashcardTextSize.minimumStep ... FlashcardTextSize.maximumStep,
                    onChange: { newValue in
                        appPreferences.defaultTextSize = FlashcardTextSize(step: newValue)
                    },
                    isCompact: true
                ) { value in
                    "\(value)"
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isTextSizeExpanded)
    }

    private func formattedMicroUSD(_ value: Int) -> String {
        let amount = Double(max(value, 0)) / 1_000_000
        return amount.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private func formattedUsagePercent(_ progress: Double) -> String {
        let boundedProgress = max(0, min(progress, 1))
        return boundedProgress.formatted(.percent.precision(.fractionLength(0)))
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
        .environment(SubscriptionManager.shared)
        .environment(CloudUserProfileService.shared)
        .modelContainer(for: [DeckModel.self, CardModel.self], inMemory: true)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
