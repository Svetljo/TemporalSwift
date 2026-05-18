import Foundation
import TemporalSwiftCore

// MARK: - JSON helpers (internal to this module)

private let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .secondsSince1970
    return e
}()

private let jsonDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .secondsSince1970
    return d
}()

private func encodeAttributes(_ attrs: [String: AttributeValue]) throws -> String {
    let data = try jsonEncoder.encode(attrs)
    return String(data: data, encoding: .utf8) ?? "{}"
}

private func decodeAttributes(_ json: String) throws -> [String: AttributeValue] {
    guard let data = json.data(using: .utf8) else { return [:] }
    return try jsonDecoder.decode([String: AttributeValue].self, from: data)
}

// MARK: - SQLiteGraphStore

/// A persistent ``GraphStore`` implementation backed by a SQLite database.
///
/// `SQLiteGraphStore` is an `actor` that guarantees data-race safety under
/// Swift 6 strict concurrency. All mutations are serialized through the actor
/// and written to a SQLite file, surviving process restarts.
///
/// ## Usage
///
/// ```swift
/// // Persistent store
/// let store = try SQLiteGraphStore(path: "/path/to/graph.db")
///
/// // In-memory store for testing
/// let store = try SQLiteGraphStore(path: ":memory:")
/// ```
public actor SQLiteGraphStore: GraphStore {

    // MARK: - State

    /// The open database connection. Owned exclusively by this actor.
    private let conn: SQLiteConnection

    /// In-memory cache of the current version counter. Written through to the database on each state insert.
    private var versionCounter: UInt64 = 0

    /// In-memory set of edge types that require DAG structure.
    private var acyclicEdgeTypes: Set<String> = []

    // MARK: - Init

    /// Opens or creates a SQLite database at `path`.
    ///
    /// If the database is new, the schema is created automatically. If it
    /// already exists, the existing data and version counter are loaded.
    ///
    /// - Parameter path: File system path to the SQLite file. Use `":memory:"`
    ///   for an in-memory database (useful in tests).
    /// - Throws: If the database cannot be opened or the schema cannot be created.
    public init(path: String) throws {
        conn = try SQLiteConnection(path: path)
        try SQLiteSchema.createSchema(in: conn)
        versionCounter = try SQLiteGraphStore.loadVersionCounter(conn: conn)
        acyclicEdgeTypes = try SQLiteGraphStore.loadAcyclicEdgeTypes(conn: conn)
    }

    // MARK: - Node operations

    /// Adds a new node to the graph and persists it to SQLite.
    public func addNode(type: String, attributes: [String: AttributeValue]) async throws -> Node {
        let node = Node(id: UUID(), type: type, attributes: attributes, createdAt: Date())
        let attrsJSON = try encodeAttributes(attributes)
        let stmt = try conn.prepare("""
            INSERT INTO nodes (id, type, attributes, created_at)
            VALUES (?, ?, ?, ?);
            """)
        try stmt.bindText(node.id.uuidString.lowercased(), at: 1)
        try stmt.bindText(type, at: 2)
        try stmt.bindText(attrsJSON, at: 3)
        try stmt.bindDouble(node.createdAt.timeIntervalSince1970, at: 4)
        try stmt.step()
        return node
    }

    /// Returns the node with the given ID, or `nil` if not found.
    public func node(id: UUID) async throws -> Node? {
        let stmt = try conn.prepare("SELECT id, type, attributes, created_at FROM nodes WHERE id = ?;")
        try stmt.bindText(id.uuidString.lowercased(), at: 1)
        guard try stmt.step() else { return nil }
        return try nodeFromStatement(stmt)
    }

    /// Returns all nodes of the given type.
    public func nodes(ofType type: String) async throws -> [Node] {
        let stmt = try conn.prepare("SELECT id, type, attributes, created_at FROM nodes WHERE type = ?;")
        try stmt.bindText(type, at: 1)
        var result: [Node] = []
        while try stmt.step() {
            result.append(try nodeFromStatement(stmt))
        }
        return result
    }

    // MARK: - Edge operations

    /// Adds a new directed edge and persists it to SQLite.
    public func addEdge(
        type: String,
        sourceID: UUID,
        targetID: UUID,
        attributes: [String: AttributeValue],
        bounds: TemporalBounds
    ) async throws -> Edge {
        // Referential integrity check
        guard (try await node(id: sourceID)) != nil else {
            throw TemporalSwiftError.referentialIntegrityViolation(missingNodeID: sourceID)
        }
        guard (try await node(id: targetID)) != nil else {
            throw TemporalSwiftError.referentialIntegrityViolation(missingNodeID: targetID)
        }

        // Cycle detection for constrained edge types
        if acyclicEdgeTypes.contains(type) {
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

        let attrsJSON = try encodeAttributes(attributes)
        try conn.beginTransaction()
        do {
            let stmt = try conn.prepare("""
                INSERT INTO edges (id, type, source_id, target_id, attributes, created_at)
                VALUES (?, ?, ?, ?, ?, ?);
                """)
            try stmt.bindText(edge.id.uuidString.lowercased(), at: 1)
            try stmt.bindText(type, at: 2)
            try stmt.bindText(sourceID.uuidString.lowercased(), at: 3)
            try stmt.bindText(targetID.uuidString.lowercased(), at: 4)
            try stmt.bindText(attrsJSON, at: 5)
            try stmt.bindDouble(edge.createdAt.timeIntervalSince1970, at: 6)
            try stmt.step()

            // Store initial temporal state for the edge
            _ = try insertState(for: edge.id, attributes: attributes, bounds: bounds)

            try conn.commit()
        } catch {
            conn.rollback()
            throw error
        }
        return edge
    }

    /// Returns all outgoing edges from the specified node.
    public func edges(from nodeID: UUID) async throws -> [Edge] {
        let stmt = try conn.prepare("""
            SELECT id, type, source_id, target_id, attributes, created_at
            FROM edges WHERE source_id = ?;
            """)
        try stmt.bindText(nodeID.uuidString.lowercased(), at: 1)
        return try edgesFromStatement(stmt)
    }

    /// Returns all incoming edges to the specified node.
    public func edges(to nodeID: UUID) async throws -> [Edge] {
        let stmt = try conn.prepare("""
            SELECT id, type, source_id, target_id, attributes, created_at
            FROM edges WHERE target_id = ?;
            """)
        try stmt.bindText(nodeID.uuidString.lowercased(), at: 1)
        return try edgesFromStatement(stmt)
    }

    /// Returns all outgoing edges from the node with the given type.
    public func edges(from nodeID: UUID, ofType type: String) async throws -> [Edge] {
        let stmt = try conn.prepare("""
            SELECT id, type, source_id, target_id, attributes, created_at
            FROM edges WHERE source_id = ? AND type = ?;
            """)
        try stmt.bindText(nodeID.uuidString.lowercased(), at: 1)
        try stmt.bindText(type, at: 2)
        return try edgesFromStatement(stmt)
    }

    // MARK: - Temporal state operations

    /// Adds a new temporal state and persists it to SQLite.
    public func addState(
        for entityID: UUID,
        attributes: [String: AttributeValue],
        bounds: TemporalBounds
    ) async throws -> TemporalState {
        try conn.beginTransaction()
        do {
            let state = try insertState(for: entityID, attributes: attributes, bounds: bounds)
            try conn.commit()
            return state
        } catch {
            conn.rollback()
            throw error
        }
    }

    /// Returns all temporal states for the given entity, ordered by version ascending.
    public func states(for entityID: UUID) async throws -> [TemporalState] {
        let stmt = try conn.prepare("""
            SELECT id, entity_id, valid_from, valid_until, attributes, version, created_at
            FROM temporal_states
            WHERE entity_id = ?
            ORDER BY version ASC;
            """)
        try stmt.bindText(entityID.uuidString.lowercased(), at: 1)
        return try temporalStatesFromStatement(stmt)
    }

    /// Returns the active state with the highest version at the given date.
    public func activeState(for entityID: UUID, at date: Date) async throws -> TemporalState? {
        try await allActiveStates(for: entityID, at: date)
            .max(by: { $0.version < $1.version })
    }

    /// Returns all states active at the given date.
    public func allActiveStates(for entityID: UUID, at date: Date) async throws -> [TemporalState] {
        let ts = date.timeIntervalSince1970
        // active = valid_from <= date AND (valid_until IS NULL OR valid_until > date)
        let stmt = try conn.prepare("""
            SELECT id, entity_id, valid_from, valid_until, attributes, version, created_at
            FROM temporal_states
            WHERE entity_id = ?
              AND valid_from <= ?
              AND (valid_until IS NULL OR valid_until > ?);
            """)
        try stmt.bindText(entityID.uuidString.lowercased(), at: 1)
        try stmt.bindDouble(ts, at: 2)
        try stmt.bindDouble(ts, at: 3)
        return try temporalStatesFromStatement(stmt)
    }

    // MARK: - Episode operations

    /// Creates a new episode and persists it to SQLite.
    public func createEpisode(
        description: String?,
        stateIDs: [UUID],
        timestamp: Date
    ) async throws -> Episode {
        let episode = Episode(id: UUID(), description: description, stateIDs: stateIDs, timestamp: timestamp)

        try conn.beginTransaction()
        do {
            let stmt = try conn.prepare("""
                INSERT INTO episodes (id, description, timestamp)
                VALUES (?, ?, ?);
                """)
            try stmt.bindText(episode.id.uuidString.lowercased(), at: 1)
            try stmt.bindOptionalText(description, at: 2)
            try stmt.bindDouble(timestamp.timeIntervalSince1970, at: 3)
            try stmt.step()

            let junctionStmt = try conn.prepare("""
                INSERT INTO episode_state_ids (episode_id, state_id) VALUES (?, ?);
                """)
            for stateID in stateIDs {
                junctionStmt.reset()
                try junctionStmt.bindText(episode.id.uuidString.lowercased(), at: 1)
                try junctionStmt.bindText(stateID.uuidString.lowercased(), at: 2)
                try junctionStmt.step()
            }

            try conn.commit()
        } catch {
            conn.rollback()
            throw error
        }
        return episode
    }

    /// Returns the episode with the given ID, or `nil` if not found.
    ///
    /// This method is not part of the `GraphStore` protocol but is used by
    /// persistence tests to verify episodes survive restarts.
    public func episode(id: UUID) async throws -> Episode? {
        let stmt = try conn.prepare("SELECT id, description, timestamp FROM episodes WHERE id = ?;")
        try stmt.bindText(id.uuidString.lowercased(), at: 1)
        guard try stmt.step() else { return nil }

        let episodeID = UUID(uuidString: stmt.columnText(0)) ?? id
        let desc = stmt.columnOptionalText(1)
        let ts = Date(timeIntervalSince1970: stmt.columnDouble(2))

        // Load state IDs from junction table
        let jStmt = try conn.prepare("""
            SELECT state_id FROM episode_state_ids WHERE episode_id = ?;
            """)
        try jStmt.bindText(episodeID.uuidString.lowercased(), at: 1)
        var stateIDs: [UUID] = []
        while try jStmt.step() {
            if let sid = UUID(uuidString: jStmt.columnText(0)) {
                stateIDs.append(sid)
            }
        }

        return Episode(id: episodeID, description: desc, stateIDs: stateIDs, timestamp: ts)
    }

    // MARK: - Acyclicity configuration

    /// Marks the given edge type as requiring an acyclic (DAG) structure.
    public func setAcyclicConstraint(for edgeType: String) async {
        acyclicEdgeTypes.insert(edgeType)
        try? conn.exec("INSERT OR IGNORE INTO acyclic_edge_types (edge_type) VALUES ('\(edgeType)');")
    }

    /// Removes the acyclicity constraint for the given edge type.
    public func removeAcyclicConstraint(for edgeType: String) async {
        acyclicEdgeTypes.remove(edgeType)
        try? conn.exec("DELETE FROM acyclic_edge_types WHERE edge_type = '\(edgeType)';")
    }

    // MARK: - Cross-cutting queries

    /// Returns entity IDs whose states were created within the given temporal range.
    public func changedEntitiesInRange(_ range: TemporalBounds) async throws -> [UUID] {
        let from = range.validFrom.timeIntervalSince1970
        let sql: String
        let stmt: SQLiteStatement

        if let until = range.validUntil {
            sql = """
                SELECT DISTINCT entity_id FROM temporal_states
                WHERE created_at >= ? AND created_at < ?;
                """
            stmt = try conn.prepare(sql)
            try stmt.bindDouble(from, at: 1)
            try stmt.bindDouble(until.timeIntervalSince1970, at: 2)
        } else {
            sql = "SELECT DISTINCT entity_id FROM temporal_states WHERE created_at >= ?;"
            stmt = try conn.prepare(sql)
            try stmt.bindDouble(from, at: 1)
        }

        var result: [UUID] = []
        while try stmt.step() {
            if let id = UUID(uuidString: stmt.columnText(0)) {
                result.append(id)
            }
        }
        return result
    }

    // MARK: - Private: state insertion (shared by addState and addEdge)

    /// Inserts a new `TemporalState` row, incrementing and persisting the version counter.
    ///
    /// Must be called within an open transaction.
    private func insertState(
        for entityID: UUID,
        attributes: [String: AttributeValue],
        bounds: TemporalBounds
    ) throws -> TemporalState {
        versionCounter &+= 1
        let newVersion = versionCounter

        let attrsJSON = try encodeAttributes(attributes)
        let stateID = UUID()
        let createdAt = Date()

        let stmt = try conn.prepare("""
            INSERT INTO temporal_states
                (id, entity_id, valid_from, valid_until, attributes, version, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """)
        try stmt.bindText(stateID.uuidString.lowercased(), at: 1)
        try stmt.bindText(entityID.uuidString.lowercased(), at: 2)
        try stmt.bindDouble(bounds.validFrom.timeIntervalSince1970, at: 3)
        try stmt.bindOptionalDouble(bounds.validUntil?.timeIntervalSince1970, at: 4)
        try stmt.bindText(attrsJSON, at: 5)
        try stmt.bindInt64(Int64(newVersion), at: 6)
        try stmt.bindDouble(createdAt.timeIntervalSince1970, at: 7)
        try stmt.step()

        // Persist updated version counter
        let updateStmt = try conn.prepare("""
            UPDATE metadata SET value = ? WHERE key = 'version_counter';
            """)
        try updateStmt.bindInt64(Int64(newVersion), at: 1)
        try updateStmt.step()

        return TemporalState(
            id: stateID,
            entityID: entityID,
            bounds: bounds,
            attributes: attributes,
            version: newVersion,
            createdAt: createdAt
        )
    }

    // MARK: - Private: cycle detection

    /// DFS reachability check over `edges` table: can we reach `target` from `start`
    /// following edges of `edgeType`? Used to detect cycles before inserting a new edge.
    private func hasCycle(from start: UUID, to target: UUID, edgeType: String) throws -> Bool {
        var visited: Set<UUID> = []
        var stack: [UUID] = [start]
        while !stack.isEmpty {
            let current = stack.removeLast()
            if current == target { return true }
            guard visited.insert(current).inserted else { continue }

            let stmt = try conn.prepare("""
                SELECT target_id FROM edges WHERE source_id = ? AND type = ?;
                """)
            try stmt.bindText(current.uuidString.lowercased(), at: 1)
            try stmt.bindText(edgeType, at: 2)
            while try stmt.step() {
                if let nextID = UUID(uuidString: stmt.columnText(0)) {
                    stack.append(nextID)
                }
            }
        }
        return false
    }

    // MARK: - Private: startup loaders

    private static func loadVersionCounter(conn: SQLiteConnection) throws -> UInt64 {
        let stmt = try conn.prepare("SELECT value FROM metadata WHERE key = 'version_counter';")
        guard try stmt.step() else { return 0 }
        return UInt64(stmt.columnInt64(0))
    }

    private static func loadAcyclicEdgeTypes(conn: SQLiteConnection) throws -> Set<String> {
        let stmt = try conn.prepare("SELECT edge_type FROM acyclic_edge_types;")
        var result: Set<String> = []
        while try stmt.step() {
            result.insert(stmt.columnText(0))
        }
        return result
    }

    // MARK: - Private: row deserializers

    private func nodeFromStatement(_ stmt: SQLiteStatement) throws -> Node {
        let idStr = stmt.columnText(0)
        let type = stmt.columnText(1)
        let attrsJSON = stmt.columnText(2)
        let createdAt = Date(timeIntervalSince1970: stmt.columnDouble(3))
        let attrs = try decodeAttributes(attrsJSON)
        let id = UUID(uuidString: idStr) ?? UUID()
        return Node(id: id, type: type, attributes: attrs, createdAt: createdAt)
    }

    private func edgesFromStatement(_ stmt: SQLiteStatement) throws -> [Edge] {
        var result: [Edge] = []
        while try stmt.step() {
            result.append(try edgeFromStatement(stmt))
        }
        return result
    }

    private func edgeFromStatement(_ stmt: SQLiteStatement) throws -> Edge {
        let id = UUID(uuidString: stmt.columnText(0)) ?? UUID()
        let type = stmt.columnText(1)
        let sourceID = UUID(uuidString: stmt.columnText(2)) ?? UUID()
        let targetID = UUID(uuidString: stmt.columnText(3)) ?? UUID()
        let attrs = try decodeAttributes(stmt.columnText(4))
        let createdAt = Date(timeIntervalSince1970: stmt.columnDouble(5))
        return Edge(id: id, type: type, sourceID: sourceID, targetID: targetID, attributes: attrs, createdAt: createdAt)
    }

    private func temporalStatesFromStatement(_ stmt: SQLiteStatement) throws -> [TemporalState] {
        var result: [TemporalState] = []
        while try stmt.step() {
            result.append(try temporalStateFromStatement(stmt))
        }
        return result
    }

    private func temporalStateFromStatement(_ stmt: SQLiteStatement) throws -> TemporalState {
        let id = UUID(uuidString: stmt.columnText(0)) ?? UUID()
        let entityID = UUID(uuidString: stmt.columnText(1)) ?? UUID()
        let validFrom = Date(timeIntervalSince1970: stmt.columnDouble(2))
        let validUntil: Date? = stmt.columnIsNull(3) ? nil : Date(timeIntervalSince1970: stmt.columnDouble(3))
        let attrs = try decodeAttributes(stmt.columnText(4))
        let version = UInt64(stmt.columnInt64(5))
        let createdAt = Date(timeIntervalSince1970: stmt.columnDouble(6))
        return TemporalState(
            id: id,
            entityID: entityID,
            bounds: TemporalBounds(validFrom: validFrom, validUntil: validUntil),
            attributes: attrs,
            version: version,
            createdAt: createdAt
        )
    }
}
