# New Feature Template

Use this as the default order of operations when adding a new end-to-end feature to QuizFlash.

## Structura de foldere

```text
Features/
  MyFeature/
    ViewModels/
      MyFeatureViewModel.swift
    Views/
      MyFeatureView.swift
    Components/
      MyFeatureCard.swift
      MyFeatureEmptyStateView.swift
```

Opțional, dacă feature-ul cere date noi sau routing nou:

```text
Domain/
  Models/
    MyFeatureModel.swift

Core/
  Navigation/
    NavigationManager.swift
```

## Ordinea recomandată

1. Decide ownership-ul: model, view model, view, sau componentă.
2. Verifică `references/component-catalog.md` ca să nu recreezi un card, overlay, toolbar, sau modal deja existent.
3. Stabilește route-ul sau full-screen destination-ul dacă flow-ul cere navigație.
4. Scrie `ViewModel`-ul și stările UI.
5. Scrie `View`-ul root.
6. Extrage componente doar după ce layout-ul root s-a clarificat.
7. Leagă save/load/navigation și rulează un build.

## Checklist înainte de a începe

- [ ] Am citit `references/architecture.md`
- [ ] Am verificat `references/component-catalog.md`
- [ ] Am verificat `references/antipatterns.md`
- [ ] Am identificat dacă flow-ul are nevoie de `fullScreenSheet`
- [ ] Am identificat dacă datele trebuie salvate prin SwiftData sau doar randate
- [ ] Am verificat route-ul relevant în `NavigationManager`

## Schelet ViewModel

```swift
//
//  MyFeatureViewModel.swift
//  QuizFlash
//

import Foundation
import Observation
import OSLog
import SwiftData

// MARK: - MyFeatureViewModel

/// Owns business state, async orchestration, and persistence for a single QuizFlash feature screen.
@Observable
@MainActor
final class MyFeatureViewModel {

    // MARK: - Dependencies

    private let context: ModelContext
    private let logger = Logger(subsystem: "QuizFlash", category: "MyFeatureViewModel")

    // MARK: - State

    var items: [MyFeatureItem] = []
    var isLoading = false
    var showError = false
    var errorMessage = ""
    var activeSheet: SheetDestination?

    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    // MARK: - Init

    init(context: ModelContext) {
        self.context = context
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Public

    func load() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }

            isLoading = true
            defer { isLoading = false }

            do {
                let snapshot = try await fetchSnapshot()
                guard !Task.isCancelled else { return }
                items = snapshot
            } catch is CancellationError {
                logger.debug("Load cancelled.")
            } catch {
                logger.error("Load failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = "Couldn't load this screen right now."
                showError = true
            }
        }
    }

    func saveChanges() {
        do {
            try context.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Your changes couldn't be saved."
            showError = true
        }
    }

    // MARK: - Private

    private func fetchSnapshot() async throws -> [MyFeatureItem] {
        []
    }
}
```

## Schelet View

```swift
//
//  MyFeatureView.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

// MARK: - MyFeatureView

struct MyFeatureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var router

    @State private var viewModel: MyFeatureViewModel

    init(viewModel: MyFeatureViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            LazyVStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                ForEach(viewModel.items) { item in
                    MyFeatureCard(item: item)
                }
            }
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.bottom, UIConstants.Spacing.huge)
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .top) {
            HStack {
                Button("Back") { dismiss() }
                    .glassButton(shape: .capsule)
                Spacer()
            }
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .topNavigationChrome()
        }
        .task {
            viewModel.load()
        }
        .alert("Something went wrong", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .fullScreenSheet(item: $viewModel.activeSheet) { destination, _ in
            MyFeatureSheet(destination: destination)
        } background: {
            Color.black.opacity(0.35)
        }
    }
}
```

## Feature checklist după implementare

- [ ] View-ul root nu conține business logic, fetch-uri grele sau save direct în handler-ele de layout
- [ ] `body` nu calculează filtre/sortări/fingerprint-uri/summaries peste `@Query` sau colecții mari
- [ ] `.task(id:)` folosește id-uri/revisions cache-uite, nu hash-uri construite prin citirea tuturor modelelor în render path
- [ ] Nu am introdus `.count` pe relații SwiftData
- [ ] Task-urile înlocuibile sunt anulate înainte de restart
- [ ] Dacă am un flow imersiv, folosesc `fullScreenSheet`
- [ ] Spacing-ul și size-urile vin din `UIConstants`
- [ ] Erorile de save sunt logate și afișate clar
- [ ] Am folosit componente existente înainte să creez unele noi

## Checklist de review

- [ ] No new code reads relationship arrays just to compute `.count`
- [ ] No large SwiftData/model collection is walked from `body`, row computed properties, or scroll-driven geometry updates
- [ ] Date/calendar/formatter work used by repeated cells is precomputed in a snapshot or view model
- [ ] No new main-actor code loads heavy card blobs directly
- [ ] Stored tasks are cancellable and cancelled on replacement
- [ ] New `@Observable` view models are `@MainActor`
- [ ] Saves are explicit and failures are logged or surfaced
- [ ] New images go through `ImageCache` and new web views go through `MathWebViewPool`
- [ ] Long scroll surfaces use lazy stacks and stable chrome spacing instead of hard-coded overlay compensation
- [ ] Immersive modal flows reuse `fullScreenSheet` when they need QuizFlash drag-dismiss and backdrop behavior
- [ ] If performance was the bug, I compared before/after using Time Profiler + Allocations or explained why a trace was unnecessary
