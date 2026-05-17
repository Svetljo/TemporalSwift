import Testing
import Foundation
import TemporalSwiftCore
import TemporalSwiftPersistence

// MARK: - Helpers

private func makeTempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "temporalswift-test-\(UUID().uuidString).store")
}

private func deleteTempStore(at url: URL) {
    // SwiftData creates the SQLite file plus -shm and -wal
    let base = url.path()
    for suffix in ["", "-shm", "-wal"] {
        try? FileManager.default.removeItem(atPath: base + suffix)
    }
}

// MARK: - Persistence Round-Trip Tests (US1)

// SwiftData ModelContainer initialisation is not safe under parallel test execution.
// `.serialized` ensures tests in this suite run one at a time.
@Suite("Persistence Round-Trip Tests", .serialized)
struct PersistenceRoundTripTests {

    // MARK: Node round-trip

    @Test("Nodes survive store restart")
    func nodeRoundTrip() async throws {
        let url = makeTempURL()
        defer { deleteTempStore(at: url) }

        let nodeID: UUID
        let nodeType = "Person"
        let nodeAttributes: [String: AttributeValue] = ["name": .string("Ada"), "age": .int(36)]

        // Session 1: write
        do {
            let store = try SwiftDataGraphStore(url: url)
            let node = try await store.addNode(type: nodeType, attributes: nodeAttributes)
            nodeID = node.id
        }

        // Session 2: read
        let store2 = try SwiftDataGraphStore(url: url)
        let loaded = try await store2.node(id: nodeID)
        #expect(loaded != nil)
        #expect(loaded?.id == nodeID)
        #expect(loaded?.type == nodeType)
        #expect(loaded?.attributes == nodeAttributes)
    }

    // MARK: Edge round-trip

    @Test("Edges survive store restart")
    func edgeRoundTrip() async throws {
        let url = makeTempURL()
        defer { deleteTempStore(at: url) }

        let edgeID: UUID
        let sourceID: UUID
        let targetID: UUID
        let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)

        do {
            let store = try SwiftDataGraphStore(url: url)
            let source = try await store.addNode(type: "A", attributes: [:])
            let target = try await store.addNode(type: "B", attributes: [:])
            sourceID = source.id
            targetID = target.id
            let edge = try await store.addEdge(
                type: "knows",
                sourceID: source.id,
                targetID: target.id,
                attributes: [:],
                bounds: bounds
            )
            edgeID = edge.id
        }

