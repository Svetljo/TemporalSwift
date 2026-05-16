import Foundation

/// Represents an entity (vertex) in the temporal knowledge graph.
///
/// Nodes are created once and never deleted in v1 (append-only model).
/// Attribute evolution is tracked via ``TemporalState`` records.
public struct Node: Codable, Sendable, Hashable, Identifiable {
    /// System-generated unique identifier.
    public let id: UUID
    /// Entity type label (e.g., "Person", "Location").
    public let type: String
    /// Arbitrary key-value attributes at creation time.
    public let attributes: [String: AttributeValue]
    /// Timestamp when this node was created.
    public let createdAt: Date

    /// Creates a new `Node`.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (typically assigned by the store).
    ///   - type: Entity type label. Must not be empty.
    ///   - attributes: Initial attribute dictionary.
    ///   - createdAt: Creation timestamp.
    public init(id: UUID, type: String, attributes: [String: AttributeValue], createdAt: Date) {
        self.id = id
        self.type = type
        self.attributes = attributes
        self.createdAt = createdAt
    }
}
