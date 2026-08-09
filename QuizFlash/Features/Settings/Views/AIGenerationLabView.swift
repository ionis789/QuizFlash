#if DEBUG
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct AIGenerationLabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    @State private var viewModel = AIGenerationLabViewModel.shared
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isPDFImporterPresented = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                corpusSection
                configurationSection
                runSection
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Spacing.huge)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(themeManager.groupedScreenBackground.ignoresSafeArea())
        .navigationTitle(localized("AI Generation Lab"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            navigationBar
        }
        .fileImporter(
            isPresented: $isPDFImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true,
            onCompletion: { result in
                Task { await viewModel.importPDFs(result) }
            }
        )
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await viewModel.importPhotos(items)
                selectedPhotos = []
            }
        }
        .alert(localized("AI Generation Lab"), isPresented: $viewModel.isShowingError) {
            Button(localized("OK"), role: .cancel) { }
        } message: {
            Text(localized(viewModel.errorMessage))
        }
        .swipeBack { dismiss() }
        .task {
            await viewModel.load()
        }
    }

    private var corpusSection: some View {
        SettingsSectionCard(
            title: SettingsTextContent.verbatim(localized("Test Corpus")),
            subtitle: SettingsTextContent.verbatim(localized("Sources are processed in this exact order."))
        ) {
            VStack(spacing: UIConstants.Spacing.standard) {
                importActions

                if viewModel.isWorking {
                    ProgressView()
                        .tint(themeManager.accentColor.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, UIConstants.Spacing.small)
                }

                if viewModel.sources.isEmpty, !viewModel.isWorking {
                    emptyCorpus
                } else {
                    sourceList
                }
            }
        }
    }

    private var importActions: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            Button {
                isPDFImporterPresented = true
            } label: {
                importActionLabel(title: localized("Add PDFs"), icon: "doc.badge.plus")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isWorking || viewModel.isRunning)

            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 50,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                importActionLabel(title: localized("Add Images"), icon: "photo.badge.plus")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isWorking || viewModel.isRunning)
        }
    }

    private func importActionLabel(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(themeManager.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: UIConstants.Size.buttonHeight)
            .duoControlSurface(cornerRadius: UIConstants.Radius.card)
    }

    private var emptyCorpus: some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(themeManager.textSecondary)

            Text(localized("No sources added"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, UIConstants.Spacing.large)
    }

    private var sourceList: some View {
        VStack(spacing: UIConstants.Spacing.standard) {
            ForEach(Array(viewModel.sources.enumerated()), id: \.element.id) { index, source in
                if index > 0 {
                    SettingsCardDivider()
                }

                sourceRow(source, position: index + 1)
            }
        }
    }

    private func sourceRow(_ source: AIGenerationLabSource, position: Int) -> some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
            ZStack(alignment: .topTrailing) {
                SettingsRowIcon(
                    icon: source.kind == .pdf ? "doc.richtext" : "photo",
                    tint: source.kind == .pdf ? .red : themeManager.accentColor.color
                )

                Text("\(position)")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 17, minHeight: 17)
                    .background(themeManager.accentColor.color, in: Circle())
                    .offset(x: 5, y: -5)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(source.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(themeManager.textPrimary)
                    .lineLimit(2)

                Text(sourceMetadata(source))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(themeManager.textSecondary)
                    .lineLimit(1)

                Text("SHA-256 · \(source.sha256.prefix(12))")
                    .font(.caption2.monospaced().weight(.medium))
                    .foregroundStyle(themeManager.textSecondary.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    Task { await viewModel.moveSource(id: source.id, by: -1) }
                } label: {
                    Label(localized("Move Up"), systemImage: "chevron.up")
                }
                .disabled(!viewModel.canMoveSource(id: source.id, by: -1))

                Button {
                    Task { await viewModel.moveSource(id: source.id, by: 1) }
                } label: {
                    Label(localized("Move Down"), systemImage: "chevron.down")
                }
                .disabled(!viewModel.canMoveSource(id: source.id, by: 1))

                Divider()

                Button(role: .destructive) {
                    Task { await viewModel.removeSource(id: source.id) }
                } label: {
                    Label(localized("Delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(themeManager.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("More"))
        }
        .disabled(viewModel.isWorking || viewModel.isRunning)
    }

    private var configurationSection: some View {
        SettingsSectionCard(
            title: SettingsTextContent.verbatim(localized("Generation Configuration")),
            subtitle: SettingsTextContent.verbatim(localized("These settings are saved with the corpus."))
        ) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                cardCountRow
                SettingsCardDivider()

                compactOptionRow(title: localized("Type")) {
                    HStack(spacing: UIConstants.Spacing.small) {
                        ForEach(AICardGenerationType.allCases) { type in
                            compactSelectionButton(
                                title: type.localizedTitle(locale: appPreferences.resolvedLocale),
                                isSelected: viewModel.options.cardType == type
                            ) {
                                viewModel.options.cardType = type
                            }
                        }
                    }
                }

                compactOptionRow(title: localized("Level")) {
                    HStack(spacing: UIConstants.Spacing.small) {
                        ForEach(AICardGenerationLevel.allCases) { level in
                            compactSelectionButton(
                                title: level.localizedTitle(locale: appPreferences.resolvedLocale),
                                isSelected: viewModel.options.cardLevel == level
                            ) {
                                viewModel.options.cardLevel = level
                            }
                        }
                    }
                }

                compactOptionRow(title: localized("Language")) {
                    outputLanguagePicker
                }

                compactOptionRow(title: localized("Instructions")) {
                    TextField(
                        localized("Optional"),
                        text: Binding(
                            get: { viewModel.options.userInstructions },
                            set: { viewModel.options.userInstructions = $0 }
                        ),
                        axis: .vertical
                    )
                    .font(.body)
                    .lineLimit(2 ... 6)
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, UIConstants.Spacing.medium)
                    .duoControlSurface(cornerRadius: UIConstants.Radius.card)
                }
            }
            .disabled(viewModel.isWorking || viewModel.isRunning)
        }
    }

    private var cardCountRow: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            SettingsRowIcon(icon: "number", tint: themeManager.accentColor.color)

            Text(localized("Cards"))
                .font(.body.weight(.semibold))
                .foregroundStyle(themeManager.textPrimary)

            Spacer(minLength: UIConstants.Spacing.standard)

            Stepper(
                value: Binding(
                    get: { viewModel.targetCardCount },
                    set: { viewModel.targetCardCount = $0 }
                ),
                in: 5 ... viewModel.maximumTargetCardCount,
                step: 5
            ) {
                Text("\(viewModel.targetCardCount)")
                    .font(.body.monospacedDigit().weight(.bold))
                    .foregroundStyle(themeManager.textPrimary)
                    .frame(minWidth: 32)
            }
            .fixedSize()
        }
    }

    private var runSection: some View {
        SettingsSectionCard(
            title: SettingsTextContent.verbatim(localized("Run")),
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                if let progress = viewModel.runProgress {
                    runProgressView(progress)
                    SettingsCardDivider()
                }

                HStack(spacing: UIConstants.Spacing.small) {
                    Button {
                        if viewModel.isRunning {
                            viewModel.cancelRun()
                        } else {
                            viewModel.startRun()
                        }
                    } label: {
                        Label(
                            localized(viewModel.isRunning ? "Cancel" : "Run Corpus"),
                            systemImage: viewModel.isRunning ? "xmark" : "play.fill"
                        )
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(
                            viewModel.isRunning
                                ? Color.red
                                : themeManager.roleColor(.labelPrimaryForeground)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: UIConstants.Size.buttonHeight)
                        .primarySelectionSurface(
                            isSelected: !viewModel.isRunning,
                            cornerRadius: UIConstants.Size.buttonHeight / 2
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.isRunning && !viewModel.canStartRun)

                    if viewModel.latestReport != nil {
                        Button {
                            Task { await viewModel.copyLatestReport() }
                        } label: {
                            Label(
                                localized(viewModel.didCopyLatestReport ? "Copied" : "Copy JSON"),
                                systemImage: viewModel.didCopyLatestReport ? "checkmark" : "doc.on.doc"
                            )
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(themeManager.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: UIConstants.Size.buttonHeight)
                            .duoControlSurface(cornerRadius: UIConstants.Size.buttonHeight / 2)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isRunning)
                    }
                }

                if !viewModel.completedCaseResults.isEmpty {
                    SettingsCardDivider()
                    VStack(spacing: UIConstants.Spacing.standard) {
                        ForEach(Array(viewModel.completedCaseResults.enumerated()), id: \.element.id) { index, result in
                            if index > 0 {
                                SettingsCardDivider()
                            }
                            resultRow(result)
                        }
                    }
                }
            }
        }
    }

    private func runProgressView(_ progress: AIGenerationLabRunProgress) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(spacing: UIConstants.Spacing.small) {
                ProgressView()
                    .tint(themeManager.accentColor.color)

                Text(progress.sourceName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(themeManager.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(progress.caseIndex)/\(progress.caseCount)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(themeManager.textSecondary)
            }

            Text(runStageText(progress.stage))
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeManager.textSecondary)
                .monospacedDigit()
        }
    }

    private func resultRow(_ result: AIGenerationLabCaseResult) -> some View {
        HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
            Circle()
                .fill(resultStatusColor(result.status))
                .frame(width: 9, height: 9)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.sourceName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(themeManager.textPrimary)
                    .lineLimit(1)

                Text(
                    "\(result.generatedCardCount)/\(result.targetCardCount) · "
                    + formattedDuration(result.timings.totalMilliseconds)
                )
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(themeManager.textSecondary)

                if let traceRunID = result.traceRunID {
                    Text("Trace · \(traceRunID.uuidString.prefix(8))")
                        .font(.caption2.monospaced().weight(.medium))
                        .foregroundStyle(themeManager.textSecondary.opacity(0.72))
                }
            }

            Spacer(minLength: 0)

            Text(localized(resultStatusKey(result.status)))
                .font(.caption.weight(.bold))
                .foregroundStyle(resultStatusColor(result.status))
        }
    }

    private func runStageText(_ stage: AIGenerationLabRunStage) -> String {
        switch stage {
        case .preparing:
            return localized("Preparing source")
        case .authorizing:
            return localized("Authorizing")
        case .blueprint:
            return localized("Building blueprint")
        case .generating(let generated, let target):
            return "\(localized("Generating")) · \(generated)/\(target)"
        case .finalizing:
            return localized("Finalizing")
        }
    }

    private func resultStatusKey(_ status: AIGenerationLabCaseStatus) -> String {
        switch status {
        case .succeeded:
            return "Passed"
        case .partial:
            return "Partial"
        case .failed:
            return "Failed"
        }
    }

    private func resultStatusColor(_ status: AIGenerationLabCaseStatus) -> Color {
        switch status {
        case .succeeded:
            return .green
        case .partial:
            return .orange
        case .failed:
            return .red
        }
    }

    private func formattedDuration(_ milliseconds: Int) -> String {
        String(format: "%.1fs", Double(milliseconds) / 1_000)
    }

    private var outputLanguagePicker: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(spacing: UIConstants.Spacing.small) {
                ForEach(AIGenerationOutputLanguageMode.allCases) { mode in
                    compactSelectionButton(
                        title: mode.localizedTitle(locale: appPreferences.resolvedLocale),
                        isSelected: viewModel.options.outputLanguageMode == mode
                    ) {
                        viewModel.options.outputLanguageMode = mode
                        if mode == .manual, viewModel.options.manualOutputLanguage == nil {
                            viewModel.options.manualOutputLanguage = AIGenerationLanguageHint.supportedOutputLanguages.first
                        }
                    }
                }
            }

            if viewModel.options.outputLanguageMode == .manual {
                Menu {
                    ForEach(AIGenerationLanguageHint.supportedOutputLanguages, id: \.languageCode) { language in
                        Button {
                            viewModel.options.manualOutputLanguage = language
                        } label: {
                            if viewModel.options.manualOutputLanguage?.languageCode == language.languageCode {
                                Label(
                                    language.localizedDisplayName(locale: appPreferences.resolvedLocale),
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(language.localizedDisplayName(locale: appPreferences.resolvedLocale))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: UIConstants.Spacing.small) {
                        Text(
                            viewModel.options.manualOutputLanguage?.localizedDisplayName(
                                locale: appPreferences.resolvedLocale
                            ) ?? localized("Choose a language")
                        )
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(themeManager.textPrimary)
                        .lineLimit(1)

                        Spacer(minLength: UIConstants.Spacing.small)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(themeManager.textSecondary)
                    }
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .frame(height: UIConstants.Size.buttonHeight)
                    .duoControlSurface(cornerRadius: UIConstants.Radius.card)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func compactOptionRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.textSecondary)
                .textCase(.uppercase)

            content()
        }
    }

    private func compactSelectionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isSelected ? themeManager.roleColor(.labelPrimaryForeground) : themeManager.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: UIConstants.Size.buttonHeight)
                .primarySelectionSurface(
                    isSelected: isSelected,
                    cornerRadius: UIConstants.Size.buttonHeight / 2
                )
        }
        .buttonStyle(.plain)
    }

    private var navigationBar: some View {
        HStack {
            ChromeCircleIconButton(systemName: "chevron.compact.left") {
                dismiss()
            }

            Spacer()
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .padding(.top, UIConstants.Layout.deckNavigationTopPadding)
        .padding(.bottom, UIConstants.Spacing.small)
    }

    private func sourceMetadata(_ source: AIGenerationLabSource) -> String {
        let size = ByteCountFormatter.string(fromByteCount: source.byteCount, countStyle: .file)

        switch source.kind {
        case .pdf:
            let pageCount = source.pageCount ?? 0
            let pages = AppLocalization.numbered(
                pageCount,
                singular: "%d page",
                plural: "%d pages",
                locale: appPreferences.resolvedLocale
            )
            return "\(localized("PDF")) · \(pages) · \(size)"
        case .photos:
            let imageCount = source.imageCount ?? 0
            let images = AppLocalization.numbered(
                imageCount,
                singular: "%d image",
                plural: "%d images",
                locale: appPreferences.resolvedLocale
            )
            return "\(images) · \(size)"
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: appPreferences.resolvedLocale)
    }
}
#endif
