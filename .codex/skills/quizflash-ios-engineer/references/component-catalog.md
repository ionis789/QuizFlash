# Component Catalog

This catalog lists the reusable UI pieces that already exist in QuizFlash. Treat it as the first stop before creating a new button, card, menu, overlay, or presentation wrapper.

## Buttons & Menus

| Componentă | Fișier | Parametri cheie | Când se folosește |
|---|---|---|---|
| `SelectionToolbarIconButton` | `QuizFlash/Core/DesignSystem/Components/SelectionToolbarControls.swift` | `isEnabled`, `accessibilityLabel`, `badgeCount`, `action`, `label` | Icon-only actions inside selection toolbars in Library and Deck flows |
| `SelectionCountBadge` | `QuizFlash/Core/DesignSystem/Components/SelectionToolbarControls.swift` | `count` | Numeric badge attached to selection actions such as delete |
| `ToolbarButton` | `QuizFlash/Features/DeckEditor/Components/EditorFormatMenuBar.swift` | `icon`, `tint`, `isActive`, `action` | Formatting buttons inside the deck-editor toolbar |
| `FABMenuItem` | `QuizFlash/Features/DeckEditor/Components/FABMenuItemView.swift` | `icon`, `title`, `tint`, `action` | Expanded floating action menu items in editor/create flows |
| `ExportDeckButton` | `QuizFlash/Features/DeckDetails/Components/DeckSharingViews.swift` | `onExport`, `isExporting` | Simple export CTA when the parent owns export state |
| `HomeAvatarView` | `QuizFlash/Core/DesignSystem/Components/AvatarView.swift` | `router` | Profile/settings entry point in the Home chrome |
| `DirectionPopoverMenu` | `QuizFlash/Features/DeckEditor/Components/EditorFormatMenuBar.swift` | `activeDirection`, `accent`, `arrowRadius` | Radial direction-picker shown while dragging the add-zone control |

## Carduri, Rows & Stats

| Componentă | Fișier | Parametri cheie | Când se folosește |
|---|---|---|---|
| `FolderCardView` | `QuizFlash/Features/Home/Components/FolderCardView.swift` | `folder`, `action` | Grid folder cards on Home |
| `EmptyStatePlaceholderFolderCard` | `QuizFlash/Features/Home/Components/FolderCardView.swift` | `icon`, `message` | Empty slot in the Home folders grid |
| `HomeRecentDeckCardView` | `QuizFlash/Features/Home/Components/HomeRecentDeckCardView.swift` | `deck`, `action` | Horizontal carousel card for recently opened decks |
| `DailyGoalProgressCard` | `QuizFlash/Features/Home/Components/HomeStatsView.swift` | `cardsReviewed`, `dailyGoal` | Hero progress card for the Home daily activity section |
| `MiniStatCardView` | `QuizFlash/Features/Home/Components/HomeStatsView.swift` | `title`, `value`, `icon`, `color` | Secondary stat cards for Home metrics |
| `DeckRowView` | `QuizFlash/Features/DeckDetails/Components/DeckRowView.swift` | `deck` | Standard deck row card reused across library/folder surfaces |
| `LibraryDeckListRow` | `QuizFlash/Features/Library/Components/LibraryContentViews.swift` | `deck`, `isSelecting`, `isSelected`, `showActionMenu`, action closures | High-performance library list row with optional selection and long-press menu |
| `DetailedCardRowView` | `QuizFlash/Features/DeckEditor/Components/DetailedCardRowView.swift` | `card`, `index`, `fixedHeight`, `isSelecting`, `isSelected`, `onEdit`, `onTogglePin`, `onDelete` | Rich card preview row inside create/edit deck flows |
| `DeckHeaderView` | `QuizFlash/Features/DeckDetails/Components/DeckComponents.swift` | `deck`, `onEdit` | Compact deck identity header for sheets or supporting surfaces |
| `DeckProgressView` | `QuizFlash/Features/DeckDetails/Components/DeckProgressView.swift` | `progress`, `stats`, `deckCardCount` | Deck-detail progress breakdown and quick stats |
| `DeckHeroView` | `QuizFlash/Features/DeckDetails/Components/DeckHeroView.swift` | `deck`, `stats` | Collapsed floating title pill for `DeckView` |
| `FolderDeckListView` | `QuizFlash/Features/DeckDetails/Components/FolderDeckListView.swift` | `folder` | Folder-local deck list when navigating into a folder |
| `LibrarySectionHeader` | `QuizFlash/Features/Library/Components/LibraryContentViews.swift` | `title` | Section divider header in grouped library lists |

