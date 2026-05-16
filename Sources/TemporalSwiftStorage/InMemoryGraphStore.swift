import Foundation
import TemporalSwiftCore

/// An in-memory implementation of ``GraphStore`` backed by dictionary collections.
///
/// `InMemoryGraphStore` is an `actor` that guarantees data-race safety under
/// Swift 6 strict concurrency. All mutations are serialized through the actor;
/// all reads return value-type copies.
///
/// - Important: This store is intended for development, testing, and lightweight
///   agent workloads. It does not persist data across process restarts.
public actor InMemoryGraphStore: GraphStore {

    // MARK: - Internal storage

    private var nodes: [UUID: Node] = [:]
    private var edges: [UUID: Edge] = [:]
    private var states: [UUID: TemporalState] = [:]
    private var episodes: [UUID: Episode] = [:]

    /// Monotonically increasing version counter for temporal states.
    private var versionCounter: UInt64 = 0

    /// Edge types that must form a DAG (no cycles allowed).
    private var acyclicEdgeTypes: Set<String> = []

    // MARK: - Init

    /// Creates a new empty `InMemoryGraphStore`.
    public init() {}

    // MARK: - Node operations

    /// Adds a new node to the graph.
    ///
    /// - Parameters:
    ///   - type: Entity type label. Must not be empty.
    ///   - attributes: Initial attribute dictionary.
    /// - Returns: The newly created ``Node``.
    public func addNode(type: String, attributes: [String: AttributeValue]) async throws -> Node {
        let node = Node(id: UUID(), type: type, attributes: attributes, createdAt: Date())
        nodes[node.id] = node
        return node
    }

    /// Returns the node with the given ID, or `nil` if not found.
    public func node(id: UUID) async throws -> Node? {
        nodes[id]
    }

    /// Returns all nodes of the given type.
    public func nodes(ofType type: String) async throws -> [Node] {
        nodes.values.filter { $0.type == type }
    }

    // MARK: - Edge operations

    /// Adds a new directed edge between two existing nodes.
    ///
    /// - Throws: ``TemporalSwiftError/referentialIntegrityViolation(missingNodeID:)``
    ///   if source or target node does not exist.
    /// - Throws: ``TemporalSwiftError/cycleViolation(edgeType:sourceID:targetID:)``
    ///   if the edge type is constrained and would form a cycle.
    public func addEdge(
        type: String,
        sourceID: UUID,
        targetID: UUID,
        attributes: [String: AttributeValue],
        bounds: TemporalBounds
    ) async throws -> Edge {
        // Referential integrity check (FR-011)
        guard nodes[sourceID] != nil else {
            throw TemporalSwiftError.referentialIntegrityViolation(missingNodeID: sourceID)
        }
        guard nodes[targetID] != nil else {
            throw TemporalSwiftError.referentialIntegrityViolation(missingNodeID: targetID)
        }

        // Acyclicity check if constrained
        if acyclicEdgeTypes.contains(type) {
            if hasCycle(from: targetID, to: sourceID, edgeType: type) {
                throw TemporalSwiftError.cycleViolation(
                    edgeType: type,
                    sourceID: sourceID,
                    targetID: targetID
                )
            }
        }

        let edge = Edge(
            id: UUID(),
            type: type,
            sourceID: sourceID,
            targetID: targetID,
            attributes: attributes,
            createdAt: Date()
        )
        edges[edge.id] = edge

        // Store initial temporal state for the edge
        _ = try await _addState(for: edge.id, attributes: attributes, bounds: bounds)

        return edge
    }

    /// Returns all outgoing edges from the specified node.
    public func edges(from nodeID: UUID) async throws -> [Edge] {
        edges.values.filter { $0.sourceID == nodeID }
    }

    /// Returns all incoming edges to the specified node.
    public func edges(to nodeID: UUID) async throws -> [Edge] {
        edges.values.filter { $0.targetID == nodeID }
    }

    /// Returns all outgoing edges from the node with the given type.
    public func edges(from nodeID: UUID, ofType type: String) async throws -> [Edge] {
        edges.values.filter { $0.sourceID == nodeID && $0.type == type }
    }

    // MARK: - Temporal state operations

    /// Adds a new temporal state for the given entity.
    public func addState(
        for entityID: UUID,
        attributes: [String: AttributeValue],
        bounds: TemporalBounds
    ) async throws -> TemporalState {
        try await _addState(for: entityID, attributes: attributes, bounds: bounds)
    }

    /// Returns all temporal states for the given entity, ordered by version ascending.
    public func states(for entityID: UUID) async throws -> [TemporalState] {
        states.values
            .filter { $0.entityID == entityID }
            .sorted { $0.version < $1.version }
    }

    /// Returns the active state with the highest version at the given date.
    public func activeState(for entityID: UUID, at date: Date) async throws -> TemporalState? {
        try await allActiveStates(for: entityID, at: date)
            .max(by: { $0.version < $1.version })
    }

    /// Returns all states active at the given date.
    public func allActiveStates(for entityID: UUID, at date: Date) async throws -> [TemporalState] {
        states.values.filter { $0.entityID == entityID && $0.bounds.contains(date) }
    }

    // MARK: - Episode operations

    /// Creates a new episode grouping the given temporal state IDs.
    public func createEpisode(
        description: String?,
        stateIDs: [UUID],
        timestamp: Date
    ) async throws -> Episode {
        let episode = Episode(id: UUID(), description: description, stateIDs: stateIDs, timestamp: timestamp)
        episodes[episode.id] = episode
        return episode
    }

    // MARK: - Acyclicity configuration

    /// Marks the given edge type as requiring an acyclic (DAG) structure.
    public func setAcyclicConstraint(for edgeType: String) async {
        acyclicEdgeTypes.insert(edgeType)
    }

    /// Removes the acyclicity constraint for the given edge type.
    public func removeAcyclicConstraint(for edgeType: String) async {
        acyclicEdgeTypes.remove(edgeType)
    }

    // MARK: - Private helpers

    /// Internal state-add that skips async re-entry (called from addEdge).
    private func _addState(
        for entityID: UUID,
        attributes: [String: AttributeValue],
        bounds: TemporalBounds
    ) async throws -> TemporalState {
        versionCounter &+= 1
        let state = TemporalState(
            id: UUID(),
            entityID: entityID,
            bounds: bounds,
            attributes: attributes,
            version: versionCounter,
            createdAt: Date()
        )
        states[state.id] = state
        return state
    }

    /// Returns entity IDs whose states were created within the given temporal range.
    public func changedEntitiesInRange(_ range: TemporalBounds) async throws -> [UUID] {
        var seen: Set<UUID> = []
        for state in states.values {
            if range.contains(state.createdAt) {
                seen.insert(state.entityID)
            }
        }
        return Array(seen)
    }

    /// DFS reachability: can we reach `target` starting from `start` following
    /// edges of `edgeType`? Used for cycle detection before writing a new edge.
    private func hasCycle(from start: UUID, to target: UUID, edgeType: String) -> Bool {
        var visited: Set<UUID> = []
        var stack: [UUID] = [start]
        while !stack.isEmpty {
            let current = stack.removeLast()
            if current == target { return true }
            guard visited.insert(current).inserted else { continue }
            let outgoing = edges.values.filter { $0.sourceID == current && $0.type == edgeType }
            for edge in outgoing {
                stack.append(edge.targetID)
            }
        }
        return false
    }
}
