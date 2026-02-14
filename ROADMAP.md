# QuizFlash – Roadmap & Code Flow

Documentație detaliată a arhitecturii, flow-ului aplicației și a responsabilităților fiecărui fișier/funcție.

---

## 1. Arhitectura proiectului

### Principii
- **UI (Views)**: fișiere care conțin doar SwiftUI views, fără logică de business.
- **Logic**: managers, grouping, export/import, focus – în fișiere separate.
- **Modele**: `DeckModel`, `CardModel`, `ZoneModel`, etc. – date și comportament minimal.

### Structura dosarelor

```
QuizFlash/
├── App/
│   └── QuizFlashApp.swift          # Punct de intrare, WindowGroup, SwiftData container
├── Core/
│   ├── Authentification/
│   │   └── AuthManager.swift       # Autentificare (isAuthenticated)
│   ├── Navigation/
│   │   ├── NavigationManager.swift # Stack de navigare (path), AppRoute
│   │   └── AppTab.swift            # Tab-uri app (enum)
│   ├── Theme/
│   │   └── ThemeManager.swift      # Culoare accent, tema
│   ├── Components/                  # Componente reutilizabile (doar UI)
│   │   ├── GlassModifier.swift
│   │   ├── MorphingButton.swift
│   │   └── FloatingTabBar.swift
│   └── Storage/
│       ├── DeckSharingManager.swift # Export/Import .qflash, ZIP, StorageManager, GarbageCollector
│       └── DeckSharingViews.swift   # ShareSheet, ExportDeckButton, ImportProgressView, StorageInfoView
├── Features/
│   ├── Main/
│   │   ├── RootView.swift          # Branch: autentificat → MainAppView / LoginView
│   │   └── MainAppView.swift       # NavigationStack + destinatii (Library, Deck, Create, Settings)
│   ├── Auth/
│   │   └── LoginView.swift         # Ecran login
│   ├── Library/
│   │   ├── LibraryView.swift      # Lista/grid deck-uri, import/export, selecție
│   │   ├── LibraryGrouping.swift   # Logică: DeckSection, sections(), sectionTitle()
│   │   ├── DeckColorPickerSheet.swift # UI: alegere culoare deck
│   │   ├── Deck/
│   │   │   ├── DeckView.swift
│   │   │   ├── DeckComponents.swift
│   │   │   ├── DeckRowView.swift
│   │   │   ├── DeckGalleryView.swift
│   │   │   └── DeckCardGridView.swift
│   │   ├── DeckPlay/
│   │   │   ├── DefaultModePlay.swift
│   │   │   ├── GameplayCard.swift
│   │   │   ├── SwipeableCard.swift
│   │   │   └── FlipCardPreview.swift
│   │   └── Extension.swift         # SortOrder, ViewMode, ScaleButtonStyle, Color
│   ├── Create/
│   │   ├── CreateView.swift        # Creare/editare deck, listă carduri draft
│   │   ├── AddCardSheetView.swift  # Editor card cu zone (front/back), FAB, format bar
│   │   ├── AddCardSheet/           # Subview-uri doar UI
│   │   │   ├── ZoneFormatBarView.swift   # ZoneFormatBar, ToolbarButton
│   │   │   ├── ZonePreviewSheetView.swift # ZonePreviewSheet (preview flip)
│   │   │   └── FABMenuItemView.swift    # FABMenuItem
│   │   ├── Helpers/
│   │   │   ├── ZoneModel.swift     # ZoneModel, ZonePath, ZoneCardContent, Data/ImageCache
│   │   │   ├── ZoneView.swift      # ZoneEditorView, ZoneContentView, ZonePreviewView, CachedImageView
│   │   │   └── ZoneFocusManager.swift    # Focus + keyboard retention
│   │   ├── Canvas/
│   │   │   ├── CanvasView.swift
│   │   │   └── CanvasModalView.swift
│   │   ├── ContentBlock.swift      # Enums text/image, ContentBlock, CardSideContent (legacy)
│   │   ├── CardModel.swift
│   │   ├── CardRowView.swift
│   │   └── DeckModel.swift
│   └── Settings/
│       └── SettingsView.swift
```

