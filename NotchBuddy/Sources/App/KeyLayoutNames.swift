import AppKit
import Carbon.HIToolbox

/// The character printed on a key in a keyboard layout. Carbon hot keys are physical key positions: the key labelled
/// A on a French AZERTY keyboard is virtual key code 12, which the US layout calls Q. Settings shows what is printed
/// on the key the person has to press, so it asks the layout in use.
enum KeyLayoutNames {
    /// The key's character in the layout in use (upper case), nil for a key that prints nothing (arrows, Space, F1).
    @MainActor static func name(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return name(for: keyCode, in: source)
    }

    /// The same for one layout, such as `layout(id: "com.apple.keylayout.French")`.
    @MainActor static func name(for keyCode: UInt16, in source: TISInputSource) -> String? {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            let name = String(utf16CodeUnits: chars, count: length).uppercased()
            let printable = name.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespaces.contains($0)
            }
            return printable ? name : nil
        }
    }

    /// An installed keyboard layout by its input-source ID, whether or not it is enabled.
    @MainActor static func layout(id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else { return nil }
        return list.first
    }
}
