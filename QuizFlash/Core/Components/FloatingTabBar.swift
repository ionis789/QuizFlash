import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    @ObservedObject var router: NavigationManager

    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    handleTabSelection(tab)
                } label: {
                    tabItem(tab)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(cornerRadius: 40, style: .spotlight)
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        
    }

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        ZStack {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.18))
                    .padding(4)
                    
            }

            VStack(spacing: 8) {
                Image(systemName: isSelected ? (tab.icon + ".fill") : tab.icon)
                    .font(.title3.bold())

                
                    Text(tab.title)
                    .font(.caption.bold())
                        
                
            }
            .foregroundStyle(isSelected ? accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .frame(height: 46)
        
    }

    private func handleTabSelection(_ tab: AppTab) {
        if selectedTab == tab {
            if tab == .library {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    router.popToRoot()
                }
            }
        } else {
           
                selectedTab = tab
            
        }
    }
}
