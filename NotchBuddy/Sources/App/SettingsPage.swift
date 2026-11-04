import SwiftUI

// A page of the Settings window: the title, the page's tabs (when it has any) and the result banner stay above the scroll area, so a result is seen wherever the page is scrolled; the
// cards below are one column (at most SettingsLayout.columnMax wide, centred in the detail) that scrolls. `scrolls: false` (for the pictures) lays the
// column out at its natural height instead.

struct SettingsPage<Content: View>: View {
    let page: SettingsRoute.Page
    @Binding var tab: SettingsRoute.Tab?
    let banner: String?
    let dismissBanner: () -> Void
    let scrolls: Bool
    let content: Content
    @Environment(\.settingsMode) private var mode

    init(page: SettingsRoute.Page, tab: Binding<SettingsRoute.Tab?>, banner: String? = nil, dismissBanner: @escaping () -> Void = {},
         scrolls: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.page = page; _tab = tab; self.banner = banner; self.dismissBanner = dismissBanner; self.scrolls = scrolls; self.content = content()
    }

    private var sidePadding: CGFloat { SettingsLayout.padding(mode) }

    /// The column: as wide as the detail less the side padding, at most columnMax, centred beyond that.
    private func column<V: View>(_ view: V) -> some View {
        view.frame(maxWidth: SettingsLayout.columnMax, alignment: .leading)
            .padding(.horizontal, sidePadding)
            .frame(maxWidth: .infinity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            column(
                VStack(alignment: .leading, spacing: 10) {
                    Text(SettingsRoute.title(page)).font(.title2).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
                    if !SettingsRoute.tabs(page).isEmpty { SettingsTabBar(tabs: SettingsRoute.tabs(page), selection: $tab) }
                    if let banner, !banner.isEmpty { SettingsBanner(banner, dismiss: dismissBanner) }
                }
                .padding(.top, 20).padding(.bottom, 12)
            )
            if scrolls {
                ScrollView { column(cards.padding(.bottom, 16)) }
            } else {
                column(cards.padding(.bottom, 16))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: scrolls ? .infinity : nil, alignment: .top)
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 18) { content }
    }
}
