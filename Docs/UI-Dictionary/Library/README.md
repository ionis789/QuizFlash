# Library UI Dictionary

Acest document este roadmap-ul pentru ecranul `Library`.

Scopul lui: când vrei o schimbare, să-mi poți spune direct numele din cod al componentei, nu doar descrierea vizuală.r

## Root Screen

| Ce este în UI | Nume exact în cod | Tip | Fișier |
| --- | --- | --- | --- |
| Ecranul principal `Library` | `LibraryView` | `View` root | `QuizFlash/Features/Library/Views/LibraryView.swift` |
| Layout-ul principal al ecranului | `LibraryLayout` | `View` layout engine | `QuizFlash/Features/Library/Components/LibraryLayout.swift` |
| Zona principală scrollabilă | `mainScrollArea` | computed view | `QuizFlash/Features/Library/Components/LibraryLayout+MainScrollArea.swift` |
| Stack-ul mare care decide browse vs search results | `stackContent` | computed view | `QuizFlash/Features/Library/Components/LibraryLayout+MainScrollArea.swift` |
| Hero area cu titlul mare `Library` | `libraryHeroTitle` | computed view | `QuizFlash/Features/Library/Components/LibraryLayout+MainScrollArea.swift` |
| Lista principală în stare normală | `browseListContent` | computed view | `QuizFlash/Features/Library/Components/LibraryLayout+MainScrollArea.swift` |
| Conținutul când sunt rezultate de search | `SearchResultsView` | `View` | `QuizFlash/Features/Library/Views/SearchResultsView.swift` |

## Top Bar

| Ce vezi | Nume exact în cod | Tip | Fișier |
| --- | --- | --- | --- |
| Bara flotantă de sus | `LibraryTopBarView` | `View` | `QuizFlash/Features/Library/Components/LibraryTopBarView.swift` |
| Varianta normală a top bar-ului | `idleChromeRow` | computed view | `QuizFlash/Features/Library/Components/LibraryTopBarView+Chrome.swift` |
| Butonul rotund din stânga cu search | `LibraryTopBarSearchIconButton` | `View` | `QuizFlash/Features/Library/Components/LibraryTopBarControls.swift` |
| Iconița lupă | `LibraryTopBarSearchGlyph` | `View` | `QuizFlash/Features/Library/Components/LibraryTopBarControls.swift` |
| Butonul rotund din dreapta cu `...` | `LibraryTopBarMoreSettingsButton` | `View` | `QuizFlash/Features/Library/Components/LibraryTopBarControls.swift` |
| Conținutul meniului din `...` | `LibraryTopBarMenuContent` | `View` | `QuizFlash/Features/Library/Components/LibraryTopBarMenuContent.swift` |
| Titlul mic colapsat din centru, când dai scroll | `CollapsibleTitlePill` | shared `View` | `QuizFlash/Core/DesignSystem/Components/CollapsibleTitleChrome.swift` |
| Bara shared care ține leading / center / trailing chrome | `CollapsibleTitleNavigationBar` | shared `View` | `QuizFlash/Core/DesignSystem/Components/CollapsibleTitleChrome.swift` |

## Search State

| Ce vezi | Nume exact în cod | Tip | Fișier |
| --- | --- | --- | --- |
| Toată bara de search activă | `searchBar` | computed view | `QuizFlash/Features/Library/Components/LibraryTopBarView+Search.swift` |
| Capsula mare de search | `searchField` | computed view | `QuizFlash/Features/Library/Components/LibraryTopBarView+Search.swift` |
| Background-ul capsulei de search | `LibraryTopBarSearchFieldBackground` | `View` | `QuizFlash/Features/Library/Components/LibraryTopBarControls.swift` |
| Text field-ul / placeholder-ul din search | `searchFieldContent` | computed view | `QuizFlash/Features/Library/Components/LibraryTopBarView+Search.swift` |
| Butonul `Cancel` | `cancelButton` | computed view | `QuizFlash/Features/Library/Components/LibraryTopBarView+Search.swift` |
| Accesoriul din dreapta din search | `LibraryTopBarTrailingAccessory` | `View` | `QuizFlash/Features/Library/Components/LibraryTopBarControls.swift` |
| Iconița voice/waveform din dreapta, când textul e gol | `LibraryVoiceCommandGlyph` | `View` | `QuizFlash/Features/Library/Components/LibraryTopBarControls.swift` |
| Butonul mic `x` pentru clear text | parte din `LibraryTopBarTrailingAccessory` | `Button` intern | `QuizFlash/Features/Library/Components/LibraryTopBarControls.swift` |