---

## 2. Flow-ul aplicației (la runtime)

### Pornire
1. **QuizFlashApp** (`App/QuizFlashApp.swift`)
   - Creează `AuthManager` și `ThemeManager`.
   - Setează `WindowGroup` cu `RootView`, `modelContainer(for: [DeckModel.self, CardModel.self])`, tint și preferredColorScheme.

2. **RootView** (`Features/Main/RootView.swift`)
   - Citește `authManager.isAuthenticated`.
   - Dacă `true` → afișează **MainAppView**.
   - Dacă `false` → afișează **LoginView**.

3. **MainAppView** (`Features/Main/MainAppView.swift`)
   - Creează `NavigationManager()` (path).
   - `NavigationStack(path: $router.path)` cu rădăcina **LibraryView**.
   - Destinații:
     - `DeckModel` → **DeckView(deck:)**.
     - `AppRoute.createDeck` → **CreateView()**.
     - `AppRoute.settings` → **SettingsView()**.

### Din Library
- Utilizatorul vede **LibraryView** (lista sau grid de deck-uri, grupate pe secțiuni de dată via **LibraryGrouping**).
- Tap pe un deck → `router.path.append(deck)` → se deschide **DeckView**.
- Tap pe „+” → `router.path.append(AppRoute.createDeck)` → **CreateView**.
- Tap pe Settings → `router.path.append(AppRoute.settings)` → **SettingsView**.
- Import: fileImporter → `handleFileImport` → `DeckSharingManager.shared.importDeck(from:into:)`.
- Export (din modul selecție): `exportSelectedDecks()` → `DeckSharingManager.shared.exportDeck(deck)` → ShareSheet cu URL-uri.

### Din DeckView
- Header (DeckHeaderView), moduri de play (DeckPlayModesView), toolbar (DeckSectionToolbar), grid de carduri (DeckCardGridView).
- „Play” → `isPlayingQuiz = true` → fullScreenCover cu **DefaultModePlay**.
- „Add card” → sheet cu **CreateView** (cu deck bindat) sau flow add card → **AddCardSheetView**.
- Export deck → `exportDeck()` → DeckSharingManager → ShareSheet.

### Creare deck / card
- **CreateView**: titlu deck + listă de **DraftCard**. „Add card” / tap pe card → sheet **AddCardSheetView** cu `onSaveZones` care fie adaugă, fie actualizează un draft card.
- **AddCardSheetView**: conține `frontZoneContent` / `backZoneContent` (ZoneCardContent), `selectedPath`, FAB (photo/sketch), **ZoneEditorView** pentru zone, **ZoneFormatBar** când e selectată o zone. Salvare → `onSaveZones(frontZoneContent.rootZone, backZoneContent.rootZone)` și dismiss.

### Play
- **DefaultModePlay**: afișează **GameplayCard** pentru `cards[currentIndex]`, swipe (SwipeableCard) → `handleSwipe` (next/previous sau „wrong” queue). Retry wrong → reîntoarce cardurile greșite în listă.

---

## 3. Fișier cu fișier – ce face fiecare

### App

| Fișier | Rol | Tipuri / funcții importante |
|--------|-----|-----------------------------|
| **QuizFlashApp.swift** | Entry point. | `QuizFlashApp: App` – `body`: WindowGroup cu RootView, modelContainer, environmentObject(authManager), tint(themeManager). |

---

### Core

