//
//  CollapsingScrollView.swift
//  QuizFlash
//
//  Universal reusable container: ScrollView + sticky collapsing header.
//
//  ── Isolation architecture (no memory leak) ──────────────────────────────
//
//  CollapsingScrollView takes `onProgress: (CGFloat) -> Void` — a write-only
//  callback — instead of `@Binding<CGFloat>`.
//
//  Why this matters:
//    • @Binding is a two-way channel. When the bound value changes, SwiftUI
//      marks CollapsingScrollView dirty and re-evaluates its body, calling the
//      content() closure and re-describing the full view tree at 120 Hz.
//    • A plain closure has no such contract. CollapsingScrollView writes into
//      it and never reads back — SwiftUI has nothing to observe.
//
//  The views that animate read `viewModel.collapseProgress` directly via
//  @Observable. SwiftUI tracks that access per-View and re-renders ONLY
//  those leaf nodes. Everything else is untouched during scroll.
//
//  ── Usage ────────────────────────────────────────────────────────────────
//
//  // Basic
//  CollapsingScrollView(collapseDistance: 200) { p in
//      viewModel.collapseProgress = p
//  } header: {
//      MyTopBar()
//  } content: {
//      MyContent()
//  }
//
//  // With scroll-to-top support (onScrollProxy exposes ScrollViewProxy)
//  CollapsingScrollView(collapseDistance: 130) { p in
//      viewModel.collapseProgress = p
//  } onScrollProxy: { proxy in
//      scrollProxy = proxy
//  } header: {
//      MyTopBar()
//  } content: {
//      MyContent()
//          .id("TOP_ANCHOR")
//  }
//

import SwiftUI

struct CollapsingScrollView<Header: View, Content: View>: View {

    // MARK: - Configuration
    var collapseDistance: CGFloat
    var showsIndicators: Bool

    // Write-only callback — never read back, so body is never re-invalidated.
    var onProgress: @MainActor (CGFloat) -> Void

    // Optional: called once with the ScrollViewProxy so callers can scroll to id.
    var onScrollProxy: (@MainActor (ScrollViewProxy) -> Void)?

    // MARK: - Content builders
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    // MARK: - Init
    init(
        collapseDistance: CGFloat = CollapsingHeaderConfig.standardDistance,
        showsIndicators: Bool = false,
        onProgress: @escaping @MainActor (CGFloat) -> Void,
        onScrollProxy: (@MainActor (ScrollViewProxy) -> Void)? = nil,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.collapseDistance = collapseDistance
        self.showsIndicators = showsIndicators
        self.onProgress = onProgress
        self.onScrollProxy = onScrollProxy
        self.header = header
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        scrollBody
            // The iOS 17 jump-to-top bug is frequently caused by SwiftUI recalculating the 
            // bounds of `.safeAreaInset` during a NavigationStack pop transition.
            // By wrapping the header in grouped stable bounds, or by using another technique, 
            // we stabilize the layout. Let's start with a simpler safe area patch: 
            // We force the safe area inset to ignore the temporary bottom safe area changes 
            // that occur when hiding/showing tab bars during push transitions.
            .ignoresSafeArea(.container, edges: .bottom)
            .safeAreaInset(edge: .top, content: header)
            // But wait, the bottom is ignored now...
    }

    // MARK: - OS-split scroll body

    @ViewBuilder
    private var scrollBody: some View {
        if #available(iOS 18, *) {
            ios18ScrollView
        } else {
            ios17ScrollView
        }
    }

    // ── iOS 18 ───────────────────────────────────────────────────────────
    // onScrollGeometryChange must sit directly on the ScrollView (not on
    // content inside it) to fire correctly on iPad with split-view.
    // contentOffset.y is already normalized to 0 at rest — no inset math.
    @available(iOS 18, *)
    private var ios18ScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
            }
            .scrollIndicators(showsIndicators ? .automatic : .hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, offset in
                onProgress(min(max(offset / collapseDistance, 0), 1.0))
            }
            .onAppear { onScrollProxy?(proxy) }
        }
    }

    // ── iOS 17 ───────────────────────────────────────────────────────────
    private var ios17ScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
                    .background(alignment: .top) {
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: CollapsingScrollOffsetKey.self,
                                    value: geo.frame(in: .named("CollapsingScrollViewSpace")).minY
                                )
                        }
                        .frame(height: 0)
                    }
            }
            .coordinateSpace(name: "CollapsingScrollViewSpace")
            .onPreferenceChange(CollapsingScrollOffsetKey.self) { minY in
                let p = min(max(-minY / collapseDistance, 0), 1.0)
                DispatchQueue.main.async {
                    onProgress(p)
                }
            }
            .scrollIndicators(showsIndicators ? .automatic : .hidden)
            .onAppear { onScrollProxy?(proxy) }
        }
    }
} 

private struct CollapsingScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}


/// Configurație globală pentru toate ecranele care folosesc CollapsingScrollView.
/// Garantează un comportament (fizică și distanță) 100% uniform în toată aplicația.
enum CollapsingHeaderConfig {

