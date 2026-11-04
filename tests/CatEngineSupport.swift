import Foundation

/// A clock the tests move by hand, in milliseconds.
@MainActor
final class FakeClock { var t = 0.0 }
