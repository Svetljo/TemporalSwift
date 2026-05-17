import Testing
import Foundation
import TemporalSwiftCore
import TemporalSwiftPersistence

// MARK: - US4: Version Monotonicity Tests

@Suite("Version Monotonicity Tests", .serialized)
struct VersionMonotonicityTests {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "temporalswift-version-\(UUID().uuidString).store")
    }

    private func deleteTempStore(at url: URL) {
        let base = url.path()
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: base + suffix)
        }
    }

    @Test("Version counter is monotonic across store restarts")
    func versionMonotonicAcrossRestarts() async throws {
        let url = makeTempURL()
        defer { deleteTempStore(at: url) }

        var session1MaxVersion: UInt64 = 0
        let nodeID: UUID

        // Session 1: write several states
        do {
            let store = try SwiftDataGraphStore(url: url)
            let node = try await store.addNode(type: "N", attributes: [:])
            nodeID = node.id
            let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)
            for i in 1...5 {
                let s = try await store.addState(for: nodeID, attributes: ["i": .int(i)], bounds: bounds)
                session1MaxVersion = max(session1MaxVersion, s.version)
            }
        }

        // Session 2: add more states and verify all versions exceed session 1 max
        let store2 = try SwiftDataGraphStore(url: url)
        let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)
        for i in 6...10 {
            let s = try await store2.addState(for: nodeID, attributes: ["i": .int(i)], bounds: bounds)
            #expect(s.version > session1MaxVersion,
                "Version \(s.version) must exceed session-1 max \(session1MaxVersion)")
        }
    }

    @Test("Versions are strictly increasing within a single session")
    func versionStrictlyIncreasing() async throws {
        let store = try SwiftDataGraphStore(inMemory: true)
        let node = try await store.addNode(type: "N", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)

        var prev: UInt64 = 0
        for i in 1...10 {
            let s = try await store.addState(for: node.id, attributes: ["i": .int(i)], bounds: bounds)
            #expect(s.version > prev, "Version \(s.version) must be > previous \(prev)")
            prev = s.version
        }
    }
}

// MARK: - US3 & US4: Multi-Store Isolation + Acyclicity Constraint Tests
// (Appended here to keep constraint-related tests together)

@Suite("Acyclicity Constraint Tests", .serialized)
struct AcyclicityConstraintTests {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "temporalswift-acyclic-\(UUID().uuidString).store")
    }

    private func deleteTempStore(at url: URL) {
        let base = url.path()
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: base + suffix)
        }
    }

    @Test("Acyclicity constraints survive store restart")
    func constraintSurvivesRestart() async throws {
        let url = makeTempURL()
        defer { deleteTempStore(at: url) }

        let aID: UUID
        let bID: UUID
        let cID: UUID
        let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)

        // Session 1: set constraint, add edges A→B→C
        do {
            let store = try SwiftDataGraphStore(url: url)
            await store.setAcyclicConstraint(for: "parent")
            let a = try await store.addNode(type: "X", attributes: [:])
            let b = try await store.addNode(type: "X", attributes: [:])
            let c = try await store.addNode(type: "X", attributes: [:])
            aID = a.id; bID = b.id; cID = c.id
            _ = try await store.addEdge(type: "parent", sourceID: aID, targetID: bID, attributes: [:], bounds: bounds)
            _ = try await store.addEdge(type: "parent", sourceID: bID, targetID: cID, attributes: [:], bounds: bounds)
        }

        // Session 2: reload — adding C→A must be rejected (cycle)
        let store2 = try SwiftDataGraphStore(url: url)
        await #expect(throws: TemporalSwiftError.self) {
            _ = try await store2.addEdge(type: "parent", sourceID: cID, targetID: aID, attributes: [:], bounds: bounds)
        }
    }

    @Test("setAcyclicConstraint / removeAcyclicConstraint work correctly")
    func setAndRemoveConstraint() async throws {
        let store = try SwiftDataGraphStore(inMemory: true)
        let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)
        let a = try await store.addNode(type: "N", attributes: [:])
        let b = try await store.addNode(type: "N", attributes: [:])

        _ = try await store.addEdge(type: "rel", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)

        // Set constraint — adding reverse edge should fail
        await store.setAcyclicConstraint(for: "rel")
        await #expect(throws: TemporalSwiftError.self) {
            _ = try await store.addEdge(type: "rel", sourceID: b.id, targetID: a.id, attributes: [:], bounds: bounds)
        }

        // Remove constraint — reverse edge should now succeed
        await store.removeAcyclicConstraint(for: "rel")
        let reverseEdge = try await store.addEdge(type: "rel", sourceID: b.id, targetID: a.id, attributes: [:], bounds: bounds)
        #expect(reverseEdge.sourceID == b.id)
    }

    // MARK: US3: Multi-Store Isolation (T024)

    @Test("Two stores at different URLs are fully isolated")
    func multiStoreIsolation() async throws {
        let url1 = makeTempURL()
        let url2 = makeTempURL()
        defer { deleteTempStore(at: url1); deleteTempStore(at: url2) }

        let store1 = try SwiftDataGraphStore(url: url1)
        let store2 = try SwiftDataGraphStore(url: url2)

        let nodeA = try await store1.addNode(type: "Fruit", attributes: ["name": .string("Apple")])
        let nodeB = try await store2.addNode(type: "Veggie", attributes: ["name": .string("Carrot")])

        // store1 does not see store2's node
        let fromStore1 = try await store1.node(id: nodeB.id)
        #expect(fromStore1 == nil)

        // store2 does not see store1's node
        let fromStore2 = try await store2.node(id: nodeA.id)
        #expect(fromStore2 == nil)

        // Types are independent
        let fruits = try await store1.nodes(ofType: "Fruit")
        #expect(fruits.count == 1)
        let fruitsInStore2 = try await store2.nodes(ofType: "Fruit")
        #expect(fruitsInStore2.count == 0)
    }
}