| Fișier | Rol | Tipuri / funcții importante |
|--------|-----|-----------------------------|
| **AuthManager.swift** | Stare autentificare. | `AuthManager: ObservableObject` – `isAuthenticated`, metode login/logout. |
| **NavigationManager.swift** | Stiva de navigare. | `NavigationManager` – `path: NavigationPath`, `popToRoot()`. `AppRoute`: createDeck, settings. |
| **AppTab.swift** | Tab-uri (dacă se folosesc). | `AppTab` enum. |
| **ThemeManager.swift** | Tema și accent. | `ThemeManager` – `accentColor`, `AccentColorOption`. |
| **GlassModifier.swift** | Efecte UI. | `GlassModifier`, `TrueGlowModifier`, `View.glassEffect`, `View.glowEffect`. |
| **DeckSharingManager.swift** | Export/import .qflash, storage, cleanup. | **Modele**: ExportableCard, ExportableDeck, AssetReference, DeckSharingError. **DeckSharingManager**: `exportDeck`, `importDeck`, `isValidQFlashFile`; ZIP: `createZipArchive`, `extractZipArchive`, `unzipFile`, `findEndOfCentralDirectory`, `readUInt16/32`, `decompressDeflate`, `extractAndReplaceAssets`. **StorageManager**: `calculateStorage`, `calculateDeckStorage`, `formatBytes`. **GarbageCollector**: `cleanupDeckData`, `runFullCleanup`, `deleteDeck`. **UTType.qflash**. |
| **DeckSharingViews.swift** | Doar UI pentru share/export/import/storage. | **ShareSheet**: UIActivityViewController wrapper. **ExportDeckButton**: buton export → DeckSharingManager.exportDeck → ShareSheet. **ImportProgressView**: ProgressView + text. **StorageInfoView**: List storage total, by deck, cleanup. |

---

### Features – Main

| Fișier | Rol | Tipuri / funcții importante |
|--------|-----|-----------------------------|
| **RootView.swift** | Branch login vs app. | `RootView` – `body`: dacă `authManager.isAuthenticated` → MainAppView, altfel LoginView. |
| **MainAppView.swift** | Container principal + navigare. | `MainAppView` – NavigationStack, LibraryView, navigationDestination(DeckModel → DeckView), navigationDestination(AppRoute → CreateView / SettingsView). |

---

### Features – Auth

| Fișier | Rol | Tipuri / funcții importante |
|--------|-----|-----------------------------|
| **LoginView.swift** | Ecran login. | `LoginView` – UI login, apeluri AuthManager. |

---

### Features – Library

| Fișier | Rol | Tipuri / funcții importante |
|--------|-----|-----------------------------|
| **LibraryView.swift** | Lista/grid deck-uri, toolbar, import/export, selecție. | **LibraryView** – `body`, `groupedDecks` (delegat la LibraryGrouping), `content` (list vs gallery), `groupedDecksList`, `galleryGrid`, `deckRow`, `deckGalleryCell`, `selectionIndicator`, `selectionBottomBar`, `bottomFloatingButtons`, `deckCountSection`, `dateSectionHeader`, `emptyStateView`. Acțiuni: `toggleSelection`, `exitSelectionMode`, `deleteSelectedDecks`, `handleFileImport`, `exportSelectedDecks`. Toolbar: `topToolbar`. |
| **LibraryGrouping.swift** | Logică grouping (fără UI). | `DeckSection` (id, title, decks, dateForSorting). `LibraryGrouping.sections(decks:sortOrder:)` – sortează, grupează pe dată sau returnează o secțiune „All Decks”. `LibraryGrouping.sectionTitle(for:calendar:)` – „Today”, „Yesterday”, „This Week - …”, „MMMM d”, „MMMM yyyy”. |
| **DeckColorPickerSheet.swift** | Sheet alegere culoare deck. | `DeckColorPickerSheet` – grid culori, bind la `deck.colorHex`, Done. |
| **Extension.swift** | Utilitare Library. | `SortOrder`, `ViewMode`, `ScaleButtonStyle`, extensii Color. |

---

### Features – Library / Deck

