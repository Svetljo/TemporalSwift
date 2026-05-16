import Testing
import Foundation
@testable import TemporalSwiftCore
@testable import TemporalSwiftStorage
@testable import TemporalSwiftQuery

@Suite("ContextPackager Tests")
struct ContextPackagerTests {

    private func makeStore() -> InMemoryGraphStore { InMemoryGraphStore() }
    private func makeBounds() -> TemporalBounds {
        TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
    }

    // MARK: - Basic snapshot

    @Test("snapshot: output is valid JSON and contains focal entity")
    func snapshotValidJSON() async throws {
        let store = makeStore()
        let focal = try await store.addNode(type: "Person", attributes: ["name": .string("Alice")])
        _ = try await store.addState(for: focal.id, attributes: [:], bounds: makeBounds())

        let traverser = GraphTraverser(store: store)
        let packager = ContextPackager(store: store, traverser: traverser)
        let snapshot = try await packager.snapshot(
            focalEntityID: focal.id,
            at: Date(timeIntervalSince1970: 1000),
            maxDepth: 2,
            characterBudget: 2000,
            charsPerToken: 4,
            edgeTypeFilter: nil
        )

        #expect(snapshot.focalEntityID == focal.id)
        #expect(!snapshot.nodes.isEmpty)

        // Validate JSON serialisability
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        #expect(!data.isEmpty)

        // Verify it round-trips
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ContextSnapshot.self, from: data)
        #expect(decoded.focalEntityID == focal.id)
    }

    @Test("snapshot: respects character budget within 5% overshoot (SC-005)")
    func snapshotRespectsBudget() async throws {
        let store = makeStore()
        let focal = try await store.addNode(type: "Person", attributes: ["name": .string("Alice")])

        // Add many connected nodes to exercise pruning
        for i in 0..<20 {
            let other = try await store.addNode(type: "Item", attributes: ["index": .int(i)])
            _ = try await store.addEdge(
                type: "owns",
                sourceID: focal.id,
                targetID: other.id,
                attributes: [:],
                bounds: makeBounds()
            )
            _ = try await store.addState(
                for: other.id,
                attributes: ["detail": .string(String(repeating: "x", count: 100))],
                bounds: makeBounds()
            )
        }

        let traverser = GraphTraverser(store: store)
        let packager = ContextPackager(store: store, traverser: traverser)
        let budget = 500 // characters (× charsPerToken=1 for simplicity)
        let snapshot = try await packager.snapshot(
            focalEntityID: focal.id,
            at: Date(timeIntervalSince1970: 1000),
            maxDepth: 1,
            characterBudget: budget,
            charsPerToken: 1,
            edgeTypeFilter: nil
        )

        let overshootLimit = Int(Double(budget) * 1.05)
        #expect(snapshot.actualCharacters <= overshootLimit)
    }

    @Test("snapshot: closer entities included before distant ones (relevance ranking)")
    func snapshotRelevanceRanking() async throws {
        let store = makeStore()
        let focal = try await store.addNode(type: "Person", attributes: [:])
        let close = try await store.addNode(type: "Close", attributes: [:])
        let distant = try await store.addNode(type: "Distant", attributes: [:])
        let bounds = makeBounds()
        _ = try await store.addEdge(type: "r", sourceID: focal.id, targetID: close.id, attributes: [:], bounds: bounds)
        _ = try await store.addEdge(type: "r", sourceID: close.id, targetID: distant.id, attributes: [:], bounds: bounds)

        let traverser = GraphTraverser(store: store)
        let packager = ContextPackager(store: store, traverser: traverser)
        let snapshot = try await packager.snapshot(
            focalEntityID: focal.id,
            at: Date(timeIntervalSince1970: 1000),
            maxDepth: 2,
            characterBudget: 100_000,
            charsPerToken: 1,
            edgeTypeFilter: nil
        )

        // Focal entity must appear first
        #expect(snapshot.nodes.first?.id == focal.id)
        // All three nodes should be included with a generous budget
        let ids = Set(snapshot.nodes.map(\.id))
        #expect(ids.contains(focal.id))
        #expect(ids.contains(close.id))
        #expect(ids.contains(distant.id))
    }

    @Test("snapshot: edge type filter limits included relationship types")
    func snapshotEdgeTypeFilter() async throws {
        let store = makeStore()
        let focal = try await store.addNode(type: "Person", attributes: [:])
        let friend = try await store.addNode(type: "Person", attributes: [:])
        let city = try await store.addNode(type: "Location", attributes: [:])
        let bounds = makeBounds()
        _ = try await store.addEdge(type: "knows", sourceID: focal.id, targetID: friend.id, attributes: [:], bounds: bounds)
        _ = try await store.addEdge(type: "lives_in", sourceID: focal.id, targetID: city.id, attributes: [:], bounds: bounds)

        let traverser = GraphTraverser(store: store)
        let packager = ContextPackager(store: store, traverser: traverser)
        let snapshot = try await packager.snapshot(
            focalEntityID: focal.id,
            at: Date(timeIntervalSince1970: 1000),
            maxDepth: 1,
            characterBudget: 100_000,
            charsPerToken: 1,
            edgeTypeFilter: ["knows"]
        )

        let nodeIDs = Set(snapshot.nodes.map(\.id))
        #expect(nodeIDs.contains(friend.id))
        #expect(!nodeIDs.contains(city.id))
        // Only "knows" edges in snapshot
        for edge in snapshot.edges {
            #expect(edge.type == "knows")
        }
    }
}
