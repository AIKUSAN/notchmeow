import Foundation

/// A settings store that lives in a dictionary, so a test run never writes a preferences file. It counts the writes, in order.
final class MemoryBacking: CatSettingsBacking {
    var values: [String: Any] = [:]
    private(set) var writes: [String] = []
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { writes.append(key); values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    func allKeys() -> [String] { Array(values.keys) }
}
