import CoreGraphics

// The companion chat's island height (F3a-mac, Task 2): today's 240 pt for a fresh chat plus 40 pt per message, capped at 560 pt (the spec's cap; the
// island panel has room for it). The width stays the island's 640 pt. Pure: no view and no window; the panel reads the number.
enum ChatSizing {
    static let baseHeight: CGFloat = 240
    static let perMessage: CGFloat = 40
    static let maxHeight: CGFloat = 560

    /// The island's height for a chat with `messages` messages. A negative count is no message.
    static func islandHeight(messages: Int) -> CGFloat {
        min(maxHeight, baseHeight + perMessage * CGFloat(max(0, messages)))
    }
}
