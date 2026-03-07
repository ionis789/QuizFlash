import SwiftUI

// MARK: - Deck Custom Navigation Bar
/// A unified, safe-area respectful custom navigation bar.
/// Uses a ZStack to guarantee the center pill remains absolutely centered
/// regardless of the leading/trailing item widths.
struct DeckCustomNavigationBar: View {
    let deck: DeckModel
    let stats: DeckStats
    let backLabel: String
    let searchQuery: String?

    // Action Dependencies
    let isSelecting: Bool
    @Binding var isMenuExpanded: Bool
    @Binding var menuPosition: CGRect
    let menuTracker: MenuPositionTracker

    // Closures
    let onBack: () -> Void
    let onAdd: () -> Void
    let onStartSelection: () -> Void
    let onExport: () -> Void

    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        ZStack(alignment: .center) {

            // 1. Center: The Collapsed Pill (DeckHeroView)
            // It manages its own opacity/scale internally via DeckScrollState.
            if searchQuery == nil {
                DeckHeroView(deck: deck, stats: stats)
                    .allowsHitTesting(false) // Prevents the pill from intercepting touches
            }

            // 2. Edges: Back Button & Action Controls
            HStack(alignment: .center) {

                // Leading: Back Button
                Button(action: onBack) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.compact.left")
                            .font(.system(size: 24, weight: .bold)).fontDesign(.rounded)
                        Text(backLabel)
                            .font(.system(size: 13, weight: .bold))
                            .fontDesign(.rounded)
                    }
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(height: 50)
                        .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                            Capsule()
                                .fill(Color.white.opacity(0.35))
                                .blur(radius: 10)
                                .mask(Capsule().stroke(lineWidth: 4))
                                .blendMode(.overlay)
                        }
                    }
                }
                    .buttonStyle(.plain)

                Spacer()

                // Trailing: Action Overlays (+ and ...)
                DeckActionOverlay(
                    deck: deck,
                    isSelecting: isSelecting,
                    isMenuExpanded: $isMenuExpanded,
                    menuPosition: $menuPosition,
                    menuTracker: menuTracker,
                    onAdd: onAdd,
                    onStartSelection: onStartSelection,
                    onExport: onExport
                )
            }
        }
        // Apply global padding for the entire Navigation Bar here,
        // removing the need for scattered hardcoded paddings in sub-components.
        .padding(.horizontal, 16)
            .padding(.top, 8)
    }
}
