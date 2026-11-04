import Foundation

extension ShelfModel {
    /// The app's shelf: shelf.json and the copies live in the app's support folder (`HookServer.supportDir`, the same folder as the inbox).
    @MainActor static let shared = ShelfModel(store: ShelfStore(support: HookServer.supportDir))
}
