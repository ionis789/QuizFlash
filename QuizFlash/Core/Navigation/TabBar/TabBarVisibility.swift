import SwiftUI

// MARK: - Tab Bar Visibility Rules
enum TabBarVisibilityRule: Equatable {
    /// Standard behavior: Visible on Root, Hidden on push in a NavigationStack.
    case implicit
    /// Forces the Tab Bar to be visible, overriding the implicit rule.
    case visible
    /// Forces the Tab Bar to be hidden, overriding the implicit rule.
    case hidden
}

// MARK: - Preference Key
struct TabBarVisibilityKey: PreferenceKey {
    static var defaultValue: TabBarVisibilityRule = .implicit
    
    static func reduce(value: inout TabBarVisibilityRule, nextValue: () -> TabBarVisibilityRule) {
        let next = nextValue()
        // If a child view dictates a strict rule (.visible or .hidden),
        // it overrides the implicit rule of the hierarchy.
        if next != .implicit {
            value = next
        }
    }
}

// MARK: - View Extension
extension View {
    /// Modifier to control the visibility of the Custom Tab Bar globally.
    func customTabBarVisibility(_ rule: TabBarVisibilityRule) -> some View {
        self.preference(key: TabBarVisibilityKey.self, value: rule)
    }
}

// MARK: - Sheet-Driven Visibility

struct TabBarSheetVisibilityAction {
    var update: (UUID, Bool) -> Void

    func setHidden(_ isHidden: Bool, for id: UUID) {
        update(id, isHidden)
    }
}

private struct TabBarSheetVisibilityActionKey: EnvironmentKey {
    static let defaultValue = TabBarSheetVisibilityAction { _, _ in }
}

extension EnvironmentValues {
    var tabBarSheetVisibilityAction: TabBarSheetVisibilityAction {
        get { self[TabBarSheetVisibilityActionKey.self] }
        set { self[TabBarSheetVisibilityActionKey.self] = newValue }
    }
}

// MARK: - Smart Visibility Modifier
struct HideTabBarOnPushModifier: ViewModifier {
    @Environment(\.isPresented) private var isPresented
    
    func body(content: Content) -> some View {
        content
            // Când isPresented devine false (la swipe back), trimite instant .implicit
            .customTabBarVisibility(isPresented ? .hidden : .implicit)
    }
}

extension View {
    /// Folosește asta în loc de `.customTabBarVisibility(.hidden)` pentru ecranele rutiere
    func hideTabBarOnPush() -> some View {
        self.modifier(HideTabBarOnPushModifier())
    }
}
