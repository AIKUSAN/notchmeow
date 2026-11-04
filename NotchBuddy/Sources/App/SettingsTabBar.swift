import SwiftUI

// A page's tabs as plain text under the title: the selected one in the accent colour with a 2 pt underline, the same row height on every page. When the labels do not fit the
// column the whole bar becomes a pop-up menu that shows the current tab. That is the only fallback: a label is never shortened, wrapped or scrolled, and there is no segmented control.

struct SettingsTabBar: View {
    let tabs: [SettingsRoute.Tab]
    @Binding var selection: SettingsRoute.Tab?
    init(tabs: [SettingsRoute.Tab], selection: Binding<SettingsRoute.Tab?>) { self.tabs = tabs; _selection = selection }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                ForEach(tabs, id: \.self) { tab in
                    Button { selection = tab } label: {
                        // The underline is as wide as the label: the stack is fixed to its ideal size, so the line cannot stretch the tab.
                        VStack(spacing: 0) {
                            Text(SettingsRoute.title(tab)).font(.system(size: 13)).frame(height: SettingsLayout.tabBarHeight - 2)
                            Rectangle().fill(selection == tab ? Color.accentColor : Color.clear).frame(height: 2)
                        }
                        .fixedSize()
                        .foregroundColor(selection == tab ? Color.accentColor : Color.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            Menu {
                ForEach(tabs, id: \.self) { tab in
                    Button(SettingsRoute.title(tab)) { selection = tab }
                }
            } label: {
                Text(SettingsRoute.title(selection.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs.first ?? .general)).fixedSize()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .frame(height: SettingsLayout.tabBarHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }
}
