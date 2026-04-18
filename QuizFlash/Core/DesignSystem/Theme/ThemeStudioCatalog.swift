//
//  ThemeStudioCatalog.swift
//  QuizFlash
//
//  Screen-first Theme Studio catalog for core product screens.
//

import Foundation

enum ThemeStudioScreenID: String, CaseIterable, Identifiable {
    case home = "Home"
    case library = "Library"
    case deckView = "DeckView"
    case create = "Create"
    case settings = "Settings"

    var id: String { rawValue }
    var title: String { rawValue }
}

enum ThemeStudioBindingTarget: Hashable, Identifiable {
    case role(ThemeColorRole)
    case token(ThemeColorToken)

    var id: String {
        switch self {
        case .role(let role):
            return "role.\(role.rawValue)"
        case .token(let token):
            return "token.\(token.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .role(let role):
            return role.title
        case .token(let token):
            return token.title
        }
    }
}

struct ThemeStudioColorSlotDescriptor: Identifiable, Hashable {
    let name: String
    let bindingTarget: ThemeStudioBindingTarget
    let isShared: Bool
    let note: String?

    var id: String { name }
}

struct ThemeStudioComponentDescriptor: Identifiable, Hashable {
    let swiftTypeName: String
    let note: String
    let componentKindID: String
    let slots: [ThemeStudioColorSlotDescriptor]

    var id: String { swiftTypeName }
}

struct ThemeStudioScreenDescriptor: Identifiable, Hashable {
    let id: ThemeStudioScreenID
    let title: String
    let components: [ThemeStudioComponentDescriptor]
}

