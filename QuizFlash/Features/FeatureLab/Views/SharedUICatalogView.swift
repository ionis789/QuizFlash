//
//  SharedUICatalogView.swift
//  QuizFlash
//
//  Centralized inventory of shared views and global modifiers used across the app.
//

import SwiftUI
struct SharedUICatalogView: View {
    private let runtime = FeatureLabFixtures.shared
    private let horizontalInset = UIConstants.Spacing.large

    @State private var searchText = ""
    @State private var filter: SharedUICatalogFilter = .all

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredEntries: [SharedUICatalogEntry] {
        Self.entries.filter { entry in
            matchesFilter(entry) && matchesSearch(entry)
        }
    }

    private var featuredViewEntries: [SharedUICatalogEntry] {
        filteredEntries.filter { $0.isFeatured && $0.kind == .view }
    }

    private var featuredModifierEntries: [SharedUICatalogEntry] {
        filteredEntries.filter { $0.isFeatured && $0.kind == .modifier }
    }

    private var registrySections: [SharedUICatalogRegistrySection] {
        SharedUICatalogRegistrySection.allCases.filter { section in
            filteredEntries.contains(where: { $0.section == section })
        }
    }

    private var trackedViewCount: Int {
        Self.entries.filter { $0.kind == .view }.count
    }

    private var trackedModifierCount: Int {
        Self.entries.filter { $0.kind == .modifier }.count
    }

    private var featuredCount: Int {
        Self.entries.filter(\.isFeatured).count
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - (horizontalInset * 2), 0)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                    LargeScreenTitle(title: "Shared UI Catalog")

                    SharedUICatalogIntroCard(
                        trackedViewCount: trackedViewCount,
                        trackedModifierCount: trackedModifierCount,
                        featuredCount: featuredCount
                    )

                    filterSection

                    if featuredViewEntries.isEmpty && featuredModifierEntries.isEmpty && registrySections.isEmpty {
                        SharedUICatalogEmptyState(query: query)
                    } else {
                        if !featuredViewEntries.isEmpty {
                            SharedUICatalogSectionHeader(
                                title: "Featured Views",
                                subtitle: "Live demos for the shared surfaces you are most likely to tweak globally."
                            )

                            ForEach(featuredViewEntries) { entry in
                                SharedUICatalogShowcaseCard(entry: entry) {
                                    demo(for: entry)
                                }
                            }
                        }

                        if !featuredModifierEntries.isEmpty {
                            SharedUICatalogSectionHeader(
                                title: "Featured Modifiers",
                                subtitle: "Interactive samples for the styling and presentation primitives reused across the app."
                            )

                            ForEach(featuredModifierEntries) { entry in
                                SharedUICatalogShowcaseCard(entry: entry) {
                                    demo(for: entry)
                                }
                            }
                        }

                        SharedUICatalogSectionHeader(
                            title: "Registry",
                            subtitle: "Single-source inventory of shared views and modifiers with their edit locations."
                        )

                        ForEach(registrySections) { section in
                            SharedUICatalogRegistryCard(
                                section: section,
                                entries: filteredEntries.filter { $0.section == section }
                            )
                        }
                    }
                }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, UIConstants.Spacing.large)
                    .padding(.bottom, UIConstants.Size.bottomChromeBarHeight + 120)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Shared UI")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search views, modifiers, or file paths")
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Picker("Catalog Filter", selection: $filter) {
                ForEach(SharedUICatalogFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
                .pickerStyle(.segmented)
        }
            .padding(UIConstants.Spacing.large)
            .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func matchesFilter(_ entry: SharedUICatalogEntry) -> Bool {
        switch filter {
        case .all:
            true
        case .views:
            entry.kind == .view
        case .modifiers:
            entry.kind == .modifier
        }
    }

    private func matchesSearch(_ entry: SharedUICatalogEntry) -> Bool {
        guard !query.isEmpty else { return true }
        return entry.searchableText.localizedCaseInsensitiveContains(query)
    }

    @ViewBuilder
    private func demo(for entry: SharedUICatalogEntry) -> some View {
        switch entry.demo {
        case .libraryDeckListRow:
            LibraryDeckListRow(
                deck: runtime.libraryDeckRow,
                isFirstInSection: true,
                isSelecting: false,
                isSelected: false,
                onNavigate: { },
                onToggleSelection: { },
                onImport: { },
                onMoveToFolder: { },
                onDelete: { }
            )
                .padding(UIConstants.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )

        case .deckCardGridView:
            DeckCardGridView(
                cards: runtime.deckGridSections,
                isSelecting: false,
                selectedCards: [],
                isSuspended: false,
                onToggleSelection: { _ in },
                onTapCard: { _ in },
                onEditCard: { _ in },
                onConvertCard: { _ in },
                onTogglePinned: { _ in },
                onDeleteCard: { _ in }
            )

        case .homeRecentDeckCardView:
            HomeRecentDeckCardView(
                deck: runtime.recentDeck,
                usesRegularMetrics: false,
                action: { }
            )

        case .folderCardView:
            FolderCardView(
                folder: runtime.folder,
                usesRegularMetrics: false,
                action: { }
            )

        case .detailedCardRowView:
            DetailedCardRowView(
                card: runtime.draftCard,
                index: runtime.draftCard.cardNumber
            )

        case .settingsHeaderCard:
            SettingsHeaderCard(
                icon: "brain.head.profile",
                title: "Study Defaults",
                subtitle: "Large settings chrome with icon emphasis, badges, and shared spacing.",
                tint: .cyan,
                badges: ["Review", "Focus", "Daily Goal"]
            )

        case .settingsNavigationRow:
            SettingsNavigationRow(
                icon: "paintpalette.fill",
                tint: .pink,
                title: "Accent Color",
                detail: "Slim navigation row used across Settings surfaces.",
                value: "Sunset"
            )
                .padding(UIConstants.Spacing.large)
                .settingsCardBackground(cornerRadius: UIConstants.Radius.large)

        case .deckProgressView:
            DeckProgressView(
                progress: runtime.progress,
                stats: runtime.stats,
                deckCardCount: runtime.stats.totalCards
            )

        case .selectionToolbarControls:
            SharedUICatalogSelectionToolbarDemo()

        case .flashcardStyle:
            SharedUICatalogFlashcardStyleDemo()

        case .topNavigationChrome:
            SharedUICatalogTopNavigationChromeDemo()

        case .statusTextMotion:
            SharedUICatalogStatusTextMotionDemo()

        case .bottomChromeVisibility:
            SharedUICatalogBottomChromeVisibilityDemo()

        case .fullScreenSheet:
            SharedUICatalogFullScreenSheetDemo()

        case .none:
            EmptyView()
        }
    }
}