Notă importantă:

- Când search-ul e activ, dar încă nu ai intrat în starea cu rezultate dedicate, ecranul poate rămâne pe lista normală. Asta este controlat de `viewModel.searchPresentation`.
- Stările principale sunt `.browse`, `.searchEmpty` și `.searchResults`.

## Hero Area

| Ce vezi | Nume exact în cod | Tip | Fișier |
| --- | --- | --- | --- |
| Titlul mare `Library` din conținut | `LargeScreenTitle` folosit în `libraryHeroTitle` | shared `View` + local composition | `QuizFlash/Core/DesignSystem/Components/CollapsibleTitleChrome.swift` și `QuizFlash/Features/Library/Components/LibraryLayout+MainScrollArea.swift` |
| Textul mic `15 Decks` | `Text` din `libraryHeroTitle` | view intern, fără componentă separată | `QuizFlash/Features/Library/Components/LibraryLayout+MainScrollArea.swift` |

## Deck List

| Ce vezi | Nume exact în cod | Tip | Fișier |
| --- | --- | --- | --- |
| Lista grupată pe date | `LibraryListView` | `View` | `QuizFlash/Features/Library/Components/LibraryDeckListViews.swift` |
| Header-ul de secțiune, de ex. `Thursday`, `March 20` | `LibrarySectionHeader` | `View` | `QuizFlash/Features/Library/Components/LibrarySectionHeaders.swift` |
| Textul efectiv din header-ul de secțiune | `LibrarySectionHeaderLabel` | `View` | `QuizFlash/Features/Library/Components/LibrarySectionHeaders.swift` |
| Un row de deck | `LibraryDeckListRow` | `View` | `QuizFlash/Features/Library/Components/LibraryDeckListRow.swift` |
| Titlul deck-ului, de ex. `test` | `LibraryDeckTitleLabel` | `View` privat | `QuizFlash/Features/Library/Components/LibraryDeckListRow.swift` |
| Meta info row, de ex. `2 cards`, `1 day ago`, nume folder | `LibraryDeckMetaLabel` | `View` | `QuizFlash/Features/Library/Components/LibraryDeckListRow.swift` |
| Separatorul luminos de sub row | `LibraryRowSeparator` | `View` | `QuizFlash/Features/Library/Components/LibraryDeckListRow.swift` |
| Cerculețul de selecție din dreapta în selection mode | `LibraryRowAccessory` | `View` privat | `QuizFlash/Features/Library/Components/LibraryDeckListRow.swift` |
| Meniul flotant după long press pe row | `DeckActionMenu` | `View` privat | `QuizFlash/Features/Library/Components/LibraryDeckListRow.swift` |

## Search Results List

Folosește aceste nume doar când `Library` intră în starea de rezultate dedicate, nu pentru lista normală de deck-uri.

| Ce vezi | Nume exact în cod | Tip | Fișier |
| --- | --- | --- | --- |
| Un rezultat deck în search | `SearchDeckResultRow` | `View` privat | `QuizFlash/Features/Library/Views/SearchResultsView.swift` |
| Un snippet de card din interiorul unui rezultat | `SearchSnippetRow` | `View` privat | `QuizFlash/Features/Library/Views/SearchResultsView.swift` |
| Empty state pentru search | `emptyState` din `SearchResultsView` | computed view | `QuizFlash/Features/Library/Views/SearchResultsView.swift` |