enum ThemeStudioCatalog {
    static let screens: [ThemeStudioScreenDescriptor] = [
        ThemeStudioScreenDescriptor(
            id: .home,
            title: "Home",
            components: [
                component("HomeView", note: "Root canvas", kind: "screen.root.primary", slots: screenPrimarySlots),
                component("HomeCalendarSectionView", note: "Top calendar chrome", kind: "top.chrome.calendar", slots: [
                    slot("backgroundFill", .role(.screenBackgroundPrimary), true, "Uses the app shell canvas behind the compact calendar."),
                    slot("capsuleFill", .role(.buttonSurfaceFill), true, "Shared with floating chrome capsules and circular utility buttons."),
                    slot("iconTint", .role(.circularToolbarForeground), true, "Shared by Home, Library, and Deck top chrome buttons."),
                    slot("selectionFill", .role(.buttonPrimaryFill), true, "Used by the selected day treatment."),
                    slot("dangerTint", .token(.dangerPrimary), false, "Used by overdue or missed-day emphasis.")
                ]),
                component("HomeGreetingCardView", note: "Greeting summary widget", kind: "widget.card.standard", slots: widgetCardTextSlots),
                component("HomeRecentDeckCardView", note: "Recently opened deck card", kind: "widget.card.standard", slots: [
                    slot("backgroundFill", .role(.widgetSurfaceFill), true, widgetSurfaceNote),
                    slot("titleForeground", .token(.textPrimary), true, "Used by the deck title."),
                    slot("metaForeground", .token(.textSecondary), true, "Used by card count and secondary metadata.")
                ]),
                component("HomeExamGoalSummaryCard", note: "Exam pressure summary widget", kind: "widget.card.emphasis", slots: widgetEmphasisSlots),
                component("HomeWeeklyMomentumCard", note: "Weekly trend widget", kind: "widget.card.emphasis", slots: widgetEmphasisSlots),
                component("HomeSelectedDayInsightsCard", note: "Selected day insights widget", kind: "widget.card.emphasis", slots: widgetEmphasisSlots),
                component("FolderCardView", note: "Folder grid card", kind: "widget.card.standard", slots: [
                    slot("backgroundFill", .role(.widgetSurfaceFill), true, widgetSurfaceNote),
                    slot("titleForeground", .token(.textPrimary), true, "Used by the folder title."),
                    slot("metaForeground", .token(.textSecondary), true, "Used by the deck count."),
                    slot("accentFallback", .token(.brandPrimary), false, "Used when the folder has no custom colorHex.")
                ])
            ]
        ),
        ThemeStudioScreenDescriptor(
            id: .library,
            title: "Library",
            components: [
                component("LibraryLayout", note: "Root canvas and top chrome host", kind: "screen.root.primary", slots: screenPrimarySlots),
                component("LibraryTopBarView", note: "Search and navigation chrome", kind: "top.chrome.library", slots: [
                    slot("capsuleFill", .role(.buttonSurfaceFill), true, "Shared by the floating top chrome controls."),
                    slot("iconTint", .role(.circularToolbarForeground), true, "Shared by the circular top-bar icons."),
                    slot("backTint", .role(.backButtonForeground), true, "Used by the back capsule foreground."),
                    slot("titleForeground", .token(.textPrimary), true, "Used by the compact title treatment.")
                ]),
                component("LibraryDeckListRow", note: "Primary deck row", kind: "library.deck.row", slots: [
                    slot("titleForeground", .token(.textPrimary), true, "Used by the main deck title."),
                    slot("metaForeground", .token(.textSecondary), true, "Used by counts and metadata."),
                    slot("selectionFill", .role(.buttonPrimaryFill), true, "Used by the selected-row fill gradient.")
                ]),
                component("LibrarySectionHeader", note: "Grouped date/title header", kind: "library.section.header", slots: [
                    slot("titleForeground", .token(.textSecondary), false, "Used by the compact section title.")
                ]),
                component("LibrarySelectionBarView", note: "Bottom multi-select toolbar", kind: "selection.toolbar", slots: [
                    slot("clusterFill", .role(.selectionToolbarFill), true, "Background of the trailing action cluster."),
                    slot("clusterBorder", .role(.selectionToolbarBorder), true, "Border color for the trailing action cluster."),
                    slot("activeForeground", .token(.textPrimary), true, "Used by enabled actions and the Done capsule."),
                    slot("inactiveForeground", .token(.textSecondary), true, "Used by disabled actions."),
                    slot("dangerTint", .token(.dangerPrimary), true, "Used by the delete action.")
                ]),
                component("LibraryEmptyStateView", note: "No deck / no results state", kind: "empty.state.standard", slots: [
                    slot("accentTint", .token(.brandPrimary), true, "Used by the icon chip accent."),
                    slot("bodyForeground", .token(.textSecondary), true, "Used by helper copy.")
                ])
            ]
        ),
        ThemeStudioScreenDescriptor(
            id: .deckView,
            title: "DeckView",
            components: [
                component("DeckView", note: "Root grouped canvas", kind: "screen.root.grouped", slots: screenGroupedSlots),
                component("DeckCustomNavigationBar", note: "Top back capsule chrome", kind: "top.chrome.backCapsule", slots: [
                    slot("capsuleFill", .role(.buttonSurfaceFill), true, "Shared by capsule utility chrome."),
                    slot("backTint", .role(.backButtonForeground), true, "Used by back icon and label.")
                ]),
                component("DeckHeroView", note: "Hero summary and readiness header", kind: "deck.hero.summary", slots: [
                    slot("backgroundFill", .token(.backgroundPrimary), false, "Used by the lower hero surface."),
                    slot("accentFallback", .token(.brandPrimary), false, "Used when the deck has no custom accent.")
                ]),
                component("DeckHeaderView", note: "Deck title and summary header", kind: "deck.header.summary", slots: [
                    slot("accentFallback", .token(.brandPrimary), false, "Used for deck accent fallback treatments.")
                ]),
                component("DeckPlayModesView", note: "Study mode cards", kind: "widget.card.emphasis", slots: widgetEmphasisSlots),
                component("DeckSectionToolbar", note: "Grid/list section chrome", kind: "toolbar.section.action", slots: [
                    slot("capsuleFill", .role(.buttonSurfaceFill), true, "Shared by surface action buttons."),
                    slot("capsuleForeground", .role(.buttonSurfaceForeground), true, "Shared by surface action icons and labels."),
                    slot("dangerTint", .role(.buttonDangerForeground), true, "Used by destructive toolbar actions.")
                ]),
                component("DeckSelectionBottomBar", note: "Bottom multi-select toolbar", kind: "selection.toolbar", slots: [
                    slot("clusterFill", .role(.selectionToolbarFill), true, "Background of the action cluster."),
                    slot("clusterBorder", .role(.selectionToolbarBorder), true, "Border of the action cluster."),
                    slot("activeForeground", .token(.textPrimary), true, "Used by enabled actions."),
                    slot("inactiveForeground", .token(.textSecondary), true, "Used by disabled actions."),
                    slot("dangerTint", .token(.dangerPrimary), true, "Used by delete actions.")
                ])
            ]
        ),
        ThemeStudioScreenDescriptor(
            id: .create,
            title: "Create",
            components: [
                component("DeckWorkspaceView", note: "Root grouped canvas", kind: "screen.root.grouped", slots: screenGroupedSlots),
                component("DeckWorkspaceChrome", note: "Workspace top chrome", kind: "top.chrome.create", slots: [
                    slot("capsuleFill", .role(.buttonSurfaceFill), true, "Shared by create chrome capsules and buttons."),
                    slot("capsuleForeground", .role(.buttonSurfaceForeground), true, "Shared by create chrome labels and icons."),
                    slot("dangerTint", .role(.buttonDangerForeground), true, "Used by destructive and save emphasis actions.")
                ]),
                component("DetailedCardRowView", note: "Editor row card", kind: "editor.row.detailed", slots: [
                    slot("backgroundFill", .role(.widgetSurfaceFill), true, widgetSurfaceNote),
                    slot("accentFallback", .token(.brandPrimary), false, "Used by deck accent fallback treatments.")
                ]),
                component("CardPreviewModeView", note: "Preview panel surface", kind: "preview.panel.card", slots: [
                    slot("accentFallback", .token(.brandPrimary), false, "Used by preview highlights and state chips.")
                ]),
                component("AIGenerationSheetView", note: "AI generation surface", kind: "sheet.ai.generation", slots: [
                    slot("accentFallback", .token(.brandPrimary), false, "Used by the generation CTA and helper accents."),
                    slot("backgroundFill", .role(.widgetSurfaceFill), true, "Used by the larger AI summary cards.")
                ]),
                component("FloatingAIWorkspaceStatusMenu", note: "AI floating status panel", kind: "floating.ai.status", slots: [
                    slot("accentFallback", .token(.brandPrimary), false, "Used by status emphasis and runtime pills.")
                ])
            ]
        ),
        ThemeStudioScreenDescriptor(
            id: .settings,
            title: "Settings",
            components: [
                component("SettingsView", note: "Root grouped canvas", kind: "screen.root.grouped", slots: screenGroupedSlots),
                component("SettingsHeaderCard", note: "Profile header card", kind: "settings.card.hero", slots: settingsCardSlots),
                component("SettingsSectionCard", note: "Grouped settings section", kind: "settings.card.section", slots: settingsCardSlots + settingsTextSlots),
                component("SettingsNavigationRow", note: "Navigation row item", kind: "settings.row.navigation", slots: settingsTextSlots),
                component("SettingsToggleRow", note: "Toggle row item", kind: "settings.row.toggle", slots: settingsTextSlots),
                component("SettingsInfoCard", note: "Small informational card", kind: "settings.card.section", slots: settingsCardSlots + [
                    slot("detailForeground", .token(.textSecondary), true, "Used by supporting informational copy.")
                ])
            ]
        )
    ]

