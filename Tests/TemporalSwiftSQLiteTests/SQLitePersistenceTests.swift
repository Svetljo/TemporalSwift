import Testing
import Foundation
@testable import TemporalSwiftCore
@testable import TemporalSwiftSQLite

// MARK: - Helper

/// Returns a unique temp file path for a fresh database that is cleaned up on teardown.
private func tempDBPath() -> String {
    let dir = FileManager.default.temporaryDirectory
    let name = UUID().uuidString + ".sqlite"
    return dir.appendingPathComponent(name).path
}

// MARK: - Persistence Tests

@Suite("SQLite Persistence Tests")
struct SQLitePersistenceTests {

    // MARK: - T008: Round-trip persistence across close/reopen

    @Test("Node persists across store close and reopen")
    func nodePersistsAcrossRestart() async throws {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let nodeID: UUID
        let nodeType = "Person"

        // Session 1: write
        do {
            let store = try SQLiteGraphStore(path: path)
            let node = try await store.addNode(type: nodeType, attributes: ["name": .string("Alice")])
            nodeID = node.id
        }

        // Session 2: reopen and verify
        let store2 = try SQLiteGraphStore(path: path)
        let fetched = try await store2.node(id: nodeID)
        #expect(fetched != nil)
        #expect(fetched?.type == nodeType)
        #expect(fetched?.attributes["name"] == .string("Alice"))
    }

    @Test("Edge persists across store close and reopen")
    func edgePersistsAcrossRestart() async throws {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let edgeID: UUID

        do {
            let store = try SQLiteGraphStore(path: path)
            let a = try await store.addNode(type: "A", attributes: [:])
            let b = try await store.addNode(type: "B", attributes: [:])
            let edge = try await store.addEdge(
                type: "knows",
                sourceID: a.id,
                targetID: b.id,
                attributes: ["since": .int(2024)],
                bounds: TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
            )
            edgeID = edge.id
        }

        let store2 = try SQLiteGraphStore(path: path)
        let outgoing = try await store2.edges(from: { () -> UUID in
            // We need the source node ID — fetch all edges of type "knows"
            // Since we can't directly look up by edge ID in the protocol, verify by
            // checking that there are edges in the store after reopen.
            UUID() // placeholder — will be overridden below
        }())
        // Actually verify via a fresh query using known structure
        _ = edgeID // referenced

        // Re-open and check edge count via nodes
        let store3 = try SQLiteGraphStore(path: path)
        let nodesA = try await store3.nodes(ofType: "A")
        let nodesB = try await store3.nodes(ofType: "B")
        #expect(nodesA.count == 1)
        #expect(nodesB.count == 1)
        let edges = try await store3.edges(from: nodesA[0].id)
        #expect(edges.count == 1)
        #expect(edges[0].type == "knows")
        #expect(edges[0].attributes["since"] == .int(2024))
    }

    @Test("TemporalState persists across store close and reopen")
    func temporalStatePersistsAcrossRestart() async throws {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let nodeID: UUID
        let queryDate = Date(timeIntervalSince1970: 1_000_000)

        do {
            let store = try SQLiteGraphStore(path: path)
            let node = try await store.addNode(type: "City", attributes: [:])
            nodeID = node.id
            _ = try await store.addState(
                for: node.id,
                attributes: ["population": .int(8_000_000)],
                bounds: TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
            )
        }

        let store2 = try SQLiteGraphStore(path: path)
        let active = try await store2.activeState(for: nodeID, at: queryDate)
        #expect(active != nil)
        #expect(active?.attributes["population"] == .int(8_000_000))
    }

    @Test("Episode persists across store close and reopen")
    func episodePersistsAcrossRestart() async throws {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let episodeID: UUID

        do {
            let store = try SQLiteGraphStore(path: path)
            let node = try await store.addNode(type: "X", attributes: [:])
            let state = try await store.addState(
                for: node.id,
                attributes: [:],
                bounds: TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
            )
            let episode = try await store.createEpisode(
                description: "test-episode",
                stateIDs: [state.id],
                timestamp: Date(timeIntervalSince1970: 100)
            )
            episodeID = episode.id
        }

        let store2 = try SQLiteGraphStore(path: path)
        let ep = try await store2.episode(id: episodeID)
        #expect(ep != nil)
        #expect(ep?.description == "test-episode")
        #expect(ep?.stateIDs.count == 1)
    }

    // MARK: - T009: Version counter persistence

    @Test("Version counter increases monotonically across restarts (FR-006)")
    func versionCounterPersistsAcrossRestart() async throws {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        var maxVersionSession1: UInt64 = 0

        do {
            let store = try SQLiteGraphStore(path: path)
            let node = try await store.addNode(type: "T", attributes: [:])
            let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
            let s1 = try await store.addState(for: node.id, attributes: [:], bounds: bounds)
            let s2 = try await store.addState(for: node.id, attributes: [:], bounds: bounds)
            let s3 = try await store.addState(for: node.id, attributes: [:], bounds: bounds)
            maxVersionSession1 = max(s1.version, s2.version, s3.version)
        }

        let store2 = try SQLiteGraphStore(path: path)
        let node2 = try await store2.addNode(type: "T", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        let newState = try await store2.addState(for: node2.id, attributes: [:], bounds: bounds)

        #expect(newState.version > maxVersionSession1,
            "Version \(newState.version) should be greater than \(maxVersionSession1) from previous session")
    }

    @Test("Version numbers are globally unique across entities and sessions")
    func versionNumbersNeverReused() async throws {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        var allVersions: Set<UInt64> = []

        // Session 1
        do {
            let store = try SQLiteGraphStore(path: path)
            let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
            for _ in 0..<5 {
                let n = try await store.addNode(type: "T", attributes: [:])
                let s = try await store.addState(for: n.id, attributes: [:], bounds: bounds)
                #expect(allVersions.insert(s.version).inserted, "Duplicate version \(s.version)")
            }
        }

        // Session 2
        let store2 = try SQLiteGraphStore(path: path)
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        for _ in 0..<5 {
            let n = try await store2.addNode(type: "T", attributes: [:])
            let s = try await store2.addState(for: n.id, attributes: [:], bounds: bounds)
            #expect(allVersions.insert(s.version).inserted, "Duplicate version \(s.version)")
        }

        #expect(allVersions.count == 10)
    }

    // MARK: - T010: Acyclicity constraint persistence

    @Test("Acyclicity constraint persists across store close and reopen (FR-005)")
    func acyclicityConstraintPersistsAcrossRestart() async throws {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let aID: UUID
        let bID: UUID

        // Session 1: configure constraint and add an edge A→B
        do {
            let store = try SQLiteGraphStore(path: path)
            await store.setAcyclicConstraint(for: "parent")
            let a = try await store.addNode(type: "N", attributes: [:])
            let b = try await store.addNode(type: "N", attributes: [:])
            aID = a.id
            bID = b.id
            _ = try await store.addEdge(
                type: "parent",
                sourceID: a.id,
                targetID: b.id,
                attributes: [:],
                bounds: TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
            )
        }

        // Session 2: reopen — constraint should still be active, cycle B→A must fail
        let store2 = try SQLiteGraphStore(path: path)
        do {
            _ = try await store2.addEdge(
                type: "parent",
                sourceID: bID,
                targetID: aID,
                attributes: [:],
                bounds: TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
            )
            Issue.record("Expected cycleViolation to be thrown after restart")
        } catch TemporalSwiftError.cycleViolation {
            // Expected
        }
    }
}
