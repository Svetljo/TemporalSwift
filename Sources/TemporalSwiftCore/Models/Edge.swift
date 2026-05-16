import Foundation

/// Represents a directional relationship between two nodes in the temporal graph.
///
/// Edges are created once and never deleted in v1. Temporal validity is managed
/// via ``TemporalState`` records whose ``TemporalBounds/validUntil`` can be set
/// to express when a relationship ended.
public struct Edge: Codable, Sendable, Hashable, Identifiable {
    /// System-generated unique identifier.
    public let id: UUID
    /// Relationship type label (e.g., "lives_in", "knows").
    public let type: String
    /// ID of the source node.
    public let sourceID: UUID
    /// ID of the target node.
    public let targetID: UUID
    /// Arbitrary key-value attributes at creation time.
    public let attributes: [String: AttributeValue]
    /// Timestamp when this edge was created.
    public let createdAt: Date

    /// Creates a new `Edge`.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (typically assigned by the store).
    ///   - type: Relationship type label. Must not be empty.
    ///   - sourceID: ID of the source node.
    ///   - targetID: ID of the target node.
    ///   - attributes: Initial attribute dictionary.
    ///   - createdAt: Creation timestamp.
    public init(
        id: UUID,
        type: String,
        sourceID: UUID,
        targetID: UUID,
        attributes: [String: AttributeValue],
        createdAt: Date
    ) {
        self.id = id
        self.type = type
        self.sourceID = sourceID
        self.targetID = targetID
        self.attributes = attributes
        self.createdAt = createdAt
    }
}
