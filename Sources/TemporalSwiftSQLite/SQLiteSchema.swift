import Foundation

// MARK: - SQLiteSchema

/// Namespace for DDL statements that create and maintain the TemporalSwift schema.
///
/// All tables use `CREATE TABLE IF NOT EXISTS` so the function is idempotent
/// and safe to call on every store open.
enum SQLiteSchema {

    // MARK: - Table + index DDL

    /// Creates all required tables and indexes.
    ///
    /// - Parameter connection: An open ``SQLiteConnection``.
    /// - Throws: ``SQLiteError`` if any DDL statement fails.
    static func createSchema(in connection: SQLiteConnection) throws {
        // Run all DDL in a single transaction for atomicity.
        try connection.beginTransaction()
        do {
            try connection.exec(createNodes)
            try connection.exec(createEdges)
            try connection.exec(createTemporalStates)
            try connection.exec(createEpisodes)
            try connection.exec(createEpisodeStateIDs)
            try connection.exec(createAcyclicEdgeTypes)
            try connection.exec(createMetadata)

            // Indexes
            try connection.exec(indexNodesType)
            try connection.exec(indexEdgesSource)
            try connection.exec(indexEdgesTarget)
            try connection.exec(indexEdgesSourceType)
            try connection.exec(indexStatesEntity)
            try connection.exec(indexStatesEntityVersion)
            try connection.exec(indexStatesCreated)

            // Seed the version counter row if absent
            try connection.exec(seedVersionCounter)

            try connection.commit()
        } catch {
            connection.rollback()
            throw error
        }
    }

    // MARK: - Table DDL

    private static let createNodes = """
        CREATE TABLE IF NOT EXISTS nodes (
            id          TEXT PRIMARY KEY NOT NULL,
            type        TEXT NOT NULL,
            attributes  TEXT NOT NULL,
            created_at  REAL NOT NULL
        );
        """

    private static let createEdges = """
        CREATE TABLE IF NOT EXISTS edges (
            id          TEXT PRIMARY KEY NOT NULL,
            type        TEXT NOT NULL,
            source_id   TEXT NOT NULL,
            target_id   TEXT NOT NULL,
            attributes  TEXT NOT NULL,
            created_at  REAL NOT NULL
        );
        """

    private static let createTemporalStates = """
        CREATE TABLE IF NOT EXISTS temporal_states (
            id          TEXT PRIMARY KEY NOT NULL,
            entity_id   TEXT NOT NULL,
            valid_from  REAL NOT NULL,
            valid_until REAL,
            attributes  TEXT NOT NULL,
            version     INTEGER NOT NULL,
            created_at  REAL NOT NULL
        );
        """

    private static let createEpisodes = """
        CREATE TABLE IF NOT EXISTS episodes (
            id          TEXT PRIMARY KEY NOT NULL,
            description TEXT,
            timestamp   REAL NOT NULL
        );
        """

    private static let createEpisodeStateIDs = """
        CREATE TABLE IF NOT EXISTS episode_state_ids (
            episode_id  TEXT NOT NULL,
            state_id    TEXT NOT NULL,
            PRIMARY KEY (episode_id, state_id)
        );
        """

    private static let createAcyclicEdgeTypes = """
        CREATE TABLE IF NOT EXISTS acyclic_edge_types (
            edge_type   TEXT PRIMARY KEY NOT NULL
        );
        """

    private static let createMetadata = """
        CREATE TABLE IF NOT EXISTS metadata (
            key         TEXT PRIMARY KEY NOT NULL,
            value       INTEGER NOT NULL
        );
        """

    // MARK: - Index DDL

    private static let indexNodesType =
        "CREATE INDEX IF NOT EXISTS idx_nodes_type ON nodes(type);"

    private static let indexEdgesSource =
        "CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id);"

    private static let indexEdgesTarget =
        "CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id);"

    private static let indexEdgesSourceType =
        "CREATE INDEX IF NOT EXISTS idx_edges_source_type ON edges(source_id, type);"

    private static let indexStatesEntity =
        "CREATE INDEX IF NOT EXISTS idx_states_entity ON temporal_states(entity_id);"

    private static let indexStatesEntityVersion =
        "CREATE INDEX IF NOT EXISTS idx_states_entity_version ON temporal_states(entity_id, version);"

    private static let indexStatesCreated =
        "CREATE INDEX IF NOT EXISTS idx_states_created ON temporal_states(created_at);"

    // MARK: - Seed

    /// Inserts the version_counter row if it does not already exist.
    private static let seedVersionCounter = """
        INSERT OR IGNORE INTO metadata (key, value) VALUES ('version_counter', 0);
        """
}