private enum SharedUICatalogFilter: String, CaseIterable, Identifiable {
    case all
    case views
    case modifiers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .views:
            "Views"
        case .modifiers:
            "Modifiers"
        }
    }
}

private enum SharedUICatalogEntryKind: String {
    case view = "View"
    case modifier = "Modifier"

    var tint: Color {
        switch self {
        case .view:
                .orange
        case .modifier:
                .cyan
        }
    }
}

private enum SharedUICatalogRegistrySection: String, CaseIterable, Identifiable {
    case featuredSurfaces
    case designSystemComponents
    case globalModifiers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featuredSurfaces:
            "Shared Feature Views"
        case .designSystemComponents:
            "Core Design System Views"
        case .globalModifiers:
            "Global Modifiers"
        }
    }

    var subtitle: String {
        switch self {
        case .featuredSurfaces:
            "Feature-owned surfaces reused or treated as source-of-truth UI across Home, Library, Deck, Editor, and Settings."
        case .designSystemComponents:
            "Shared building blocks that support cross-screen chrome, badges, and bottom bars."
        case .globalModifiers:
            "App-wide styling, presentation, and interaction primitives applied through View extensions."
        }
    }
}

private enum SharedUICatalogDemo {
    case libraryDeckListRow
    case deckCardGridView
    case homeRecentDeckCardView
    case folderCardView
    case detailedCardRowView
    case settingsHeaderCard
    case settingsNavigationRow
    case deckProgressView
    case selectionToolbarControls
    case flashcardStyle
    case topNavigationChrome
    case statusTextMotion
    case bottomChromeVisibility
    case fullScreenSheet
}

private struct SharedUICatalogEntry: Identifiable {
    let id: String
    let title: String
    let kind: SharedUICatalogEntryKind
    let summary: String
    let sourcePath: String
    let pairedOwnerPath: String?
    let usage: String
    let section: SharedUICatalogRegistrySection
    let isFeatured: Bool
    let demo: SharedUICatalogDemo?
    let keywords: [String]