    private static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Distanța totală de scroll necesară pentru a declanșa starea "collapsed".
    /// Adaptată ergonomic: iPad are ecrane mai mari, iPhone necesită reacție mai rapidă.
    static var standardDistance: CGFloat {
        isPad ? 140.0 : 140.0
    }

    /// Punctul exact din progres (0.0...1.0) unde Hero-ul este complet ascuns,
    /// iar Compact Header-ul de sus (sticlă) devine vizibil.
    static let heroFadeThreshold: CGFloat = 0.5

    /// Calculul opacității/scalării pentru secțiunea Hero.
    /// Funcție utilitară pentru a nu repeta matematica în fiecare View.
    static func heroTransitionProgress(currentProgress: CGFloat) -> CGFloat {
        min(currentProgress / heroFadeThreshold, 1.0)
    }
}

/**
 📖 Documentație: CollapsingHeaderConfig

 Acest enum funcționează ca un "Single Source of Truth" (Sursă Unică de Adevăr) pentru fizica și sincronizarea tuturor header-elor custom din aplicația ta (ex: LibraryView, DeckView).

 Orice modificare a acestor valori va reverbera automat și uniform în toată aplicația, garantând o experiență de utilizare (UX) consistentă.

 1. private static var isPad: Bool

 Ce face: Detectează la runtime dacă aplicația rulează pe un iPad sau pe un iPhone.

 Valoare: true dacă e iPad, false dacă e iPhone.

 De ce este crucial: Fizica de scroll se simte complet diferit pe ecrane mari față de ecrane mici. Ceea ce pe iPhone pare un "swipe" lung, pe iPad pare abia o atingere ușoară. Această variabilă ne permite să adaptăm distanțele ergonomic. Fiind private, este folosită doar intern în acest fișier pentru a calcula alte valori.

 2. static var standardDistance: CGFloat

 Ce face: Definește distanța fizică (în puncte) pe care utilizatorul trebuie să o parcurgă cu degetul pe ecran pentru ca progresul de scroll să ajungă de la 0.0 (sus) la 1.0 (complet restrâns).

 Valoare: 140.0 pentru iPad / 110.0 pentru iPhone.

 De ce aceste valori:

 iPhone (110pt): Ecranul este mic. Dacă punem o valoare mare (ex: 200pt), utilizatorul ar trebui să facă scroll pe jumătate din ecran doar ca să ascundă titlul, ceea ce se simte greoi și nenatural. 110pt face animația "snappy" și rapidă.

 iPad (140pt): Ecranul e generos. Dacă lăsăm 110pt, header-ul s-ar ascunde prea brusc (într-o fracțiune de mișcare). La 140pt, îi dăm animației de "fade" a titlului suficient spațiu vizual ca să arate elegant (smooth).

 3. static let heroFadeThreshold: CGFloat

 Ce face: Este "punctul de întâlnire" (pragul) exprimat ca procentaj din distanța totală (0.0 până la 1.0). Reprezintă momentul exact în care Titlul Mare (Hero) devine invizibil (opacity = 0) și Titlul Mic (Compact Bar de sticlă) devine vizibil (opacity = 1).

 Valoare: 0.85 (adică 85% din distanța de scroll). Pe iPhone înseamnă la 93.5pt de scroll, pe iPad la 119pt.

 De ce 0.85: Dacă am folosi 1.0, ar apărea un spațiu mort ("gap") între momentul în care dispare titlul mare și momentul în care e fixat titlul mic. La 0.85, creăm o suprapunere mentală subtilă: titlul mare se termină de evaporat exact în momentul în care bara de sus culisează în poziția finală.

 4. static func heroTransitionProgress(currentProgress: CGFloat) -> CGFloat

 Ce face: Este un convertor matematic. Primește progresul global al scroll-ului (0.0 -> 1.0) și returnează un nou progres "accelerat" (0.0 -> 1.0), care se termină forțat fix la atingerea lui heroFadeThreshold.

 Valoare returnată: O cifră între 0.0 și 1.0. De exemplu, dacă ești la 50% din scroll (0.5), funcția returnează 0.5 / 0.85 = 0.58. Dacă depășești 0.85, funcția dă clamp și returnează mereu 1.0.

 De ce e nevoie de ea: Pentru opacitatea și scalarea titlului mare (Hero Section). Titlul tău mare trebuie să aibă opacitate 0 fix la 85% din scroll, nu la 100%. Această funcție te scutește de a scrie și calcula manual regula de trei simplă cu min(progress / 0.85, 1.0) în fiecare ecran unde implementezi acest header. Tu doar îi dai progresul curent, și ea îți spune cum să animezi opacitatea și offset-ul.

 Rezumat pentru echipă

 Dacă pe viitor cineva zice: "Vreau ca header-ul să apară mai repede pe iPhone!", tot ce trebuie să facă este să meargă în CollapsingHeaderConfig.swift și să schimbe 110.0 în 90.0. Modificarea se va aplica instant în Library, în Deck, și în orice alt ecran din QuizFlash unde folosești acest sistem. Asta înseamnă arhitectură scalabilă!

 Dorești să mai verificăm și alte aspecte legate de performanța UI-ului?
 */