    static func screen(_ id: ThemeStudioScreenID) -> ThemeStudioScreenDescriptor {
        screens.first(where: { $0.id == id }) ?? screens[0]
    }

    static func linkedScreenIDs(for componentKindID: String) -> [ThemeStudioScreenID] {
        var ordered: [ThemeStudioScreenID] = []
        for screen in screens where screen.components.contains(where: { $0.componentKindID == componentKindID }) {
            ordered.append(screen.id)
        }
        return ordered
    }

    private static let widgetSurfaceNote = "Inherited from flashcardStyle(surfaceRole: .widget)."

    private static let screenPrimarySlots: [ThemeStudioColorSlotDescriptor] = [
        slot("backgroundFill", .role(.screenBackgroundPrimary), true, "Main canvas for full-screen primary surfaces.")
    ]

    private static let screenGroupedSlots: [ThemeStudioColorSlotDescriptor] = [
        slot("backgroundFill", .role(.screenBackgroundGrouped), true, "Main canvas for grouped and pushed settings-style surfaces.")
    ]

    private static let settingsCardSlots: [ThemeStudioColorSlotDescriptor] = [
        slot("backgroundFill", .role(.settingsCardFill), true, "Shared by settings cards and grouped settings sections."),
        slot("borderColor", .role(.settingsCardBorder), true, "Shared by settings card borders and dividers.")
    ]

    private static let settingsTextSlots: [ThemeStudioColorSlotDescriptor] = [
        slot("titleForeground", .token(.textPrimary), true, "Used by primary row and section titles."),
        slot("detailForeground", .token(.textSecondary), true, "Used by secondary row details and helper copy.")
    ]

    private static let widgetCardTextSlots: [ThemeStudioColorSlotDescriptor] = [
        slot("backgroundFill", .role(.widgetSurfaceFill), true, widgetSurfaceNote),
        slot("titleForeground", .token(.textPrimary), true, "Used by the main content title."),
        slot("detailForeground", .token(.textSecondary), true, "Used by supporting copy and labels.")
    ]

    private static let widgetEmphasisSlots: [ThemeStudioColorSlotDescriptor] = [
        slot("backgroundFill", .role(.widgetSurfaceFill), true, widgetSurfaceNote),
        slot("accentFallback", .token(.brandPrimary), false, "Used by global accent-driven highlights when the content has no custom tint.")
    ]

    private static func component(
        _ swiftTypeName: String,
        note: String,
        kind: String,
        slots: [ThemeStudioColorSlotDescriptor]
    ) -> ThemeStudioComponentDescriptor {
        ThemeStudioComponentDescriptor(
            swiftTypeName: swiftTypeName,
            note: note,
            componentKindID: kind,
            slots: slots
        )
    }

    private static func slot(
        _ name: String,
        _ bindingTarget: ThemeStudioBindingTarget,
        _ isShared: Bool,
        _ note: String?
    ) -> ThemeStudioColorSlotDescriptor {
        ThemeStudioColorSlotDescriptor(
            name: name,
            bindingTarget: bindingTarget,
            isShared: isShared,
            note: note
        )
    }
}
