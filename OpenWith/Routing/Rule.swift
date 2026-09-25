import Foundation

/// A saved "this domain goes to that browser" decision.
struct Rule: Codable, Identifiable, Hashable, Sendable {
    var domain: String
    var browserID: String

    var id: String { domain }
}