    var searchableText: String {
        ([title, summary, sourcePath, pairedOwnerPath, usage] + keywords)
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

private extension SharedUICatalogView {
    static let entries: [SharedUICatalogEntry] = [
            .init(
            id: "library-deck-list-row",
            title: "LibraryDeckListRow",
            kind: .view,
            summary: "Primary Library deck row with context menu, title balancing, and selection-safe rendering.",
            sourcePath: "Features/Library/Components/LibraryDeckListRow.swift",
            pairedOwnerPath: "Features/Library/Components/LibraryGrouping.swift",
            usage: "Used by Library lists as the source of truth for deck-row presentation.",
            section: .featuredSurfaces,
            isFeatured: true,
            demo: .libraryDeckListRow,
            keywords: ["library", "row", "deck", "context menu", "selection"]
        ),
            .init(
            id: "deck-card-grid-view",
            title: "DeckCardGridView",
            kind: .view,
            summary: "Deck detail grid surface for card sections, grid cells, selection, and card-level context actions.",
            sourcePath: "Features/DeckDetails/Views/DeckCardGridView.swift",
            pairedOwnerPath: "Features/DeckDetails/ViewModels/DeckViewModel.swift",
            usage: "Used by DeckView to render grouped cards and all card-grid interactions.",
            section: .featuredSurfaces,
            isFeatured: true,
            demo: .deckCardGridView,
            keywords: ["deck", "grid", "cards", "selection", "pinned"]
        ),
            .init(
            id: "home-recent-deck-card",
            title: "HomeRecentDeckCardView",
            kind: .view,
            summary: "Compact ticket-style Home surface for recently opened decks.",
            sourcePath: "Features/Home/Components/HomeRecentDeckCardView.swift",
            pairedOwnerPath: nil,
            usage: "Used by Home recent-decks carousel.",
            section: .featuredSurfaces,
            isFeatured: true,
            demo: .homeRecentDeckCardView,
            keywords: ["home", "recent", "deck", "ticket", "carousel"]
        ),
            .init(
            id: "folder-card-view",
            title: "FolderCardView",
            kind: .view,
            summary: "Folder surface with layered depth and shared widget chrome.",
            sourcePath: "Features/Home/Components/FolderCardView.swift",
            pairedOwnerPath: nil,
            usage: "Used by Home folder strips and folder browsing entry points.",
            section: .featuredSurfaces,
            isFeatured: true,
            demo: .folderCardView,
            keywords: ["folder", "home", "card", "widget"]
        ),
            .init(
            id: "detailed-card-row-view",
            title: "DetailedCardRowView",
            kind: .view,
            summary: "Rich deck-editor row with content summary, chips, and compact/full presentation modes.",
            sourcePath: "Features/DeckEditor/Components/DetailedCardRowView.swift",
            pairedOwnerPath: nil,
            usage: "Used by the deck editor list and draft-card previews.",
            section: .featuredSurfaces,
            isFeatured: true,
            demo: .detailedCardRowView,
            keywords: ["editor", "draft", "card", "row", "preview"]
        ),
            .init(
            id: "settings-header-card",
            title: "SettingsHeaderCard",
            kind: .view,
            summary: "Large header chrome for settings sections with icon block and adaptive badge grid.",
            sourcePath: "Features/Settings/Views/SettingsComponents.swift",
            pairedOwnerPath: nil,
            usage: "Used by Settings feature for section hero cards and grouped headers.",
            section: .featuredSurfaces,
            isFeatured: true,
            demo: .settingsHeaderCard,
            keywords: ["settings", "header", "badges", "hero"]
        ),
            .init(
            id: "settings-navigation-row",
            title: "SettingsNavigationRow",
            kind: .view,
            summary: "Reusable settings row pattern for icon, detail text, value text, and chevron navigation.",
            sourcePath: "Features/Settings/Views/SettingsComponents.swift",
            pairedOwnerPath: nil,
            usage: "Used across Settings navigation groups and settings cards.",
            section: .featuredSurfaces,
            isFeatured: true,
            demo: .settingsNavigationRow,
            keywords: ["settings", "row", "navigation", "value"]
        ),
            .init(
            id: "deck-progress-view",
            title: "DeckProgressView",
            kind: .view,
            summary: "Progress breakdown surface that renders precomputed deck state without owning business logic.",
            sourcePath: "Features/DeckDetails/Components/DeckProgressView.swift",
            pairedOwnerPath: "Features/DeckDetails/ViewModels/DeckViewModel.swift",
            usage: "Used by DeckView overlays and deck summary areas.",
            section: .featuredSurfaces,
            isFeatured: true,
            demo: .deckProgressView,
            keywords: ["progress", "deck", "stats", "mastered", "learning"]
        ),
            .init(
            id: "selection-toolbar-controls",
            title: "Selection Toolbar Controls",
            kind: .view,
            summary: "Shared capsule, text, and icon controls used by multi-select toolbars.",
            sourcePath: "Core/DesignSystem/Components/SelectionToolbarControls.swift",
            pairedOwnerPath: nil,
            usage: "Used by selection toolbars across Library and Deck surfaces.",
            section: .designSystemComponents,
            isFeatured: true,
            demo: .selectionToolbarControls,
            keywords: ["selection", "toolbar", "capsule", "icon", "badge"]
        ),
            .init(
            id: "bottom-chrome-container",
            title: "BottomChromeContainer",
            kind: .view,
            summary: "Shared floating bottom-chrome host used to keep persistent bottom controls aligned and safe-area aware.",
            sourcePath: "Core/DesignSystem/Components/BottomChromeContainer.swift",
            pairedOwnerPath: nil,
            usage: "Used for the floating tab bar and other persistent bottom chrome.",
            section: .designSystemComponents,
            isFeatured: false,
            demo: nil,
            keywords: ["bottom chrome", "tab bar", "floating"]
        ),
            .init(
            id: "collapsible-title-chrome",
            title: "CollapsibleTitleChrome",
            kind: .view,
            summary: "Shared title chrome that coordinates large-title collapse and top-bar reveal behavior.",
            sourcePath: "Core/DesignSystem/Components/CollapsibleTitleChrome.swift",
            pairedOwnerPath: nil,
            usage: "Used by scroll-driven screens that need collapsing hero titles.",
            section: .designSystemComponents,
            isFeatured: false,
            demo: nil,
            keywords: ["collapsible", "title", "chrome", "scroll"]
        ),
            .init(
            id: "avatar-view",
            title: "AvatarView",
            kind: .view,
            summary: "Shared circular avatar surface with glass-style action affordance.",
            sourcePath: "Core/DesignSystem/Components/AvatarView.swift",
            pairedOwnerPath: nil,
            usage: "Used anywhere the app needs a user/avatar identity surface.",
            section: .designSystemComponents,
            isFeatured: false,
            demo: nil,
            keywords: ["avatar", "profile", "identity"]
        ),
            .init(
            id: "standard-sheet-top-strip-background",
            title: "StandardSheetTopStripBackground",
            kind: .view,
            summary: "Shared immersive sheet background strip that reacts to full-screen-sheet drag progress.",
            sourcePath: "Features/DeckEditor/Views/CardPreviewModeView.swift",
            pairedOwnerPath: "Core/DesignSystem/Modifiers/View+FullScreenSheet.swift",
            usage: "Used by immersive sheets in Deck Editor and AI generation flows.",
            section: .designSystemComponents,
            isFeatured: false,
            demo: nil,
            keywords: ["sheet", "background", "top strip", "drag progress"]
        ),
            .init(
            id: "flashcard-style",
            title: "flashcardStyle",
            kind: .modifier,
            summary: "Shared chrome for both flashcards and widget-like cards across study, deck, home, and settings surfaces.",
            sourcePath: "Core/DesignSystem/Modifiers/View+Styles.swift",
            pairedOwnerPath: nil,
            usage: "Used by play-mode flashcards plus dashboard, deck, editor, and settings widgets.",
            section: .globalModifiers,
            isFeatured: true,
            demo: .flashcardStyle,
            keywords: ["flashcard", "widget", "study", "surface", "play mode"]
        ),
            .init(
            id: "top-navigation-chrome",
            title: "topNavigationChrome",
            kind: .modifier,
            summary: "Shared top-bar inset treatment for Deck, Create, and Library navigation surfaces.",
            sourcePath: "Core/DesignSystem/Modifiers/View+Styles.swift",
            pairedOwnerPath: nil,
            usage: "Used on navigation chrome where large top spacing must stay consistent.",
            section: .globalModifiers,
            isFeatured: true,
            demo: .topNavigationChrome,
            keywords: ["top navigation", "chrome", "inset", "header"]
        ),
            .init(
            id: "status-text-motion",
            title: "statusTextMotion",
            kind: .modifier,
            summary: "Shared numeric/status text transition for counters and short live labels.",
            sourcePath: "Core/DesignSystem/Modifiers/View+Styles.swift",
            pairedOwnerPath: nil,
            usage: "Used for animated counters and compact live-state text across surfaces.",
            section: .globalModifiers,
            isFeatured: true,
            demo: .statusTextMotion,
            keywords: ["status", "text", "motion", "counter", "numeric"]
        ),
            .init(
            id: "bottom-chrome-visibility",
            title: "bottomChromeVisibility",
            kind: .modifier,
            summary: "Shared visibility motion for floating tab bars and other bottom chrome swaps.",
            sourcePath: "Core/DesignSystem/Modifiers/View+Styles.swift",
            pairedOwnerPath: nil,
            usage: "Used whenever persistent bottom controls appear, hide, or yield to selection bars.",
            section: .globalModifiers,
            isFeatured: true,
            demo: .bottomChromeVisibility,
            keywords: ["bottom chrome", "tab bar", "visibility", "animation"]
        ),
            .init(
            id: "full-screen-sheet",
            title: "fullScreenSheet",
            kind: .modifier,
            summary: "App-wide custom full-screen sheet wrapper with drag-dismiss coordination and background injection.",
            sourcePath: "Core/DesignSystem/Modifiers/View+FullScreenSheet.swift",
            pairedOwnerPath: nil,
            usage: "Used by Deck, Create, Play Mode, and immersive modal flows.",
            section: .globalModifiers,
            isFeatured: true,
            demo: .fullScreenSheet,
            keywords: ["full screen", "sheet", "drag dismiss", "modal"]
        ),
            .init(
            id: "full-screen-sheet-drag-activation-height",
            title: "fullScreenSheetDragActivationHeight",
            kind: .modifier,
            summary: "Preference-based companion modifier for scoping where full-screen-sheet drag dismiss can begin.",
            sourcePath: "Core/DesignSystem/Modifiers/View+FullScreenSheet.swift",
            pairedOwnerPath: nil,
            usage: "Used on sheet content to protect interactive top areas before drag dismiss activates.",
            section: .globalModifiers,
            isFeatured: false,
            demo: nil,
            keywords: ["drag activation", "sheet", "dismiss"]
        ),
            .init(
            id: "app-screen-background",
            title: "appScreenBackground",
            kind: .modifier,
            summary: "Root-surface background modifier that prevents UIKit fallback greys during resize or presentation changes.",
            sourcePath: "Core/DesignSystem/Modifiers/View+Styles.swift",
            pairedOwnerPath: "Core/DesignSystem/Theme/ThemeManager.swift",
            usage: "Used on root screens that should inherit the app-managed background color.",
            section: .globalModifiers,
            isFeatured: false,
            demo: nil,
            keywords: ["screen background", "theme", "root background"]
        ),
            .init(
            id: "custom-context-menu",
            title: "customContextMenu",
            kind: .modifier,
            summary: "Reusable custom menu system for long-press actions with preview lift and shared layout resolution.",
            sourcePath: "Core/DesignSystem/Components/CustomContextMenu.swift",
            pairedOwnerPath: "Features/FeatureLab/Views/ContextMenuLabView.swift",
            usage: "Used by Library and Deck card surfaces. Deep validation lives in Context Menu Lab.",
            section: .globalModifiers,
            isFeatured: false,
            demo: nil,
            keywords: ["context menu", "preview", "long press", "menu"]
        ),
            .init(
            id: "dismiss-keyboard-on-background-tap",
            title: "dismissKeyboardOnBackgroundTap",
            kind: .modifier,
            summary: "UIKit-backed keyboard dismissal recognizer that ignores interactive controls.",
            sourcePath: "Core/DesignSystem/Modifiers/KeyboardDismissModifier.swift",
            pairedOwnerPath: nil,
            usage: "Used on text-entry surfaces that need reliable background-tap keyboard dismissal.",
            section: .globalModifiers,
            isFeatured: false,
            demo: nil,
            keywords: ["keyboard", "dismiss", "background tap", "text input"]
        ),
            .init(
            id: "swipe-back",
            title: "swipeBack",
            kind: .modifier,
            summary: "Interactive edge-swipe-back gesture with local-host and window-level attachment options.",
            sourcePath: "Core/DesignSystem/Modifiers/SwipeBackModifier.swift",
            pairedOwnerPath: nil,
            usage: "Used on screens and sheet-hosted flows that need custom back gesture behavior.",
            section: .globalModifiers,
            isFeatured: false,
            demo: nil,
            keywords: ["swipe back", "gesture", "edge", "navigation"]
        ),
            .init(
            id: "scroll-proximity-effect",
            title: "scrollProximityEffect",
            kind: .modifier,
            summary: "3D fold, dissolve, blur, and scale effect driven by scroll distance from the top edge.",
            sourcePath: "Core/Helpers/ScrollProximityEffect.swift",
            pairedOwnerPath: nil,
            usage: "Used on scroll-driven surfaces that need theatrical exit motion near the top edge.",
            section: .globalModifiers,
            isFeatured: false,
            demo: nil,
            keywords: ["scroll", "proximity", "3d", "blur", "dissolve"]
        )
    ]
}

private struct SharedUICatalogIntroCard: View {
    let trackedViewCount: Int
    let trackedModifierCount: Int
    let featuredCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            HStack(spacing: UIConstants.Spacing.medium) {
                SharedUICatalogMetricCard(value: "\(trackedViewCount)", label: "Views", tint: .orange)
                SharedUICatalogMetricCard(value: "\(trackedModifierCount)", label: "Modifiers", tint: .cyan)
                SharedUICatalogMetricCard(value: "\(featuredCount)", label: "Live Demos", tint: .green)
            }
        }
            .padding(UIConstants.Spacing.large)
            .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.maximum, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

private struct SharedUICatalogMetricCard: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(tint)

            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UIConstants.Spacing.medium)
            .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}