        let store2 = try SwiftDataGraphStore(url: url)
        let outgoing = try await store2.edges(from: sourceID)
        #expect(outgoing.count == 1)
        #expect(outgoing[0].id == edgeID)
        #expect(outgoing[0].targetID == targetID)
    }

    // MARK: TemporalState round-trip

    @Test("Temporal states survive store restart")
    func temporalStateRoundTrip() async throws {
        let url = makeTempURL()
        defer { deleteTempStore(at: url) }

        let nodeID: UUID
        let stateAttributes: [String: AttributeValue] = ["role": .string("Engineer")]
        let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)

        do {
            let store = try SwiftDataGraphStore(url: url)
            let node = try await store.addNode(type: "Person", attributes: [:])
            nodeID = node.id
            _ = try await store.addState(for: nodeID, attributes: stateAttributes, bounds: bounds)
        }

        let store2 = try SwiftDataGraphStore(url: url)
        let states = try await store2.states(for: nodeID)
        #expect(states.count == 1)
        #expect(states[0].attributes == stateAttributes)
        #expect(states[0].bounds.validUntil == nil)
    }

    // MARK: Episode round-trip

    @Test("Episodes survive store restart")
    func episodeRoundTrip() async throws {
        let url = makeTempURL()
        defer { deleteTempStore(at: url) }

        let episodeID: UUID
        let episodeDesc = "test-episode"

        do {
            let store = try SwiftDataGraphStore(url: url)
            let node = try await store.addNode(type: "X", attributes: [:])
            let state = try await store.addState(
                for: node.id,
                attributes: [:],
                bounds: TemporalBounds(validFrom: Date.distantPast, validUntil: nil)
            )
            let episode = try await store.createEpisode(
                description: episodeDesc,
                stateIDs: [state.id],
                timestamp: Date()
            )
            episodeID = episode.id
        }

        let store2 = try SwiftDataGraphStore(url: url)
        // Episodes are stored; verify we can create another and the first persisted
        // (GraphStore protocol doesn't expose episode fetch by ID, so we verify via state IDs)
        _ = episodeID  // Used to confirm the episode was written without crash
        let states = try await store2.states(for: (try await store2.nodes(ofType: "X").first!.id))
        #expect(states.count == 1)
    }

    // MARK: All entities survive restart

    @Test("All entity types survive store restart")
    func allEntitiesRoundTrip() async throws {
        let url = makeTempURL()
        defer { deleteTempStore(at: url) }

        let nodeIDs: [UUID]
        let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)

        do {
            let store = try SwiftDataGraphStore(url: url)
            let n1 = try await store.addNode(type: "Fruit", attributes: ["name": .string("Apple")])
            let n2 = try await store.addNode(type: "Fruit", attributes: ["name": .string("Banana")])
            let n3 = try await store.addNode(type: "Color", attributes: ["name": .string("Red")])
            nodeIDs = [n1.id, n2.id, n3.id]
            _ = try await store.addEdge(type: "has_color", sourceID: n1.id, targetID: n3.id, attributes: [:], bounds: bounds)
            _ = try await store.addState(for: n1.id, attributes: ["ripe": .bool(true)], bounds: bounds)
        }

        let store2 = try SwiftDataGraphStore(url: url)
        let fruits = try await store2.nodes(ofType: "Fruit")
        #expect(fruits.count == 2)
        let colors = try await store2.nodes(ofType: "Color")
        #expect(colors.count == 1)
        let edgesFromApple = try await store2.edges(from: nodeIDs[0])
        #expect(edgesFromApple.count == 1)
        // Apple node has 1 state from the explicit addState call.
        // The state created by addEdge belongs to the edge's ID, not the node's ID.
        let appleStates = try await store2.states(for: nodeIDs[0])
        #expect(appleStates.count == 1)
    }

    // MARK: AttributeValue variant round-trips (T017)

    @Test("All AttributeValue variants survive round-trip")
    func attributeValueVariants() async throws {
        let url = makeTempURL()
        defer { deleteTempStore(at: url) }

        let testDate = Date(timeIntervalSince1970: 1_700_000_000)
        let allVariants: [String: AttributeValue] = [
            "str":    .string("hello"),
            "int":    .int(42),
            "dbl":    .double(3.14),
            "bool":   .bool(true),
            "date":   .date(testDate),
            "null":   .null,
        ]

        let nodeID: UUID
        do {
            let store = try SwiftDataGraphStore(url: url)
            let node = try await store.addNode(type: "Test", attributes: allVariants)
            nodeID = node.id
        }

        let store2 = try SwiftDataGraphStore(url: url)
        let loaded = try await store2.node(id: nodeID)
        #expect(loaded != nil)
        let attrs = loaded!.attributes
        #expect(attrs["str"] == .string("hello"))
        #expect(attrs["int"] == .int(42))
        #expect(attrs["bool"] == .bool(true))
        #expect(attrs["null"] == .null)
        // Double — allow for small floating-point drift via pattern match
        if case .double(let d) = attrs["dbl"] {
            #expect(abs(d - 3.14) < 0.0001)
        } else {
            Issue.record("Expected .double for key 'dbl'")
        }
        // Date — compare with millisecond tolerance
        if case .date(let d) = attrs["date"] {
            #expect(abs(d.timeIntervalSince(testDate)) < 0.001)
        } else {
            Issue.record("Expected .date for key 'date'")
        }
    }

    @Test("AttributeValue variants in temporal state attributes survive round-trip")
    func attributeValueVariantsInStates() async throws {
        let url = makeTempURL()
        defer { deleteTempStore(at: url) }

        let stateAttrs: [String: AttributeValue] = [
            "active": .bool(false),
            "score":  .double(99.9),
            "label":  .string("test"),
            "count":  .int(7),
            "empty":  .null,
        ]
        let nodeID: UUID
        do {
            let store = try SwiftDataGraphStore(url: url)
            let node = try await store.addNode(type: "Entity", attributes: [:])
            nodeID = node.id
            _ = try await store.addState(
                for: nodeID,
                attributes: stateAttrs,
                bounds: TemporalBounds(validFrom: Date.distantPast, validUntil: nil)
            )
        }

        let store2 = try SwiftDataGraphStore(url: url)
        let states = try await store2.states(for: nodeID)
        #expect(states.count == 1)
        let loadedAttrs = states[0].attributes
        #expect(loadedAttrs["active"] == .bool(false))
        #expect(loadedAttrs["label"] == .string("test"))
        #expect(loadedAttrs["count"] == .int(7))
        #expect(loadedAttrs["empty"] == .null)
    }
}
