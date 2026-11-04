import SwiftUI
import QuartzCore

#if DEBUG && !APPSTORE

/// The Wardrobe section of the Debug-only cat panel (sub-project I): a live big cat in any outfit on any coat at any size (on a `CatConfig` of its own: the app's cats are untouched), and the two
/// controls the owner's real-build checks need, which DO reach the running app's Auto: a date Auto reads instead of today's, and a pretend midnight five seconds away. They go through
/// notifications that the app's `WardrobeClock` listens to in a Debug build, so this file compiles without the app. Compiled in Debug builds only (`WardrobeDev.marker`).
extension WardrobeDev {
    /// In a Debug build and in no other (19 bytes: a shorter string would hide in the code where `strings` cannot see it).
    static let marker = "NM_CAT_DEV_WARDROBE"
    static let sizes: [Double] = [12, 20, 28, 48, 64, 96]
}

struct WardrobeDevView: View {
    @State private var outfit = "santahat"
    @State private var coat = "momo"
    @State private var size = 64.0
    @State private var date = ""
    @State private var note = "No date is pretended: Auto reads today's."
    private let config = CatConfig()

    var body: some View {
        GroupBox("Wardrobe") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    WardrobePreviewView(coat: coat, outfit: outfit, head: size, active: true, config: config)
                        .frame(width: 200, height: 170)
                        .accessibilityIdentifier(WardrobeDev.marker)
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Outfit", selection: $outfit) { ForEach(Wardrobe.drawn, id: \.self) { Text(Wardrobe.name($0)).tag($0) } }
                        Picker("Coat", selection: $coat) { ForEach(CatPresets.ids, id: \.self) { Text(CatPresets.byID($0).label).tag($0) } }
                        Picker("Size", selection: $size) { ForEach(WardrobeDev.sizes, id: \.self) { Text("Ø\(Int($0))").tag($0) } }.pickerStyle(.segmented)
                    }
                }
                HStack(spacing: 8) {
                    Text("Pretend today is").frame(width: 120, alignment: .leading)
                    TextField("2026-12-24", text: $date).frame(width: 120)
                    Button("Apply") {
                        if let day = Wardrobe.parseDay(date) {
                            NotificationCenter.default.post(name: WardrobeDev.dateNote, object: nil, userInfo: ["day": date])
                            note = "Auto reads \(date) and wears \(Wardrobe.autoLabel(today: Wardrobe.autoOutfit(day)).replacingOccurrences(of: "Auto: today, ", with: ""))."
                        } else { note = "A date looks like 2026-12-24." }
                    }
                    Button("Back to today") {
                        date = ""
                        NotificationCenter.default.post(name: WardrobeDev.dateNote, object: nil, userInfo: ["day": ""])
                        note = "No date is pretended: Auto reads today's."
                    }
                    Button("Midnight in 5 s") {
                        NotificationCenter.default.post(name: WardrobeDev.midnightNote, object: nil)
                        note = "The wardrobe's one timer fires in five seconds and the pretend date moves on a day."
                    }
                }
                Text(note).font(.system(size: 11)).foregroundColor(.secondary)
                Text("The cat above is drawn on its own settings. The date and the midnight reach the running app's Auto (only while Auto is the stored choice), in Debug builds only.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

#endif
