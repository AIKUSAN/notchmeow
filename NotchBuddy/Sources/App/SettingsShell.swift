import SwiftUI
import AppKit

// The Settings window: a sidebar of the six pages and a detail area. The window's width decides the sidebar: 200 pt with names, or 56 pt with the icon tiles only below
// SettingsLayout.breakpoint. The shell hands that mode down (`settingsMode`) so a page can change its own layout, and sets the window's minimum size from SettingsLayout. A plain HStack,
// not a split view; the divider is an overlay that takes no width. `scrolls: false` stops the detail area from stretching to the window's height (the pictures use it, with `scrolls: false` on their pages).

extension EnvironmentValues {
    @Entry var settingsMode: SettingsLayout.SidebarMode = .expanded
}

struct SettingsShell<Detail: View>: View {
    let version: String
    let icon: NSImage?
    @Binding var page: SettingsRoute.Page
    let scrolls: Bool
    let detail: (SettingsRoute.Page) -> Detail

    init(version: String, icon: NSImage?, page: Binding<SettingsRoute.Page>, scrolls: Bool = true,
         @ViewBuilder detail: @escaping (SettingsRoute.Page) -> Detail) {
        self.version = version; self.icon = icon; _page = page; self.scrolls = scrolls; self.detail = detail
    }

    var body: some View {
        GeometryReader { geo in
            let mode = SettingsLayout.sidebarMode(windowWidth: geo.size.width)
            HStack(spacing: 0) {
                sidebar(mode)
                    .frame(width: SettingsLayout.sidebarWidth(mode))
                    .overlay(alignment: .trailing) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1) }
                detail(page)
                    .frame(maxWidth: .infinity, maxHeight: scrolls ? .infinity : nil, alignment: .top)
            }
            .environment(\.settingsMode, mode)
        }
        .frame(minWidth: SettingsLayout.minWidth, minHeight: SettingsLayout.minHeight)
    }

    private var tile: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable() } else { RoundedRectangle(cornerRadius: 7).fill(Color.gray.opacity(0.5)) }
        }
        .frame(width: 32, height: 32)
    }

    private func sidebar(_ mode: SettingsLayout.SidebarMode) -> some View {
        ZStack(alignment: .topLeading) {
            SidebarBackground()
            VStack(alignment: .leading, spacing: 0) {
                if mode == .icons {
                    tile.frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 10)
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        tile
                        VStack(alignment: .leading, spacing: 1) {
                            Text("NotchMeow").font(.system(size: 13, weight: .semibold))
                            Text(version).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
                }
                Divider()
                List(selection: Binding<SettingsRoute.Page?>(get: { page }, set: { if let v = $0 { page = v } })) {
                    ForEach(SettingsRoute.Page.allCases, id: \.self) { p in
                        let symbol = SettingsRoute.icon(p)
                        if mode == .icons {
                            SettingsSidebarRow(title: SettingsRoute.title(p), icon: symbol.symbol, color: symbol.color)
                                .labelStyle(.iconOnly)
                                .help(SettingsRoute.title(p))
                                .accessibilityLabel(SettingsRoute.title(p))
                                .tag(p)
                        } else {
                            SettingsSidebarRow(title: SettingsRoute.title(p), icon: symbol.symbol, color: symbol.color).tag(p)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }
}
