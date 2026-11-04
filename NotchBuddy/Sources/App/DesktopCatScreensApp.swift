import AppKit

// The app's way into the contract's screens: `NSScreen.screens` as `DesktopCatScreens` takes them. Nothing here is in the contract, and the test programs do not compile this file.

extension DesktopCatScreens.AppKitScreen {
    /// The screens now, the one with the menu bar first.
    @MainActor static var all: [DesktopCatScreens.AppKitScreen] {
        NSScreen.screens.map { s in
            DesktopCatScreens.AppKitScreen(frame: DesktopRect(x: Double(s.frame.minX), y: Double(s.frame.minY), w: Double(s.frame.width), h: Double(s.frame.height)),
                                           visible: DesktopRect(x: Double(s.visibleFrame.minX), y: Double(s.visibleFrame.minY), w: Double(s.visibleFrame.width), h: Double(s.visibleFrame.height)))
        }
    }
}