## Empty States, Loading & Feedback

| Componentă | Fișier | Parametri cheie | Când se folosește |
|---|---|---|---|
| `LibraryEmptyStateView` | `QuizFlash/Features/Library/Components/LibraryContentViews.swift` | none | Empty library root when there are no decks yet |
| `LibraryLoadingOverlay` | `QuizFlash/Features/Library/Components/LibraryContentViews.swift` | `message` | Modal loading layer for import/export/search work in Library |
| `AILoadingOverlay` | `QuizFlash/Features/DeckEditor/Components/AILoadingOverlay.swift` | `state`, `onDismiss` | Full-screen AI generation progress and error overlay |
| `ProgressActivityDots` | `QuizFlash/Core/DesignSystem/Components/ProgressActivityDots.swift` | `color` | Shared indeterminate loading dots used instead of circular spinners |
| `ImportProgressView` | `QuizFlash/Features/DeckDetails/Components/DeckSharingViews.swift` | `sharingManager` | Inline import progress UI while deck data is being restored |
| `StorageInfoView` | `QuizFlash/Features/DeckDetails/Components/DeckSharingViews.swift` | `decks` | Storage breakdown and cleanup screen |
| `HighlightedText` | `QuizFlash/Core/DesignSystem/Components/HighlightedText.swift` | `text`, `query`, `font`, `baseColor` | Search-result text with async token highlighting |
| `EdgeShadowOverlay` | `QuizFlash/Core/DesignSystem/Components/EdgeShadowOverlay.swift` | `topHeight`, `bottomHeight`, `kMaxAlphaTop`, `kMaxAlphaBottom` | Top/bottom vignette masking for floating headers and tab bars |
| `AppSectionSeparator` | `QuizFlash/Core/DesignSystem/Components/AppSectionSeparator.swift` | none | Minimal full-width separator between standalone app sections when a full card container would add visual weight |
| `TextSizeScalePicker` | `QuizFlash/Core/DesignSystem/Components/TextSizeScalePicker.swift` | `textSize`, `previewText`, `onChange` | Shared seven-step A-to-A text-size control with animated preview for global and deck settings |

## Editor & Rich Content

| Componentă | Fișier | Parametri cheie | Când se folosește |
|---|---|---|---|
| `MixedMathTextView` | `QuizFlash/Features/DeckEditor/Components/MixedMathTextView.swift` | `text`, `renderStyle`, layout callbacks | Rich text + math rendering for card previews and study surfaces |
| `CodeBlockPreviewView` | `QuizFlash/Core/DesignSystem/Components/CodeBlockPreviewView.swift` | `zoneText`, `showCopyButton` | Preview code zones without reimplementing syntax-oriented UI |
| `InlineCodeChip` | `QuizFlash/Core/DesignSystem/Components/CodeBlockPreviewView.swift` | `code` | Small inline code token chips |
| `CodeSnippetView` | `QuizFlash/Features/DeckEditor/Components/CodeSnippetView.swift` | snippet metadata + content | Larger code snippet display in card editing flows |
| `CanvasView` | `QuizFlash/Features/DeckEditor/Components/CanvasView.swift` | drawing bindings/configuration | Low-level drawing canvas representable |
| `CanvasModalView` | `QuizFlash/Features/DeckEditor/Components/CanvasModalView.swift` | draft drawing state, completion closures | Full-screen sketch editing modal |
| `ImageCropEditorView` | `QuizFlash/Features/DeckEditor/Components/ImageCropEditorView.swift` | image source, crop result closure | Image cropping before attaching media to cards |
| `EditorFormatMenuBar` | `QuizFlash/Features/DeckEditor/Components/EditorFormatMenuBar.swift` | `content`, `path`, edit callbacks | Persistent bottom formatting toolbar in the card editor |
| `PopoverBubble` | `QuizFlash/Features/DeckEditor/Components/EditorFormatMenuBar.swift` | `icon`, `isActive`, `accent` | Direction bubbles in radial editor menus |

## Sheets, Modals & Presentation

