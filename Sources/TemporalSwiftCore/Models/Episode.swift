import Foundation

/// A logical grouping of related temporal state changes.
///
/// Episodes let consumers associate a set of ``TemporalState`` mutations
/// with a single named event (e.g., "conversation-42", "import-batch-7").
public struct Episode: Codable, Sendable, Hashable, Identifiable {
    /// Unique episode identifier.
    public let id: UUID
    /// Human-readable description of the episode.
    public let description: String?
    /// IDs of the ``TemporalState`` records that belong to this episode.
    public let stateIDs: [UUID]
    /// When this episode occurred.
    public let timestamp: Date

    /// Creates a new `Episode`.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (assigned by the store).
    ///   - description: Optional human-readable description.
    ///   - stateIDs: IDs of the temporal states in this episode.
    ///   - timestamp: When the episode occurred.
    public init(id: UUID, description: String?, stateIDs: [UUID], timestamp: Date) {
        self.id = id
        self.description = description
        self.stateIDs = stateIDs
        self.timestamp = timestamp
    }
}