private struct SharedUICatalogSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SharedUICatalogShowcaseCard<Demo: View>: View {
    let entry: SharedUICatalogEntry
    @ViewBuilder let demo: () -> Demo

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(entry.summary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                SharedUICatalogKindPill(kind: entry.kind)
            }

            SharedUICatalogMetadataBlock(entry: entry)

            demo()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UIConstants.Spacing.large)
            .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.maximum, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

private struct SharedUICatalogKindPill: View {
    let kind: SharedUICatalogEntryKind

    var body: some View {
        Text(kind.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(kind.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(kind.tint.opacity(0.12), in: Capsule())
    }
}

private struct SharedUICatalogMetadataBlock: View {
    let entry: SharedUICatalogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SharedUICatalogMetadataRow(label: "Source", value: entry.sourcePath)

            if let pairedOwnerPath = entry.pairedOwnerPath {
                SharedUICatalogMetadataRow(label: "Paired Owner", value: pairedOwnerPath)
            }

            SharedUICatalogMetadataRow(label: "Used In", value: entry.usage)
        }
    }
}

private struct SharedUICatalogMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SharedUICatalogRegistryCard: View {
    let section: SharedUICatalogRegistrySection
    let entries: [SharedUICatalogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            VStack(alignment: .leading, spacing: 6) {
                Text(section.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(section.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: UIConstants.Spacing.medium) {
                ForEach(entries) { entry in
                    SharedUICatalogRegistryRow(entry: entry)
                }
            }
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UIConstants.Spacing.large)
            .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct SharedUICatalogRegistryRow: View {
    let entry: SharedUICatalogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: UIConstants.Spacing.medium) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                SharedUICatalogKindPill(kind: entry.kind)

                Spacer(minLength: 0)
            }

            Text(entry.summary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.sourcePath)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let pairedOwnerPath = entry.pairedOwnerPath {
                Text("Owner: \(pairedOwnerPath)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(entry.usage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UIConstants.Spacing.medium)
            .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct SharedUICatalogEmptyState: View {
    let query: String

    var body: some View {
        VStack(spacing: UIConstants.Spacing.medium) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.tertiary)

            Text("No catalog matches")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Nothing in the shared UI registry matches “\(query)”.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .padding(.horizontal, UIConstants.Spacing.large)
            .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

private struct SharedUICatalogMiniStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SharedUICatalogFlashcardStyleDemo: View {
    @State private var flashcardBaseBorderBlurRadius: CGFloat = 3
    @State private var widgetBaseBorderBlurRadius: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            VStack(alignment: .leading, spacing: 12) {
                Text("What is eventual consistency?")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text("A distributed-system model where replicas converge over time instead of synchronizing immediately.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
                .padding(UIConstants.Spacing.large)
                .flashcardStyle(
                cornerRadius: 30,
                shadowRadius: 22,
                baseBorderBlurRadius: flashcardBaseBorderBlurRadius
            )

            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Focus Streak")
                            .font(.headline.weight(.semibold))
                        Text("8 sessions this week")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text("+12%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }

                HStack(spacing: UIConstants.Spacing.medium) {
                    SharedUICatalogMiniStat(title: "Due", value: "9")
                    SharedUICatalogMiniStat(title: "Done", value: "27")
                    SharedUICatalogMiniStat(title: "XP", value: "1240")
                }
            }
            .padding(UIConstants.Spacing.large)
            .flashcardStyle(
                cornerRadius: 28,
                surfaceRole: .widget,
                baseBorderBlurRadius: widgetBaseBorderBlurRadius
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Flashcard Border Radius")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    Spacer(minLength: 0)

                    Text(Double(flashcardBaseBorderBlurRadius).formatted(.number.precision(.fractionLength(1))))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Slider(value: $flashcardBaseBorderBlurRadius, in: 0...14)
                    .tint(.white.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Widget Border Radius")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    Spacer(minLength: 0)

                    Text(Double(widgetBaseBorderBlurRadius).formatted(.number.precision(.fractionLength(1))))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Slider(value: $widgetBaseBorderBlurRadius, in: 0...14)
                    .tint(.white.opacity(0.85))
            }
        }
    }
}

private struct SharedUICatalogTopNavigationChromeDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Color.clear
                .frame(height: 1)
            HStack {
                Text("Deck Title")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
                .topNavigationChrome()
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, UIConstants.Spacing.medium)
            .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct SharedUICatalogStatusTextMotionDemo: View {
    @State private var dueCount = 9

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("Due Today")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            Text("\(dueCount)")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
                .statusTextMotion(trigger: dueCount)

            HStack(spacing: UIConstants.Spacing.medium) {
                Button("Decrease") {
                    dueCount = max(0, dueCount - 1)
                }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 38)

                Button("Increase") {
                    dueCount += 1
                }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
            }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

private struct SharedUICatalogBottomChromeVisibilityDemo: View {
    @State private var isVisible = true

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Toggle(isOn: $isVisible.animation(.bottomChromeSpring)) {
                Text("Bottom chrome visible")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
                .tint(.green)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 120)

                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("Tab Bar")
                        .font(.subheadline.weight(.semibold))
                }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .padding(.bottom, 14)
                    .bottomChromeVisibility(isVisible, hiddenOffset: 40)
            }
        }
    }
}

private struct SharedUICatalogSelectionToolbarDemo: View {
    var body: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            SelectionToolbarCapsuleButton(
                action: { },
                accessibilityLabel: "Move"
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("Move")
                        .font(.subheadline.weight(.semibold))
                }
                    .foregroundStyle(.primary)
            }

            SelectionToolbarTextButton(
                title: "Archive",
                accessibilityLabel: "Archive",
                tint: .secondary,
                action: { }
            )

            SelectionToolbarIconButton(
                isEnabled: true,
                accessibilityLabel: "Delete",
                badgeCount: 3,
                action: { }
            ) {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)
        }
    }
}

