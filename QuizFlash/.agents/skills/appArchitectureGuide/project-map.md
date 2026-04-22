---
trigger: always_on
---

# QuizFlash Project Map

## Contents

- Root entry points
- Shared infrastructure
- Domain and persistence
- Feature areas
- Common starting points

## Root Entry Points

- `QuizFlash/App/QuizFlashApp.swift`: App bootstrap, shared environment injection, model-container setup, early pool warm-up.
- `QuizFlash/Core/Navigation/RootView.swift`: Auth gate and top-level entry switching.
- `QuizFlash/Core/Navigation/MainAppView.swift`: Root tab coordinator, tab-bar visibility plumbing, navigation-stack wiring.

## Shared Infrastructure

- Navigation: `QuizFlash/Core/Navigation/NavigationManager.swift`, `QuizFlash/Core/Navigation/DeckNavigationValue.swift`, `QuizFlash/Core/Navigation/TabBar/*`
- Design system: `QuizFlash/Core/DesignSystem/Theme/UIConstants.swift`, `QuizFlash/Core/DesignSystem/Theme/ThemeManager.swift`
- Helpers: `QuizFlash/Core/Helpers/ImageCache.swift`, `QuizFlash/Core/Helpers/*`
- Scroll restoration: `QuizFlash/Core/Helpers/ScrollPositionRestorer.swift`
- Safe fetches and extensions: `QuizFlash/Core/Extensions/ModelContext+SafeFetch.swift`, `QuizFlash/Core/Extensions/LibraryExtension.swift`
- Custom immersive sheet: `QuizFlash/Core/DesignSystem/Modifiers/View+FullScreenSheet.swift`
- Web view pool: `QuizFlash/Features/DeckEditor/Components/MixedMathTextView.swift`
- AI services: `QuizFlash/Services/AI/*`
- Search services: `QuizFlash/Services/Search/*`
- Auth and sharing: `QuizFlash/Services/Auth/AuthManager.swift`, `QuizFlash/Services/Storage/DeckSharingManager.swift`

## Domain And Persistence

- Models: `QuizFlash/Domain/Models/*.swift`
- Repository actor for card reads: `QuizFlash/Domain/Repositories/CardFetchActor.swift`
- Safe ID lookup helper: `QuizFlash/Core/Extensions/ModelContext+SafeFetch.swift`
- Long-form architecture note: `QuizFlash/Docs/Arhitectura_Definitiva_Gestiune_Memorie_QuizFlash_iOS17.md`

## Feature Areas

- `QuizFlash/Features/Home/*`: Dashboard, folders, recent decks, calendar, home view models
- `QuizFlash/Features/Library/*`: Search, grouping, selection, library layout, library view model
- `QuizFlash/Features/DeckDetails/*`: Deck screen, deck stats, grid, menu controls, sharing, deck view model
- `QuizFlash/Features/DeckEditor/*`: Create/edit flows, zone logic, AI generation UI, editor components
- `QuizFlash/Features/PlayMode/*`: Review gameplay, card presentation, play-mode view models
- `QuizFlash/Features/Settings/*`: Theme and appearance settings
- `QuizFlash/Features/Auth/*`: Login flow

## Common Starting Points

- Add or refactor a screen: start with the target `Features/*/Views/` file, then inspect the paired `ViewModels/` file and `MainAppView.swift` or `NavigationManager.swift` if navigation changes are involved.
- Change deck or card loading: inspect `QuizFlash/Features/DeckDetails/ViewModels/DeckViewModel.swift` and `QuizFlash/Domain/Repositories/CardFetchActor.swift` first.
- Change search behavior or library grouping: inspect `QuizFlash/Features/Library/ViewModels/LibraryViewModel.swift`, `QuizFlash/Services/Search/SearchEngine.swift`, and `QuizFlash/Services/Search/LibrarySearchActor.swift`.
- Change editor rendering, math, or rich content: inspect `QuizFlash/Features/DeckEditor/Views/ZoneView.swift`, `QuizFlash/Features/DeckEditor/Components/MixedMathTextView.swift`, and related `ZoneLogic/` files.
- Change AI generation or parsing: inspect `QuizFlash/Services/AI/AIFlashcardService.swift`, `QuizFlash/Services/AI/AIZoneParser.swift`, `QuizFlash/Services/AI/DocumentTextExtractor.swift`, and `QuizFlash/Features/DeckEditor/Views/AIGenerationView.swift`.
- Change colors, spacing, or global look: inspect `QuizFlash/Core/DesignSystem/Theme/UIConstants.swift`, `QuizFlash/Core/DesignSystem/Theme/ThemeManager.swift`, and the owning feature component.
- Change long-scroll behavior or iOS 17 scroll stability: inspect `QuizFlash/Core/Helpers/ScrollPositionRestorer.swift`, `QuizFlash/Features/Library/Components/LibraryLayout.swift`, and `QuizFlash/Features/DeckDetails/Views/DeckView.swift` first.
- Change custom full-screen modal behavior: inspect `QuizFlash/Core/DesignSystem/Modifiers/View+FullScreenSheet.swift` and its usages in `QuizFlash/Features/DeckDetails/Views/DeckView.swift`, `QuizFlash/Features/DeckEditor/Views/FlashcardEditorView.swift`, and `QuizFlash/Features/PlayMode/FlashCardsMode/Views/FlashCardsPlayModeView.swift`.