| Componentă | Fișier | Parametri cheie | Când se folosește |
|---|---|---|---|
| `ShareSheet` | `QuizFlash/Features/DeckDetails/Components/DeckSharingViews.swift` | `items` | Native iOS activity sheet wrapper |
| `LibraryModalsAndDialogs` | `QuizFlash/Features/Library/Components/LibraryViewModifiers.swift` | `viewModel`, `context`, `decks` | Reusable modifier bundle for Library sheets, importers, and confirmation dialogs |
| `LibraryAlerts` | `QuizFlash/Features/Library/Components/LibraryViewModifiers.swift` | `viewModel` | Shared alert modifier bundle for Library success/error alerts |
| `fullScreenSheet` | `QuizFlash/Core/DesignSystem/Modifiers/View+FullScreenSheet.swift` | `isPresented` or `item`, `configuration`, `content`, `background` | The only app-owned sheet presenter; all heights share the fixed symmetric `0.28 s` motion contract |
| `KeyboardAdaptiveSheetContent` | `QuizFlash/Core/DesignSystem/Components/KeyboardAdaptiveSheetContent.swift` | `isScrollable`, `content` | Standard scroll and keyboard-dismiss host for every custom sheet that contains text input |
| `StandardSheetTopStripBackground` | `QuizFlash/Features/DeckEditor/Views/CardPreviewModeView.swift` | none | Shared dark immersive sheet backdrop with the standardized top-only drag strip used by card preview and deck edit/create flows |
| `StandardCardContextMenu` | `QuizFlash/Core/DesignSystem/Components/StandardCardContextMenu.swift` | `title`, `summary`, `indicatorTint`, `isPinned`, action closures | The only custom menu surface used for card-level actions across deck detail and deck editor |

## Navigation, Chrome & Selection

| Componentă | Fișier | Parametri cheie | Când se folosește |
|---|---|---|---|
| `LibraryTopBarView` | `QuizFlash/Features/Library/Components/LibraryTopBarView.swift` | `title`, `deckCount`, `viewModel`, `isScrolled`, `onBack`, `backLabel` | Floating library chrome with native-feeling search state |
| `LibraryListView` | `QuizFlash/Features/Library/Components/LibraryContentViews.swift` | grouped deck data, selection state, action closures | Flat lazy list for the main Library screen |
| `LibrarySelectionBarView` | `QuizFlash/Features/Library/Components/LibrarySelectionBarView.swift` | `viewModel`, `decks`, `onDeleteTap`, `onMoveTap` | Floating bottom selection bar in Library |
| `DeckCustomNavigationBar` | `QuizFlash/Features/DeckDetails/Components/DeckCustomNavigationBar.swift` | `deck`, `stats`, `backLabel`, `searchQuery`, `isSelecting`, menu bindings, action closures | Unified safe-area-respectful top chrome for `DeckView` |
| `DeckActionOverlay` | `QuizFlash/Features/DeckDetails/Components/DeckComponents.swift` | `deck`, `isSelecting`, menu bindings, `menuTracker`, action closures | Floating add/menu button group in deck detail |
| `DeckSectionToolbar` | `QuizFlash/Features/DeckDetails/Components/DeckComponents.swift` | `deck`, `pillVisible` | Pinned section label above card lists in deck detail |
| `DeckSelectionBottomBar` | `QuizFlash/Features/DeckDetails/Components/DeckComponents.swift` | `selectedCount`, `onDone`, `onDelete` | Floating bottom toolbar during deck card selection |
| `DeckCardContextMenu` | `QuizFlash/Features/DeckDetails/Components/DeckComponents.swift` | `card`, `onEdit`, `onTogglePin`, `onDelete` | Anchored card actions menu for deck rows/previews |

### Floating Chrome Motion

- `BottomChromeContainer` in `QuizFlash/Core/DesignSystem/Components/BottomChromeContainer.swift` is the shared surface for `CustomTabBar`, `DeckSelectionBottomBar`, `CreateDeckSelectionBottomBar`, and `LibrarySelectionBarView`.
- Those controls belong to the same motion family.
- Their appearance/disappearance should reuse:
  - `.bottomChromeVisibility(...)` for persistent bars
  - `.transition(.bottomChrome)` for inserted bars
  - `.bottomChromeSpring` for visibility swaps
  - `.selectionToolbarSpring` for compact count/toggle changes inside the bar
- Selection-mode entry/exit should go through `withBottomChromeAnimation { ... }`.
- Do not introduce separate local spring constants for these surfaces unless the bar is intentionally behaving unlike the standard bottom chrome family.

## Reguli de utilizare

1. Reuse a DesignSystem or feature component when the new UI differs only by content, icon, tint, or callbacks.
2. Create a new component only when the layout contract changes meaningfully; do not fork an existing component just to rename labels or tweak one padding value.
3. Prefer wrappers like `LibraryModalsAndDialogs`, `LibraryAlerts`, and `fullScreenSheet` over re-stitching the same modifier stack in each screen.
4. Keep feature components dumb: if a new component needs `ModelContext`, `@Query`, or async tasks, first check whether that logic belongs in the parent view model.
5. When unsure, match the closest existing surface in this catalog before introducing a new visual language.
