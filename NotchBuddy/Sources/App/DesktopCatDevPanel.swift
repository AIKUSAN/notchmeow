import SwiftUI
import QuartzCore

#if DEBUG && !APPSTORE

/// The Desktop section of the Debug-only cat panel (sub-project H): a mock desktop with the big cat, buttons that fire the alert flight into the notch and clear it, the size picker, the kittens,
/// and a live readout of the frame rate the rule picks and what a frame costs. The real desktop cat is not touched. Compiled in Debug builds only (`DesktopCatDevModel.marker`).
struct DesktopCatDevView: View {
    @StateObject private var model = DesktopCatDevModel()

    var body: some View {
        GroupBox("Desktop") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button("Fire an alert") { model.fireAlert() }.disabled(model.alertIsOn)
                    Button("Clear the alert") { model.clearAlert() }.disabled(!model.alertIsOn)
                    Picker("", selection: Binding(get: { model.size }, set: { model.pick(size: $0) })) {
                        Text("Small Ø48").tag(DesktopSize.small)
                        Text("Medium Ø64").tag(DesktopSize.medium)
                        Text("Large Ø96").tag(DesktopSize.large)
                    }.pickerStyle(.segmented).frame(maxWidth: 300)
                    Stepper("Kittens: \(model.kittens)", value: Binding(get: { model.kittens }, set: { model.pick(kittens: $0) }), in: 0...8).frame(maxWidth: 150)
                }
                // The frame rate follows the rule: the outer view looks again four times a second and gives the inner one its interval, so a cat that is not drawn runs nothing.
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let fps = model.fps()
                    VStack(alignment: .leading, spacing: 6) {
                        TimelineView(.animation(minimumInterval: 1 / max(fps, 0.5), paused: fps == 0)) { timeline in
                            Canvas { context, size in
                                _ = timeline.date
                                model.advance()
                                context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: 0.15, green: 0.2, blue: 0.36), Color(red: 0.47, green: 0.29, blue: 0.47)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                                context.fill(Path(roundedRect: CGRect(x: size.width / 2 - 58, y: -12, width: 116, height: 36), cornerRadius: 12), with: .color(.black))
                                context.withCGContext { cg in model.draw(cg, dpr: Double(context.environment.displayScale)) }
                            }
                            .frame(width: DesktopCatDevModel.stage.w, height: DesktopCatDevModel.stage.h)
                            .accessibilityIdentifier(DesktopCatDevModel.marker)
                        }
                        Text(model.readout).font(.system(size: 11).monospacedDigit()).foregroundColor(.secondary)
                    }
                }
                Text("A mock desktop: the notch at the top, the cat's spot below it. The alert flight, the frame rate and the cost are the real rules and the real drawing function; the app's own desktop cat is untouched.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

#endif