| Fișier | Rol | Tipuri / funcții importante |
|--------|-----|-----------------------------|
| **DeckView.swift** | Ecran unui deck: header, play, toolbar, grid carduri. | **DeckView** – `body`, `groupedCards`, `handleCardTap` (navigate edit sau play), `toggleSelection`, `exitSelectionMode`, `requestSingleDelete`, `deleteSingleCard`, `deleteSelectedCards`, `exportDeck`, `getSectionTitle`. State: isAddingCard, isPresentingEdit, isPlayingQuiz, isSelecting, selectedCards, export state. |
| **DeckComponents.swift** | Componente UI deck. | `DeckHeaderView`, `DeckPlayModesView`, `DeckSectionToolbar`, `DeckSelectionBottomBar`. |
| **DeckRowView.swift** | Un rând deck în listă. | Afișează icon, titlu, meta. |
| **DeckGalleryView.swift** | Celulă deck în grid. | Variantă pentru view mode gallery. |
| **DeckCardGridView.swift** | Grid de carduri din deck. | Carduri cu preview zone, selecție, tap/long-press. |

---

### Features – Library / DeckPlay

| Fișier | Rol | Tipuri / funcții importante |
|--------|-----|-----------------------------|
| **DefaultModePlay.swift** | Ecran play: card curent, swipe. | **DefaultModePlay** – `body`, `portraitLayout`, `landscapeLayout`, `cardArea` (GameplayCard + SwipeableCard + tranziții), `handleSwipe` (next/previous/wrong), `retryWrongCards`. **header**: titlu deck, dismiss. |
| **GameplayCard.swift** | Un card în play (front/back flip). | Afișează ZonePreviewView / AdaptiveZonePreview, tap pentru flip. |
| **SwipeableCard.swift** | Wrapper swipe stânga/dreapta. | `SwipeDirection`, `SwipeableCard` – gesture, `resetPosition`, `exitCard`, callback `onSwipe`. |
| **FlipCardPreview.swift** | Preview flip card (alt context). | Card cu zone preview, flip 3D. |

---

### Features – Create

