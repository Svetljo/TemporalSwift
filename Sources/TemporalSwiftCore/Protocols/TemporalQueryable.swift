import Foundation

/// Query interface for temporal reasoning over the knowledge graph.
///
/// Implementations operate on a ``GraphStore`` and provide point-in-time
/// and time-range query capabilities.
public protocol TemporalQueryable: Sendable {
    /// Returns the active temporal state for an entity at a specific point in time.
    ///
    /// When multiple states are active at `date`, the one with the highest version
    /// is returned (FR-014, last-write-wins).
    ///
    /// - Parameters:
    ///   - entityID: ID of the node or edge to query.
    ///   - date: The point in time to query at.
    /// - Returns: The active ``TemporalState``, or `nil` if none is active.
    func query(entityID: UUID, at date: Date) async throws -> TemporalState?

    /// Returns all temporal states active within a time range.
    ///
    /// - Parameters:
    ///   - entityID: ID of the node or edge to query.
    ///   - start: Start of the time range (inclusive).
    ///   - end: End of the time range (exclusive).
    /// - Returns: All ``TemporalState`` records whose bounds overlap `[start, end)`.
    func query(entityID: UUID, from start: Date, to end: Date) async throws -> [TemporalState]

    /// Returns all temporal states for an entity, ordered by version (ascending).
    ///
    /// - Parameter entityID: ID of the node or edge.
    func history(for entityID: UUID) async throws -> [TemporalState]

    /// Returns the IDs of entities whose states changed within a time range.
    ///
    /// - Parameters:
    ///   - start: Start of the time range (inclusive).
    ///   - end: End of the time range (exclusive).
    /// - Returns: UUIDs of entities with at least one state created in `[start, end)`.
    func changedEntities(from start: Date, to end: Date) async throws -> [UUID]
}
