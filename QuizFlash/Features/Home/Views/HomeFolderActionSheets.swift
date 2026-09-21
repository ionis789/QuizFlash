import SwiftUI
import SwiftData

enum HomeFolderSheetDestination: Identifiable, Equatable {
    case rename(HomeFolderActionTarget)
    case changeColor(HomeFolderActionTarget)
    case moveDecks(HomeFolderActionTarget)

    var id: String {
        switch self {
        case .rename(let target): "rename-\(target.id)"
        case .changeColor(let target): "color-\(target.id)"
        case .moveDecks(let target): "move-\(target.id)"
        }
    }
}

struct HomeFolderEditSheet: View {
    enum Mode {
        case rename
        case changeColor
    }

    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(\.fullScreenSheetDismiss) private var dismissSheet
    @Environment(\.fullScreenSheetTopChromeClearance) private var topChromeClearance
    @FocusState private var isTitleFocused: Bool

    let target: HomeFolderActionTarget
    let mode: Mode
    let safeAreaInsets: UIEdgeInsets
    let onSave: (String, String) -> Bool

    @State private var title: String
    @State private var colorHex: String

    private let colorOptions = ["#34C759", "#AF9FFF", "#FF9F0A", "#FF5C7A", "#32ADE6"]

    init(
        target: HomeFolderActionTarget,
        mode: Mode,
        safeAreaInsets: UIEdgeInsets,
        onSave: @escaping (String, String) -> Bool
    ) {
        self.target = target
        self.mode = mode
        self.safeAreaInsets = safeAreaInsets
        self.onSave = onSave
        _title = State(initialValue: target.title)
        _colorHex = State(initialValue: target.colorHex)
    }