struct SharedUICatalogFullScreenSheetDemo: View {
    enum HeightPreset: String, CaseIterable, Identifiable {
        case full
        case medium
        case small
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .full: return "Full"
            case .medium: return "Medium"
            case .small: return "Small"
            case .custom: return "Custom"
            }
        }
    }

    enum BackgroundPreset: String, CaseIterable, Identifiable {
        case black
        case slate
        case ember

        var id: String { rawValue }

        var title: String {
            switch self {
            case .black: return "Black"
            case .slate: return "Slate"
            case .ember: return "Ember"
            }
        }
    }

    @State private var isPresented = false
    @State private var heightPreset: HeightPreset = .medium
    @State private var customHeightFraction: Double = 0.76
    @State private var topCornerRadius: Double = UIConstants.Radius.maximum
    @State private var dragActivationFraction: Double = 0.22
    @State private var showsDragIndicator = true
    @State private var dragIndicatorTopPadding: Double = UIConstants.Spacing.extraLarge
    @State private var backgroundPreset: BackgroundPreset = .black

    private var sheetConfiguration: FullScreenSheetConfiguration {
        FullScreenSheetConfiguration(
            ignoresSafeArea: true,
            heightMode: resolvedHeightMode,
            topCornerRadius: CGFloat(topCornerRadius),
            dragActivationArea: .fraction(CGFloat(dragActivationFraction)),
            showsDragIndicator: showsDragIndicator,
            dragIndicatorTopPadding: CGFloat(dragIndicatorTopPadding),
            backgroundReceivesDragProgress: true,
            appliesDefaultDragTopOverlay: false
        )
    }

    private var resolvedHeightMode: FullScreenSheetHeightMode {
        switch heightPreset {
        case .full:
            return .fullScreen
        case .medium:
            return .medium
        case .small:
            return .small
        case .custom:
            return .custom(CGFloat(customHeightFraction))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Button {
                isPresented = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.badge.plus")
                    Text("Open Sample Sheet")
                }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
            }
                .buttonStyle(.plain)

            Text("Launches a live `fullScreenSheet` playground. Change the controls inside the sheet and the container updates in real time.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
            .fullScreenSheet(
            isPresented: $isPresented,
            configuration: sheetConfiguration
        ) { safeAreaInsets in
            SharedUICatalogSampleSheet(
                safeAreaInsets: safeAreaInsets,
                heightPreset: $heightPreset,
                customHeightFraction: $customHeightFraction,
                topCornerRadius: $topCornerRadius,
                dragActivationFraction: $dragActivationFraction,
                showsDragIndicator: $showsDragIndicator,
                dragIndicatorTopPadding: $dragIndicatorTopPadding,
                backgroundPreset: $backgroundPreset
            )
        } background: {
            SharedUICatalogSheetDemoBackground(preset: backgroundPreset)
        }
    }
}