## Bottom / Overlay States

| Ce vezi | Nume exact în cod | Tip | Fișier |
| --- | --- | --- | --- |
| Empty state când nu există deck-uri | `LibraryEmptyStateView` | `View` | `QuizFlash/Features/Library/Components/LibrarySupportViews.swift` |
| Bara de jos din selection mode | `LibrarySelectionBarView` | `View` | `QuizFlash/Features/Library/Components/LibrarySelectionBarView.swift` |
| Butonul capsule `Done` din bara de selecție | `SelectionToolbarCapsuleButton` | shared `View` | `QuizFlash/Core/DesignSystem/Components/SelectionToolbarControls.swift` |
| Butoanele icon-only din bara de selecție | `SelectionToolbarIconButton` | shared `View` | `QuizFlash/Core/DesignSystem/Components/SelectionToolbarControls.swift` |
| Overlay-ul de loading pentru import/export | `LibraryLoadingOverlay` | `View` | `QuizFlash/Features/Library/Components/LibrarySupportViews.swift` |
| Toate sheet-urile, importer-ul și confirmation dialog-urile | `LibraryModalsAndDialogs` | `ViewModifier` | `QuizFlash/Features/Library/Components/LibraryViewModifiers.swift` |
| Toate alertele de eroare/succes | `LibraryAlerts` | `ViewModifier` | `QuizFlash/Features/Library/Components/LibraryViewModifiers.swift` |

## Tab Bar Vizibilă În Screenshot

În screenshot-ul normal de `Library`, bara de jos nu aparține feature-ului `Library`, ci layer-ului global de navigație al aplicației.

| Ce vezi | Nume exact în cod | Tip | Fișier |
| --- | --- | --- | --- |
| Bara flotantă de tab-uri | `CustomTabBar` | `View` | `QuizFlash/Core/Navigation/TabBar/CustomTabBar.swift` |
| Controlul capsulei animate din tab bar | `CapsuleSelectionControl` | shared `View` | `QuizFlash/Core/Navigation/TabBar/CapsuleSelectionControl.swift` |
| Tab-ul `Library` ca model de tab | `AppTabBar.library` | enum case | `QuizFlash/Core/Navigation/TabBar/AppTabBar.swift` |

Notă:

- `LibraryView` ascunde tab bar-ul când `isSearching == true` sau `isSelecting == true`.
- Logica asta este în `tabRule` din `QuizFlash/Features/Library/Views/LibraryView.swift`.

## Cum Să-Mi Ceri Schimbări

Exemple bune de formulare:

- „Modifică `LibraryTopBarSearchIconButton`.”
- „Schimbă spacing-ul din `LibrarySectionHeader`.”
- „Mărește fontul din `LibraryDeckTitleLabel`.”
- „Vreau alt stil pentru `LibraryRowSeparator`.”
- „Mută `cancelButton` mai aproape de `searchField`.”
- „Ascunde `LibraryTopBarMoreSettingsButton` în starea X.”
- „Schimbă `LibrarySelectionBarView`.”

## Observații Practice

- Unele elemente vizuale importante nu au componentă dedicată și apar ca `computed view` sau chiar `Text` direct în parent. În cazurile astea, folosește exact numele simbolului părinte din tabel.
- Pentru `Library`, punctele cele mai utile pentru modificări rapide sunt de obicei: `LibraryTopBarView`, `LibraryDeckListRow`, `LibrarySectionHeader`, `LibrarySelectionBarView`, `SearchResultsView`, `CustomTabBar`.
- Documentul ăsta e gândit să fie extins ulterior și pentru celelalte ecrane: `Home`, `Create`, `Settings`, `DeckView`.
