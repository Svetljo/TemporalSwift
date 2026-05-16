import Foundation
import TemporalSwiftCore

/// Provides temporal reasoning queries over a ``GraphStore``.
///
/// `TemporalQueryEngine` implements ``TemporalQueryable`` using the underlying
/// store's state collections. It is a value type (`struct`) — create one per
/// query scope or reuse across queries against the same store.
public struct TemporalQueryEngine: TemporalQueryable {

    private let store: any GraphStore

    /// Creates a new `TemporalQueryEngine` backed by the given store.
    ///
    /// - Parameter store: The ``GraphStore`` to query.
    public init(store: any GraphStore) {
        self.store = store
    }

    // MARK: - TemporalQueryable

    /// Returns the active temporal state for an entity at a specific point in time.
    ///
    /// When multiple states are active, the one with the highest version wins (FR-014).
    public func query(entityID: UUID, at date: Date) async throws -> TemporalState? {
        try await store.activeState(for: entityID, at: date)
    }

    /// Returns all temporal states active within a time range `[start, end)`.
    public func query(entityID: UUID, from start: Date, to end: Date) async throws -> [TemporalState] {
        let all = try await store.states(for: entityID)
        let range = TemporalBounds(validFrom: start, validUntil: end)
        return all.filter { $0.bounds.overlaps(range) }
    }

    /// Returns all temporal states for an entity ordered by version ascending.
    public func history(for entityID: UUID) async throws -> [TemporalState] {
        try await store.states(for: entityID)
    }

    /// Returns the IDs of entities whose states were created within `[start, end)`.
    public func changedEntities(from start: Date, to end: Date) async throws -> [UUID] {
        let range = TemporalBounds(validFrom: start, validUntil: end)
        return try await store.changedEntitiesInRange(range)
    }
}
