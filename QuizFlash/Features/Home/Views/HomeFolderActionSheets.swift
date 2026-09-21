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
    @Environment(\.modelContext) private var context
    @Environment(\.fullScreenSheetDismiss) private var dismissSheet
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppPreferences.self) private var appPreferences
    @Query(sort: \DeckModel.createdAt, order: .reverse) private var allDecks: [DeckModel]

    let target: HomeFolderActionTarget
    let safeAreaInsets: UIEdgeInsets

    @State private var viewModel = LibraryViewModel()

    private var locale: Locale { appPreferences.resolvedLocale }
    private var candidateDecks: [DeckModel] {
        allDecks.filter { $0.folder?.persistentModelID != target.id }
    }
    private var snapshots: [LibraryDeckRowSnapshot] {
        LibraryGrouping.makeDeckSnapshots(from: candidateDecks)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            themeManager.screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(String(format: AppLocalization.string("Move decks to %@", locale: locale), locale: locale, target.title))
                        .font(.system(size: 25, weight: .black))
                        .foregroundStyle(themeManager.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ChromeSoftCircleSymbolButton(
                        systemName: "xmark",
                        accessibilityLabel: AppLocalization.string("Close", locale: locale),
                        action: { dismissSheet?() }
                    )
                }
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, safeAreaInsets.top + UIConstants.Spacing.medium)
                .padding(.bottom, UIConstants.Spacing.standard)

                if candidateDecks.isEmpty {
                    ContentUnavailableView(
                        AppLocalization.string("No decks available to move", locale: locale),
                        systemImage: "rectangle.stack"
                    )
                    .foregroundStyle(themeManager.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            LibraryFlatListView(
                                decks: snapshots,
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
                        .padding(.bottom, 130)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            if !candidateDecks.isEmpty {
                BottomChromeContainer(
                    kind: .selection,
                    bottomPadding: BottomChromeInsets.selection(physicalSafeBottom: safeAreaInsets.bottom)
                ) {
                    SelectionActionToolbar(
                        selectedCount: viewModel.selectedDecks.count,
                        actions: [
                            .text(
                                id: "select-all",
                                title: AppLocalization.string("Select All", locale: locale),
                                accessibilityLabel: AppLocalization.string("Select All", locale: locale),
                                action: selectAll
                            ),
                            .text(
                                id: "move-here",
                                title: AppLocalization.string("Move Here", locale: locale),
                                accessibilityLabel: AppLocalization.string("Move Here", locale: locale),
                                isEnabled: !viewModel.selectedDecks.isEmpty,
                                action: moveSelectedDecks
                            ),
                        ]
                    )
                }
            }
        }
        .onAppear { viewModel.enterSelectionMode() }
        .modifier(LibraryAlerts(viewModel: viewModel))
    }

    private func selectAll() {
        if viewModel.areAllVisibleDecksSelected(in: candidateDecks) {
            viewModel.selectedDecks.subtract(candidateDecks.map(\.persistentModelID))
        } else {
            viewModel.selectAllVisibleDecks(from: candidateDecks)
        }
    }

    private func moveSelectedDecks() {
        guard let folder = context.safeModel(for: target.id, as: FolderModel.self) else { return }
        viewModel.moveSelectedDecks(from: candidateDecks, to: folder, context: context)
        if !viewModel.showMoveError, viewModel.selectedDecks.isEmpty {
            dismissSheet?()
        }
    }
}
