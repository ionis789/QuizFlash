# Anti-patterns QuizFlash

Use this file when the surrounding code still shows older patterns. The examples below were found in the current repo; prefer the "Fă" version for new code.

## ❌ Spacing cu numere magice

Găsit în:
- `QuizFlash/Features/DeckDetails/Components/DeckComponents.swift`
- `QuizFlash/Core/DesignSystem/Components/CodeBlockPreviewView.swift`

**Nu face:**
```swift
.padding(.top, 16)
.padding(14)
```

**Fă:**
```swift
.padding(.top, UIConstants.Spacing.standard)
.padding(UIConstants.Spacing.medium)
```

**De ce:** menține ritmul vizual consistent și permite ajustări globale prin `UIConstants`.

## ❌ Dimensiuni hard-coded pentru controale

Găsit în:
- `QuizFlash/Features/DeckDetails/Components/DeckComponents.swift`
- `QuizFlash/Features/Home/Components/HomeRecentDeckCardView.swift`

**Nu face:**
```swift
.frame(width: 56, height: 56)
.frame(width: 260)
```

**Fă:**
```swift
.frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
.frame(maxWidth: .infinity)
```

**De ce:** dimensiunile de control și de card trebuie să provină din tokens sau din layout-ul părintelui, nu din numere izolate.

## ❌ `DispatchQueue.main.async` pentru update-uri UI noi

Găsit în:
- `QuizFlash/Features/DeckEditor/Views/FlashcardEditorView.swift`
- `QuizFlash/Core/Helpers/ScrollPositionRestorer.swift`
- `QuizFlash/Features/Library/Components/LibraryContentViews.swift`

**Nu face:**
```swift
DispatchQueue.main.async {
    self.isLoading = false
}
```

**Fă:**
```swift
await MainActor.run {
    isLoading = false
}
```

**De ce:** noul cod trebuie să respecte actor isolation-ul Swift 6 și să evite hop-uri UIKit-style pe main queue.

## ❌ `DispatchQueue.main.asyncAfter` pentru secvențe de UI

Găsit în:
- `QuizFlash/Features/Library/Components/LibraryContentViews.swift`
- `QuizFlash/Features/DeckDetails/Components/DeckHeroView.swift`

**Nu face:**
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    onDelete()
}
```

**Fă:**
```swift
Task { @MainActor in
    try? await Task.sleep(for: .milliseconds(150))
    onDelete()
}
```

**De ce:** secvențierea nouă ar trebui să fie anulabilă și aliniată cu modelul de concurență folosit de view model-uri.

## ❌ `print(...)` în loc de logging structurat

Găsit în:
- `QuizFlash/Services/AI/AIGenerationSessionStore.swift`
- `QuizFlash/Services/Storage/DeckSharingManager.swift`
- `QuizFlash/Features/Home/ViewModels/HomeViewModel.swift`

**Nu face:**
```swift
print("Save failed: \(error)")
```

**Fă:**
```swift
logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
```

**De ce:** `Logger` oferă categorii, privacy control și output mai util pentru debugging și release builds.

## ❌ `DateFormatter()` alocat inline la fiecare render

Găsit în:
- `QuizFlash/Features/DeckDetails/ViewModels/DeckViewModel.swift`
- `QuizFlash/Features/DeckDetails/Views/DeckView.swift`
- `QuizFlash/Features/Home/ViewModels/CalendarViewModel.swift`

**Nu face:**
```swift
let formatter = DateFormatter()
formatter.dateStyle = .medium
return formatter.string(from: date)
```

**Fă:**
```swift
private static let createdAtFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter
}()
```

**De ce:** formatters sunt costisitori; în QuizFlash este preferată reutilizarea statică.

## ❌ `sheet(isPresented:)` pentru flow-uri imersive QuizFlash

Găsit în:
- `QuizFlash/Features/Home/Views/HomeView.swift`
- `QuizFlash/Features/DeckDetails/Views/DeckView.swift`
- `QuizFlash/Features/Library/Components/LibraryViewModifiers.swift`

**Nu face:**
```swift
.sheet(isPresented: $showEditor) {
    FlashcardEditorView(...)
}
```

**Fă:**
```swift
.fullScreenSheet(item: $activeSheet) { destination, _ in
    FlashcardEditorView(...)
} background: {
    Color.black.opacity(0.35)
}
```

**De ce:** pentru flow-urile care trebuie să respecte drag-dismiss-ul și backdrop-ul aplicației, `fullScreenSheet` este containerul standard.

## ❌ `.count` pe relații SwiftData în loc de counters denormalizate

Găsit în:
- `QuizFlash/Services/Storage/DeckSharingManager.swift`
- `QuizFlash/Features/DeckDetails/Views/DeckView.swift`

**Nu face:**
```swift
newDeck.cardCount = newDeck.cards.count
let reviewCount = card.reviewHistory.count
```

**Fă:**
```swift
newDeck.cardCount = importedCardCount
let reviewCount = card.reviewCount
```

**De ce:** relațiile SwiftData pot fault-ui și crește retenția de memorie; QuizFlash preferă counters stocați explicit.

## ❌ `@Observable` view model fără `@MainActor`

Găsit în:
- `QuizFlash/Features/Home/ViewModels/HomeViewModel.swift`
- `QuizFlash/Core/Navigation/NavigationManager.swift`

**Nu face:**
```swift
@Observable
final class HomeViewModel { ... }
```

**Fă:**
```swift
@Observable
@MainActor
final class MyFeatureViewModel { ... }
```

**De ce:** în codul nou, view model-urile `@Observable` trebuie ancorate pe `MainActor` pentru mutații UI sigure și previzibile.

## ❌ `try? context.save()` sau erori de save înghițite

Găsit în:
- `QuizFlash/Features/Library/Components/LibraryViewModifiers.swift`
- `QuizFlash/Features/DeckEditor/ViewModels/DeckWorkspaceViewModel.swift`

**Nu face:**
```swift
try? context.save()
```

**Fă:**
```swift
do {
    try context.save()
} catch {
    logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
    showError = true
    errorMessage = "Your changes couldn't be saved."
}
```

**De ce:** skill-ul cere save explicit și failure handling clar; datele nu trebuie pierdute tăcut.

## ❌ `#Predicate` pe relații opționale în hot paths

Găsit în:
- `QuizFlash/Features/DeckDetails/Components/FolderDeckListView.swift`

**Nu face:**
```swift
let filter = #Predicate<DeckModel> { $0.folder?.persistentModelID == folderID }
```

**Fă:**
```swift
let folder = context.safeModel(for: folderID, as: FolderModel.self)
let decks = folder?.decks ?? []
```

**De ce:** pe iOS 17, predicatele care traversează relații opționale sunt fragile pe hot paths; skill-ul recomandă rezolvarea părintelui în același context.

## ❌ Theme singleton accesat direct în UI nou

Găsit în:
- `QuizFlash/Features/Home/Components/FolderCardView.swift`
- `QuizFlash/Features/DeckDetails/Components/DeckComponents.swift`

**Nu face:**
```swift
private var accent: Color { ThemeManager.shared.accentColor.color }
```

**Fă:**
```swift
@Environment(ThemeManager.self) private var theme

private var accent: Color { theme.accentColor.color }
```

**De ce:** pattern-ul recomandat pentru cod nou este environment-based theming, chiar dacă multe fișiere vechi încă citesc singleton-ul direct.