    private var locale: Locale { appPreferences.resolvedLocale }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var heading: String {
        AppLocalization.string(mode == .rename ? "Rename Folder" : "Change Folder Color", locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            Text(heading)
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(themeManager.textPrimary)

            if mode == .rename {
                TextField(AppLocalization.string("Folder Name", locale: locale), text: $title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(themeManager.textPrimary)
                    .tint(themeManager.roleColor(.buttonPrimaryFill))
                    .focused($isTitleFocused)
                    .padding(UIConstants.Spacing.large)
                    .duoSurface(cornerRadius: 24)
            } else {
                HStack(spacing: UIConstants.Spacing.standard) {
                    ForEach(colorOptions, id: \.self) { hex in
                        colorButton(hex)
                    }

                    ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 38, height: 38)
                        .accessibilityLabel(AppLocalization.string("Custom Color", locale: locale))
                }
                .padding(UIConstants.Spacing.large)
                .duoSurface(cornerRadius: 24)
            }

            Button {
                if onSave(title, colorHex) {
                    dismissSheet?()
                }
            } label: {
                Text(AppLocalization.string("Save", locale: locale))
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(canSave ? themeManager.roleColor(.buttonPrimaryForeground) : themeManager.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(canSave ? themeManager.roleColor(.buttonPrimaryFill) : themeManager.roleColor(.widgetSurfaceFill)))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .padding(.top, max(topChromeClearance + 24, safeAreaInsets.top + 24))
        .padding(.bottom, max(safeAreaInsets.bottom, UIConstants.Spacing.standard))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if mode == .rename { isTitleFocused = true }
        }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: colorHex) ?? themeManager.brandPrimary },
            set: { colorHex = $0.toHex() ?? colorHex }
        )
    }

    private func colorButton(_ hex: String) -> some View {
        Button { colorHex = hex } label: {
            Circle()
                .fill(Color(hex: hex) ?? themeManager.brandPrimary)
                .frame(width: 38, height: 38)
                .overlay(Circle().strokeBorder(colorHex == hex ? themeManager.textPrimary : .clear, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.string("Label Color", locale: locale))
    }
}

struct MoveDecksToFolderSheet: View {
    @Environment(\.fullScreenSheetDismiss) private var dismissSheet
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppPreferences.self) private var appPreferences
    @Query(sort: \DeckModel.createdAt, order: .reverse) private var allDecks: [DeckModel]

    let target: HomeFolderActionTarget
    let safeAreaInsets: UIEdgeInsets
    let onMove: (Set<PersistentIdentifier>) -> Void

    @State private var viewModel = LibraryViewModel()
    @State private var deckSnapshots: [LibraryDeckRowSnapshot] = []
    @State private var isCommittingMove = false

    private var locale: Locale { appPreferences.resolvedLocale }
    private var candidateDecks: [DeckModel] {
        allDecks.filter { $0.folder?.persistentModelID != target.id }
    }
    private var deckQuerySignature: String {
        allDecks.map { deck in
            [
                "\(deck.persistentModelID.hashValue)",
                "\(deck.folder?.persistentModelID.hashValue ?? 0)",
                "\(deck.editedAt.timeIntervalSince1970.bitPattern)",
            ].joined(separator: ":")
        }
        .joined(separator: "|")
    }

    private var folderColor: Color {
        Color(hex: target.colorHex) ?? themeManager.brandPrimary
    }

    private var headerTopPadding: CGFloat {
        safeAreaInsets.top + UIConstants.Spacing.medium
    }

    private var headerContentHeight: CGFloat {
        UIConstants.Size.actionButton
    }

    private var headerContentBottom: CGFloat {
        headerTopPadding + headerContentHeight + UIConstants.Spacing.standard
    }

    private var moveTitle: AttributedString {
        let title = String(
            format: AppLocalization.string("Move to %@", locale: locale),
            locale: locale,
            target.title
        )
        var attributed = AttributedString(title)
        attributed.foregroundColor = themeManager.textPrimary
        if let range = attributed.range(of: target.title) {
            attributed[range].foregroundColor = folderColor
        }
        return attributed
    }

    var body: some View {
        ZStack {
            themeManager.screenBackground.ignoresSafeArea()

            if deckSnapshots.isEmpty {
                ContentUnavailableView(
                    AppLocalization.string("No decks available to move", locale: locale),
                    systemImage: "rectangle.stack"
                )
                .foregroundStyle(themeManager.textSecondary)
                .padding(.top, headerContentBottom)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        LibraryFlatListView(
                            decks: deckSnapshots,
                            showsContextMenus: false,
                            isSelecting: true,
                            selectedDeckIDs: viewModel.selectedDecks,
                            onNavigate: viewModel.toggleSelection,
                            onToggleSelection: viewModel.toggleSelection,
                            onExport: { _ in },
                            onMoveToFolder: { _ in },
                            onDelete: { _ in }
                        )
                    }
                    .padding(.top, headerContentBottom)
                    .padding(.bottom, 96 + safeAreaInsets.bottom)
                }
                .scrollIndicators(.hidden)
            }

            TopProgressiveBlurOverlay(
                topHeight: headerContentBottom,
                revealProgress: 1,
                tintColor: Color(ThemeColorToken.backgroundPrimary.assetName),
                configuration: .quizFlashDefault,
                revealAnimation: nil
            )
            .allowsHitTesting(false)

            Text(moveTitle)
                .font(.system(size: 25, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: headerContentHeight)
                .padding(.leading, UIConstants.Spacing.large)
                .padding(.trailing, UIConstants.Size.actionButton + (UIConstants.Spacing.medium * 2))
                .padding(.top, headerTopPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if !deckSnapshots.isEmpty {
                Button(action: moveSelectedDecks) {
                    Text(AppLocalization.string("Move", locale: locale))
                        .font(.system(size: 15, weight: .bold))
                        .frame(minWidth: 92)
                }
                .quizFlashButtonStyle(.primary, shape: .capsule, size: UIConstants.Size.actionButton)
                .disabled(viewModel.selectedDecks.isEmpty || isCommittingMove)
                .opacity(viewModel.selectedDecks.isEmpty || isCommittingMove ? 0.48 : 1)
                .padding(.bottom, safeAreaInsets.bottom + UIConstants.Spacing.medium)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .task(id: deckQuerySignature) {
            if !viewModel.isSelecting {
                viewModel.enterSelectionMode()
            }
            deckSnapshots = LibraryGrouping.makeDeckSnapshots(
                from: candidateDecks,
                includeCardKindPresence: false
            )
        }
    }

    private func moveSelectedDecks() {
        let selectedDeckIDs = viewModel.selectedDecks
        guard !selectedDeckIDs.isEmpty, !isCommittingMove else { return }
        isCommittingMove = true

        if let dismissSheet {
            dismissSheet {
                onMove(selectedDeckIDs)
            }
        } else {
            onMove(selectedDeckIDs)
        }
    }
}
