import Foundation

/// Drives EVE/Features/Connection. See docs/roadmap.md Milestone 1.
enum ConnectionState: Equatable {
    case unknown
    case connected
    case offline
    case unauthenticated
}