| Fișier | Rol | Tipuri / funcții importante |
|--------|-----|-----------------------------|
| **CreateView.swift** | Creare/editare deck: titlu + listă carduri. | **CreateView** – `body`, `deckInfoSection`, `cardsListSection`, `loadExistingData` (dacă deckToEdit), `addCard`, `updateCard`, `deleteCard`, `saveDeck` (insert/update DeckModel + cards), `resetForm`. Sheet: AddCardSheetView pentru add/edit card. |
| **AddCardSheetView.swift** | Editor card pe zone (front/back). | **AddCardSheetView** – `body` (sidePicker, editorArea, ZoneFormatBar, FAB, toolbar). State: frontZoneContent, backZoneContent, activeSide, selectedPath, showFABMenu, keyboard, modals. Acțiuni: `addZoneWithFocus`, `addZoneAtBottom`, `triggerKeyboardForNewZone`, `addPhoto`, `addSketch`, `splitZone`, `updateSplitZoneContent`, `executeWithKeyboardRetention`, `hideKeyboard`. Subviews: sidePicker, editorArea, fabOverlay, fabDismissOverlay, toolbarContent, styling. |
| **AddCardSheet/ZoneFormatBarView.swift** | Bară format zone (add/split/delete, text/media). | **ZoneFormatBar** – addZoneMenu, textTools (style, bold, italic, font, alignment, color, highlight, bullet), mediaTools (alignment, scale), ToolbarButton. |
| **AddCardSheet/ZonePreviewSheetView.swift** | Sheet preview card flip. | **ZonePreviewSheet** – flip question/answer, cardFace(zone), emptyContent, styling. |
| **AddCardSheet/FABMenuItemView.swift** | Un item din FAB (Photo/Sketch). | **FABMenuItem** – icon + label + action. |
| **Helpers/ZoneModel.swift** | Model zone și conținut. | **ZoneModel**: empty(), text(), image(), sketch(), container(); encode/decode; ZonePath (appending, parent, lastIndex). **ZoneCardContent**: zone(at), updateZone, addZone, deleteZone, cleanup, hasContent; from(oldContent), toOldContent(). **Data**: compressedImageData, thumbnailData. **ImageCache**: image(for), clearCache. Enums: CardOrientation, ZoneDirection, ZoneContentType, AddDirection. |
| **Helpers/ZoneView.swift** | View-uri pentru zone (editor + preview). | **ZoneEditorView** – leafZoneView (ZoneContentView), containerZoneView (HStack/VStack), selectZone. **ZoneContentView** – textView, imageView, sketchView, textBinding, checkPendingFocus, alignmentFor. **ZonePreviewView** – leafPreview (text/image/sketch), containerPreview, previewFont, alignmentFor. **AdaptiveZonePreview** – needsAdaptation, adaptedView (scroll orizontal/vertical). **CachedImageView** – loadImage, imageContent. |
| **Helpers/ZoneFocusManager.swift** | Focus și tastatură la inserare zone. | **Notification.Name**: focusNewZone, scrollToCursor. **ZoneFocusManager**: requestFocus(for:), clearPendingFocus(), prepareForInsertion(); pendingFocusZoneID, shouldRetainKeyboard. |
| **Canvas/CanvasView.swift** | Bridge PencilKit. | **CanvasView** – makeUIView (drawingPolicy, toolPicker, initialData), updateUIView. |
| **Canvas/CanvasModalView.swift** | Modal desen. | **CanvasModalView** – canvas + Save/Cancel; saveSketch() → callback cu Data. **CanvasViewRepresentable** – PKCanvasView. |
| **ContentBlock.swift** | Blocuri conținut (legacy + compat). | Enums: ContentBlockType, TextBlockAlignment, TextBlockStyle, FontFamily, HighlightColor, TextBlockColor. **ContentBlock**. **CardSideContent**: addTextBlock, addImageBlock, addSketchBlock, deleteBlock, moveBlock, updateText/Height/Alignment/Style, toggleBold/Italic, toData, fromData, fromLegacy. |
| **CardModel.swift** | Model card (front/back zone). | **CardModel** – frontZone, backZone, frontData/backData (legacy), frontImages/backImages. **DraftCard**. **CardModel.from** pentru DraftCard. |
| **CardRowView.swift** | Rând card în listă Create. | Preview zone + tap. |
| **DeckModel.swift** | Model deck. | **DeckModel** – title, icon, colorHex, cards, createdAt, editedAt. |

---

### Features – Settings

| Fișier | Rol | Tipuri / funcții importante |
|--------|-----|-----------------------------|
| **SettingsView.swift** | Setări app. | List cu opțiuni; **AccentColorPickerView** pentru culoare accent. Poate include link către StorageInfoView. |

---

## 4. Fluxuri critice pe scurt

- **Launch**: QuizFlashApp → RootView → (Auth) → MainAppView → LibraryView.
- **Navigare**: LibraryView ↔ DeckView (path.append(deck)); LibraryView ↔ CreateView / SettingsView (path.append(route)).
- **Import**: LibraryView fileImporter → handleFileImport → DeckSharingManager.importDeck → context insert.
- **Export**: LibraryView exportSelectedDecks sau DeckView exportDeck → DeckSharingManager.exportDeck → ShareSheet.
- **Add/Edit card**: CreateView deschide AddCardSheetView → onSaveZones → addCard/updateCard (DraftCard) → la Save deck: CardModel din draft + context.insert(deck) sau update.
- **Focus la zone**: ZoneFocusManager.requestFocus/clearPendingFocus/prepareForInsertion; ZoneContentView checkPendingFocus, onReceive(focusNewZone); AddCardSheetView executeWithKeyboardRetention pentru add/split.

Acest document poate fi actualizat la fiecare refactor major (fișiere noi sau mutare de responsabilități).
