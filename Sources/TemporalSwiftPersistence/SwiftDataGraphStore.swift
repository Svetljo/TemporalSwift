import Foundation
import SwiftData
import TemporalSwiftCore

/// A persistent ``GraphStore`` implementation backed by SwiftData.
///
/// `SwiftDataGraphStore` stores all graph entities (nodes, edges, temporal states,
/// episodes, and acyclic constraints) in a SQLite database at a configurable
/// file URL. Data survives process restarts and is immediately available when
/// a new instance is created pointing at the same URL.
///
/// All mutations are actor-isolated and followed by an explicit save, ensuring
/// durability without requiring a manual save call from consumers.
///
/// ## Usage
///
/// ```swift
/// let store = try SwiftDataGraphStore(url: myFileURL)
/// let node = try await store.addNode(type: "Person", attributes: ["name": .string("Ada")])
/// ```
///
/// ## Platform availability
///
/// Available on macOS 14+, iOS 17+, tvOS 17+, and watchOS 10+. Not available on Linux.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
public final actor SwiftDataGraphStore: GraphStore {

    // MARK: - Private storage

    private let modelContext: ModelContext
    private var config: PersistedStoreConfig

    // MARK: - Initialisation

    /// Creates a persistent store at the given file URL.
    ///
    /// If the file does not exist, it will be created. If it already exists,
    /// all previously stored data is loaded automatically.
    ///
    /// - Parameter url: File URL for the SQLite database.
    /// - Throws: If the `ModelContainer` cannot be created or the config cannot be loaded.
    public init(url: URL) throws {
        let schema = Schema([
            PersistedNode.self,
            PersistedEdge.self,
            PersistedTemporalState.self,
            PersistedEpisode.self,
            PersistedStoreConfig.self,
        ])
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        self.modelContext = ModelContext(container)
        self.modelContext.autosaveEnabled = false
        self.config = try SwiftDataGraphStore.loadOrCreateConfig(in: self.modelContext)
    }

    /// Creates an in-memory store. Data does not survive process exit.
    ///
    /// Useful for testing and ephemeral workloads.
    ///
    /// - Throws: If the `ModelContainer` cannot be created.
    public init(inMemory: Bool = true) throws {
        let schema = Schema([
            PersistedNode.self,
            PersistedEdge.self,
            PersistedTemporalState.self,
            PersistedEpisode.self,
            PersistedStoreConfig.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        self.modelContext = ModelContext(container)
        self.modelContext.autosaveEnabled = false
        self.config = try SwiftDataGraphStore.loadOrCreateConfig(in: self.modelContext)
    }

    // MARK: - Node operations

    /// Adds a new node to the graph.
    ///
    /// - Parameters:
    ///   - type: Entity type label. Must not be empty.
    ///   - attributes: Initial attribute dictionary.
    /// - Returns: The newly created ``Node``.
    public func addNode(type: String, attributes: [String: AttributeValue]) async throws -> Node {
        let node = Node(id: UUID(), type: type, attributes: attributes, createdAt: Date())
        let persisted = try PersistedNode.from(node)
        modelContext.insert(persisted)
        try modelContext.save()
        return node
    }

    /// Returns the node with the given ID, or `nil` if not found.
    public func node(id: UUID) async throws -> Node? {
        let descriptor = FetchDescriptor<PersistedNode>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first.map { try $0.toNode() }
    }

    /// Returns all nodes of the given type.
    public func nodes(ofType type: String) async throws -> [Node] {
        let descriptor = FetchDescriptor<PersistedNode>(
            predicate: #Predicate { $0.type == type }
        )
        return try modelContext.fetch(descriptor).map { try $0.toNode() }
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
        // Referential integrity
        guard try await node(id: sourceID) != nil else {
            throw TemporalSwiftError.referentialIntegrityViolation(missingNodeID: sourceID)
        }
        guard try await node(id: targetID) != nil else {
            throw TemporalSwiftError.referentialIntegrityViolation(missingNodeID: targetID)
        }

        // Acyclicity check
        let acyclicTypes = try config.acyclicEdgeTypes()
        if acyclicTypes.contains(type) {
            if try hasCycle(from: targetID, to: sourceID, edgeType: type) {
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
        let persisted = try PersistedEdge.from(edge)
        modelContext.insert(persisted)

        // Store initial temporal state for the edge
        _ = try internalAddState(for: edge.id, attributes: attributes, bounds: bounds)

        try modelContext.save()
        return edge
    }

    /// Returns all outgoing edges from the specified node.
    public func edges(from nodeID: UUID) async throws -> [Edge] {
        let descriptor = FetchDescriptor<PersistedEdge>(
            predicate: #Predicate { $0.sourceID == nodeID }
        )
        return try modelContext.fetch(descriptor).map { try $0.toEdge() }
    }

    /// Returns all incoming edges to the specified node.
    public func edges(to nodeID: UUID) async throws -> [Edge] {
        let descriptor = FetchDescriptor<PersistedEdge>(
            predicate: #Predicate { $0.targetID == nodeID }
        )
        return try modelContext.fetch(descriptor).map { try $0.toEdge() }
    }

    /// Returns all outgoing edges from the node with the given type.
    public func edges(from nodeID: UUID, ofType type: String) async throws -> [Edge] {
        let descriptor = FetchDescriptor<PersistedEdge>(
            predicate: #Predicate { $0.sourceID == nodeID && $0.type == type }
        )
        return try modelContext.fetch(descriptor).map { try $0.toEdge() }
    }

    // MARK: - Temporal state operations

    /// Adds a new temporal state for the given entity.
    ///
    /// States are append-only. Each call creates a new record with a
    /// monotonically increasing version number that persists across restarts.
    public func addState(
        for entityID: UUID,
        attributes: [String: AttributeValue],
        bounds: TemporalBounds
    ) async throws -> TemporalState {
        let state = try internalAddState(for: entityID, attributes: attributes, bounds: bounds)
        try modelContext.save()
        return state
    }

    /// Returns all temporal states for the given entity, ordered by version ascending.
    public func states(for entityID: UUID) async throws -> [TemporalState] {
        var descriptor = FetchDescriptor<PersistedTemporalState>(
            predicate: #Predicate { $0.entityID == entityID },
            sortBy: [SortDescriptor(\.version)]
        )
        descriptor.sortBy = [SortDescriptor(\.version)]
        return try modelContext.fetch(descriptor).map { try $0.toTemporalState() }
    }

    /// Returns the active state with the highest version at the given date.
    public func activeState(for entityID: UUID, at date: Date) async throws -> TemporalState? {
        try await allActiveStates(for: entityID, at: date)
            .max(by: { $0.version < $1.version })
    }

    /// Returns all states active at the given date.
    public func allActiveStates(for entityID: UUID, at date: Date) async throws -> [TemporalState] {
        let descriptor = FetchDescriptor<PersistedTemporalState>(
            predicate: #Predicate { $0.entityID == entityID }
        )
        let all = try modelContext.fetch(descriptor)
        return try all
            .filter { $0.isActive(at: date) }
            .map { try $0.toTemporalState() }
    }

    // MARK: - Episode operations

    /// Creates a new episode grouping the given temporal state IDs.
    public func createEpisode(
        description: String?,
        stateIDs: [UUID],
        timestamp: Date
    ) async throws -> Episode {
        let episode = Episode(id: UUID(), description: description, stateIDs: stateIDs, timestamp: timestamp)
        let persisted = try PersistedEpisode.from(episode)
        modelContext.insert(persisted)
        try modelContext.save()
        return episode
    }

    // MARK: - Acyclicity configuration

    /// Marks the given edge type as requiring an acyclic (DAG) structure.
    public func setAcyclicConstraint(for edgeType: String) async {
        // Ignore errors — best-effort persistence; types is Set<String> so duplicate-safe
        var types = (try? config.acyclicEdgeTypes()) ?? Set<String>()
        types.insert(edgeType)
        try? config.setAcyclicEdgeTypes(types)
        try? modelContext.save()
    }

    /// Removes the acyclicity constraint for the given edge type.
    public func removeAcyclicConstraint(for edgeType: String) async {
        var types = (try? config.acyclicEdgeTypes()) ?? Set<String>()
        types.remove(edgeType)
        try? config.setAcyclicEdgeTypes(types)
        try? modelContext.save()
    }

    // MARK: - Cross-cutting queries

    /// Returns the IDs of entities whose temporal states were created within the given bounds.
    public func changedEntitiesInRange(_ range: TemporalBounds) async throws -> [UUID] {
        let from = range.validFrom
        let descriptor: FetchDescriptor<PersistedTemporalState>
        if let until = range.validUntil {
            descriptor = FetchDescriptor<PersistedTemporalState>(
                predicate: #Predicate { $0.createdAt >= from && $0.createdAt < until }
            )
        } else {
            descriptor = FetchDescriptor<PersistedTemporalState>(
                predicate: #Predicate { $0.createdAt >= from }
            )
        }
        let states = try modelContext.fetch(descriptor)
        let ids = Set(states.map { $0.entityID })
        return Array(ids)
    }

    // MARK: - Private helpers

    /// Increments the version counter and inserts a new `PersistedTemporalState`.
    ///
    /// Does **not** call `save()` — callers are responsible for saving.
    private func internalAddState(
        for entityID: UUID,
        attributes: [String: AttributeValue],
        bounds: TemporalBounds
    ) throws -> TemporalState {
        config.versionCounter &+= 1
        let state = TemporalState(
            id: UUID(),
            entityID: entityID,
            bounds: bounds,
            attributes: attributes,
            version: config.versionCounter,
            createdAt: Date()
        )
        let persisted = try PersistedTemporalState.from(state)
        modelContext.insert(persisted)
        return state
    }

    /// DFS reachability check: can we reach `target` from `start` via edges of `edgeType`?
    private func hasCycle(from start: UUID, to target: UUID, edgeType: String) throws -> Bool {
        var visited: Set<UUID> = []
        var stack: [UUID] = [start]
        while !stack.isEmpty {
            let current = stack.removeLast()
            if current == target { return true }
            guard visited.insert(current).inserted else { continue }
            let descriptor = FetchDescriptor<PersistedEdge>(
                predicate: #Predicate { $0.sourceID == current && $0.type == edgeType }
            )
            let outgoing = try modelContext.fetch(descriptor)
            for edge in outgoing {
                stack.append(edge.targetID)
            }
        }
        return false
    }

    // MARK: - Static setup helpers

    private static func loadOrCreateConfig(in context: ModelContext) throws -> PersistedStoreConfig {
        let descriptor = FetchDescriptor<PersistedStoreConfig>()
        let existing = try context.fetch(descriptor)
        if let config = existing.first {
            return config
        }
        let config = try PersistedStoreConfig.makeDefault()
        context.insert(config)
        try context.save()
        return config
    }
}
