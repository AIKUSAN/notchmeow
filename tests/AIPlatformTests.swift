import Foundation

@main
@MainActor
enum AIPlatformTests {
    static func main() async {
        AILog.sink.replace { _ in }
        await network()
        await apple()
        T.finish()
    }

    static func network() async {
        T.section("NetworkMonitor")
        let changed = Flag()
        NetworkMonitor.shared.start { _ in changed.set() }
        for _ in 0..<40 where !changed.value { try? await Task.sleep(nanoseconds: 50_000_000) }
        T.checkTrue("reports the path once started", changed.value)
        T.checkTrue("this machine is online", NetworkMonitor.shared.isOnline)
    }

    static func apple() async {
        T.section("Apple on-device")
        let status = AppleOnDevice.status()
        print("  · status on this Mac: \(status) (\(status.line ?? "hidden"))")
        T.checkTrue("context is at least 4,096 tokens", AppleOnDevice.contextTokens() >= 4096)
        if #unavailable(macOS 26) {
            T.checkTrue("no provider before macOS 26", AppleOnDevice.provider() == nil)
        }
        // Real generation is opt-in (CI runners have no Apple Intelligence): NM_TEST_APPLE=1.
        guard ProcessInfo.processInfo.environment["NM_TEST_APPLE"] == "1", status == .ready,
              let provider = AppleOnDevice.provider() else { return }
        var acc = ReplyAccumulator(stripsThinkBlocks: false)
        let request = ChatRequest(model: "system", system: "Answer in one word.",
                                  messages: [.init(role: .user, parts: [.text("Say hello.")])])
        do {
            for try await chunk in provider.stream(request) { acc.add(chunk) }
        } catch {
            T.checkTrue("Apple generation failed: \(error)", false)
        }
        T.checkTrue("Apple's model answered (\(acc.text))", !acc.text.isEmpty)
    }

}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    func set() { lock.withLock { on = true } }
    var value: Bool { lock.withLock { on } }
}
