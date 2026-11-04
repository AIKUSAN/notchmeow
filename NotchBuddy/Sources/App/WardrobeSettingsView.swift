import AppKit
import QuartzCore
import SwiftUI

// Settings → Cat → Outfits (sub-project I's Wardrobe), its own card of the Outfits tab, built from the kit (SettingsCard, SettingRow, HelpText) with tiles like the Main cat's. A live preview
// of the Main cat shows the outfit under the pointer, else the chosen one; a coat picker beside it shows the same outfit on any of the 16 coats and changes nothing that is stored. A tile
// click chooses and stores (`CatSettingsStore.setOutfit`). The Auto tile shows what Auto wears today.

struct WardrobeSettingsGroup: View {
    @ObservedObject var store: CatSettingsStore
    let active: Bool
    /// Today's date, for Auto (the app passes `WardrobeClock.appToday`, which a Debug build can override).
    let day: () -> Wardrobe.Day
    /// The tile under the pointer, shown in the preview.
    @State private var hovered: String?
    /// The coat the preview shows. It starts as the Main cat and is never stored.
    @State private var previewCoat: String?

    private var coat: String { previewCoat ?? store.settings.character }
    private var chosen: String { store.wardrobe.outfit }
    private var shown: String { hovered ?? chosen }
    /// What Auto wears today: an outfit's ID or "none".
    private var autoToday: String { Wardrobe.autoOutfit(day()) }
    private func resolved(_ id: String) -> String { Wardrobe.resolve(id, day()) }

    var body: some View {
        SettingsCard("Wardrobe") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    WardrobePreviewView(coat: coat, outfit: resolved(shown), head: 76, active: active, config: store.config)
                        .frame(width: 130, height: 150)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(shown == "auto" ? Wardrobe.autoLabel(today: autoToday) : Wardrobe.name(shown)).font(.system(size: 13, weight: .semibold))
                        SettingRow("Preview on") {
                            Picker("", selection: Binding(get: { coat }, set: { previewCoat = $0 })) {
                                ForEach(CatPresets.ids, id: \.self) { Text(CatPresets.byID($0).label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        HelpText("Every big cat wears it: the notch's cat, both cats of Two cats mode, each agent's big cat and the cat on your desktop. Kittens and the small cats stay bare. The coat only changes this preview.")
                    }
                }
                ForEach(Wardrobe.groups, id: \.id) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        if !group.name.isEmpty { Text(group.name).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                            ForEach(group.ids, id: \.self) { tile($0) }
                        }
                    }
                }
                HelpText("Auto follows the date: new year, Christmas, Halloween, Easter and summer. Pick one outfit to keep it all year.")
            }
            .accessibilityIdentifier(CatOutfitDraw.marker)
        }
    }

    private func tile(_ id: String) -> some View {
        let selected = id == chosen, label = id == "auto" ? Wardrobe.autoLabel(today: autoToday) : Wardrobe.name(id)
        return Button { store.setOutfit(id) } label: {
            VStack(spacing: 0) {
                WardrobeTileView(coat: coat, outfit: resolved(id))
                    .frame(width: 66, height: 56)
                Text(label)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
                    .foregroundColor(selected ? .primary : .secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.16) : Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = id } else if hovered == id { hovered = nil }
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
