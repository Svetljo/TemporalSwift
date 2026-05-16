import Foundation

/// A versioned, immutable snapshot of an entity's attributes at a point in time.
///
/// `TemporalState` records are append-only. Once created they are never mutated
/// or deleted. When multiple states are active at a query time, the one with
/// the highest ``version`` is authoritative (FR-014).
public struct TemporalState: Codable, Sendable, Hashable, Identifiable {
    /// Unique state identifier.
    public let id: UUID
    /// ID of the ``Node`` or ``Edge`` this state belongs to.
    public let entityID: UUID
    /// Temporal validity interval for this state.
    public let bounds: TemporalBounds
    /// Attribute values at this point in time.
    public let attributes: [String: AttributeValue]
    /// Monotonic write-order version assigned by the store. Higher = later write.
    public let version: UInt64
    /// Timestamp when this state was recorded.
    public let createdAt: Date

    /// Creates a new `TemporalState`.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (assigned by the store).
    ///   - entityID: ID of the owning node or edge.
    ///   - bounds: Validity interval.
    ///   - attributes: Attribute values at this point in time.
    ///   - version: Monotonic version counter (assigned by the store).
    ///   - createdAt: Timestamp when this state was recorded.
    public init(
        id: UUID,
        entityID: UUID,
        bounds: TemporalBounds,
        attributes: [String: AttributeValue],
        version: UInt64,
        createdAt: Date
    ) {
        self.id = id
        self.entityID = entityID
        self.bounds = bounds
        self.attributes = attributes
        self.version = version
        self.createdAt = createdAt
    }
}
