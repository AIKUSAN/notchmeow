import SwiftUI

// Settings → Services: one card per service (Resend, n8n, Vercel, GitHub, Stripe, Cal.com, Notion, Music). Each card's header carries the colour dot, the name and the chip; its body has
// the "Show on the island" switch, one key field per Keychain item (a KeyRow with no Save of its own), its help, its filter behind "Choose which to watch", and one Save that writes
// that card's fields only. The drafts come in through closures, so the page names no draft store and no Keychain (Task 10 wires them).

struct ServiceFieldModel: Identifiable {
    let id: String                // the Keychain key
    var placeholder: String
    var secure: Bool
}

struct ServiceFilterModel {
    var label: String
    var items: [String]
    var filter: Binding<Set<String>>
    var loading: Bool
    var onLoad: () -> Void
}

struct ServiceCardModel: Identifiable {
    let id: String                // the pill id
    var name: String
    var color: String
    var chip: String?
    var pill: PillSwitchModel
    var fields: [ServiceFieldModel]
    var help: String?
    var filter: ServiceFilterModel?
}

struct ServicesSettingsPage: View {
    let cards: [ServiceCardModel]
    let text: (String) -> Binding<String>
    let dirty: (String) -> Bool
    let saved: (String) -> Bool
    let save: (String) -> Void
    let toggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(cards) { card in serviceCard(card) }
        }
    }

    private func serviceCard(_ card: ServiceCardModel) -> some View {
        SettingsCard(card.name, summary: card.chip, dot: Color(hex: card.color)) {
            PillSwitchRow(pill: card.pill, label: "Show on the island", dot: false, toggle: toggle)
            ForEach(card.fields) { field in
                KeyRow(field.placeholder, text: text(field.id), saved: saved(field.id), dirty: dirty(field.id), secure: field.secure)
            }
            if let help = card.help { HelpText(help) }
            if let filter = card.filter {
                DisclosureGroup("Choose which to watch") {
                    IntegrationFilterRow(label: filter.label, items: filter.items, filter: filter.filter, loading: filter.loading, onLoad: filter.onLoad)
                }
            }
            if !card.fields.isEmpty {
                saveButton(card, dirty: card.fields.contains { dirty($0.id) })
            }
        }
    }

    /// One Save for the card's fields: prominent and enabled only while one of them differs from what is stored, plain and disabled otherwise.
    @ViewBuilder private func saveButton(_ card: ServiceCardModel, dirty: Bool) -> some View {
        if dirty {
            Button("Save") { save(card.id) }.buttonStyle(.borderedProminent)
        } else {
            Button("Save") { save(card.id) }.buttonStyle(.bordered).disabled(true)
        }
    }
}