private struct SharedUICatalogSheetDemoBackground: View {
    let preset: SharedUICatalogFullScreenSheetDemo.BackgroundPreset

    @Environment(\.fullScreenSheetDragProgress) private var dragProgress

    private var overlayOpacity: Double {
        min(dragProgress / 0.10, 1.0)
    }

    var body: some View {
        ZStack {
            baseBackground

            topOverlay
                .opacity(overlayOpacity)
        }
    }

    @ViewBuilder
    private var baseBackground: some View {
        switch preset {
        case .black:
            Color.black
        case .slate:
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.08, blue: 0.16), Color(red: 0.10, green: 0.14, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ember:
            LinearGradient(
                colors: [Color(red: 0.24, green: 0.10, blue: 0.06), Color(red: 0.56, green: 0.22, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var topOverlay: some View {
        LinearGradient(
            stops: [
                    .init(color: topOverlayColor.opacity(0.92), location: 0.00),
                    .init(color: topOverlayColor.opacity(0.72), location: 0.06),
                    .init(color: .clear, location: 0.30)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topOverlayColor: Color {
        switch preset {
        case .black:
            return Color(red: 0.12, green: 0.12, blue: 0.12)
        case .slate:
            return Color(red: 0.16, green: 0.20, blue: 0.30)
        case .ember:
            return Color(red: 0.38, green: 0.17, blue: 0.08)
        }
    }
}

private struct SharedUICatalogSampleSheet: View {
    let safeAreaInsets: UIEdgeInsets
    @Binding var heightPreset: SharedUICatalogFullScreenSheetDemo.HeightPreset
    @Binding var customHeightFraction: Double
    @Binding var topCornerRadius: Double
    @Binding var dragActivationFraction: Double
    @Binding var showsDragIndicator: Bool
    @Binding var dragIndicatorTopPadding: Double
    @Binding var backgroundPreset: SharedUICatalogFullScreenSheetDemo.BackgroundPreset

    @Environment(\.fullScreenSheetDismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                    Text("Shared Sheet Playground")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Change these controls while the sheet is open. Height, corner radius, drag zone, indicator, and background update immediately.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                    .padding(.top, safeAreaInsets.top + UIConstants.Spacing.large)

                demoCard(title: "Height Mode") {
                    Picker("Height Mode", selection: $heightPreset) {
                        ForEach(SharedUICatalogFullScreenSheetDemo.HeightPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                        .pickerStyle(.segmented)

                    if heightPreset == .custom {
                        demoSliderRow(
                            title: "Custom Height",
                            valueLabel: "\(Int(customHeightFraction * 100))%"
                        )
                        Slider(value: $customHeightFraction, in: 0.35 ... 1)
                    }
                }

                demoCard(title: "Top Surface") {
                    demoSliderRow(
                        title: "Top Corner Radius",
                        valueLabel: "\(Int(topCornerRadius)) pt"
                    )
                    Slider(value: $topCornerRadius, in: 0 ... 60)

                    Toggle("Show Drag Indicator", isOn: $showsDragIndicator)
                        .tint(ThemeManager.shared.accentColor.color)

                    if showsDragIndicator {
                        demoSliderRow(
                            title: "Indicator Top Padding",
                            valueLabel: "\(Int(dragIndicatorTopPadding)) pt"
                        )
                        Slider(value: $dragIndicatorTopPadding, in: 12 ... 40)
                    }
                }

                demoCard(title: "Drag") {
                    demoSliderRow(
                        title: "Drag Activation Zone",
                        valueLabel: "\(Int(dragActivationFraction * 100))%"
                    )
                    Slider(value: $dragActivationFraction, in: 0.08 ... 1)
                }

                demoCard(title: "Background") {
                    Picker("Background", selection: $backgroundPreset) {
                        ForEach(SharedUICatalogFullScreenSheetDemo.BackgroundPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                        .pickerStyle(.segmented)

                    Text("Background is rendered inside the shared sheet surface and clipped by the top corner radius.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Dismiss") {
                    dismiss?()
                }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
            }
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.bottom, max(safeAreaInsets.bottom, UIConstants.Spacing.large))
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func demoCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            content()
        }
            .padding(UIConstants.Spacing.large)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
            .overlay {
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    private func demoSliderRow(title: String, valueLabel: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: UIConstants.Spacing.medium)

            Text(valueLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
}
