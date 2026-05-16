import Foundation

/// The primary storage abstraction for the temporal knowledge graph.
///
/// All implementations must be `Sendable`. The default implementation is
/// ``InMemoryGraphStore``, an `actor` that provides thread-safe in-memory storage.
///
/// Dependency direction: `TemporalSwiftStorage` → `TemporalSwiftCore`.
public protocol GraphStore: Sendable {
    // MARK: - Node operations

    /// Adds a new node to the graph.
    ///
    /// - Parameters:
    ///   - type: Entity type label. Must not be empty.
    ///   - attributes: Initial attribute dictionary.
    /// - Returns: The newly created ``Node``.
    func addNode(type: String, attributes: [String: AttributeValue]) async throws -> Node

    /// Returns the node with the given ID, or `nil` if not found.
    ///
    /// - Parameter id: The node's UUID.
    func node(id: UUID) async throws -> Node?

    /// Returns all nodes of the given type.
    ///
    /// - Parameter type: Entity type label to filter by.
    func nodes(ofType type: String) async throws -> [Node]

    // MARK: - Edge operations

    /// Adds a new directed edge between two existing nodes.
    ///
    /// - Parameters:
    ///   - type: Relationship type label. Must not be empty.
    ///   - sourceID: ID of the source node (must exist).
    ///   - targetID: ID of the target node (must exist).
    ///   - attributes: Initial attribute dictionary.
    ///   - bounds: Temporal validity interval for this edge.
    /// - Throws: ``TemporalSwiftError/referentialIntegrityViolation(missingNodeID:)`` if either node is missing.
    /// - Throws: ``TemporalSwiftError/cycleViolation(edgeType:sourceID:targetID:)`` if the edge type is constrained and adding it would create a cycle.
    func addEdge(
        type: String,
        sourceID: UUID,
        targetID: UUID,
        attributes: [String: AttributeValue],
        bounds: TemporalBounds
    ) async throws -> Edge

    /// Returns all outgoing edges from the specified node.
    func edges(from nodeID: UUID) async throws -> [Edge]

    /// Returns all incoming edges to the specified node.
    func edges(to nodeID: UUID) async throws -> [Edge]

    /// Returns all outgoing edges from the specified node with the given type.
    func edges(from nodeID: UUID, ofType type: String) async throws -> [Edge]

    // MARK: - Temporal state operations

    /// Adds a new temporal state for the given entity.
    ///
    /// States are append-only. Each call creates a new record with a
    /// monotonically increasing version number.
    ///
    /// - Parameters:
    ///   - entityID: ID of the node or edge this state belongs to.
    ///   - attributes: Attribute values at this point in time.
    ///   - bounds: Temporal validity interval.
    func addState(
        for entityID: UUID,
        attributes: [String: AttributeValue],
        bounds: TemporalBounds
    ) async throws -> TemporalState

    /// Returns all temporal states for the given entity, ordered by version (ascending).
    func states(for entityID: UUID) async throws -> [TemporalState]

    /// Returns the active state for the given entity at the specified date.
    ///
    /// When multiple states are active, the one with the highest version is returned (FR-014).
    func activeState(for entityID: UUID, at date: Date) async throws -> TemporalState?

    /// Returns all temporal states that are active at the specified date.
    func allActiveStates(for entityID: UUID, at date: Date) async throws -> [TemporalState]

    // MARK: - Episode operations

    /// Creates a new episode grouping the given temporal state IDs.
    ///
    /// - Parameters:
    ///   - description: Optional human-readable description.
    ///   - stateIDs: IDs of the ``TemporalState`` records in this episode.
    ///   - timestamp: When this episode occurred.
    func createEpisode(
        description: String?,
        stateIDs: [UUID],
        timestamp: Date
    ) async throws -> Episode

    // MARK: - Acyclicity configuration

    /// Marks the given edge type as requiring an acyclic (DAG) structure.
    ///
    /// When an edge of this type is added, a DFS check is performed.
    /// Cycle-forming writes are rejected with ``TemporalSwiftError/cycleViolation(edgeType:sourceID:targetID:)``.
    func setAcyclicConstraint(for edgeType: String) async

    /// Removes the acyclicity constraint for the given edge type.
    func removeAcyclicConstraint(for edgeType: String) async

    // MARK: - Cross-cutting queries

    /// Returns the IDs of entities whose temporal states were created within the given bounds.
    ///
    /// Used by ``TemporalQueryEngine`` to implement ``TemporalQueryable/changedEntities(from:to:)``.
    ///
    /// - Parameter range: Temporal bounds representing the query window.
    /// - Returns: UUIDs of entities with at least one state whose `createdAt` falls in `[range.validFrom, range.validUntil)`.
    func changedEntitiesInRange(_ range: TemporalBounds) async throws -> [UUID]
}
