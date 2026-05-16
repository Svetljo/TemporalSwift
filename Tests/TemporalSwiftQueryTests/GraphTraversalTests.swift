import Testing
import Foundation
@testable import TemporalSwiftCore
@testable import TemporalSwiftStorage
@testable import TemporalSwiftQuery

@Suite("Graph Traversal Tests")
struct GraphTraversalTests {

    private func makeBounds() -> TemporalBounds {
        TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
    }

    // MARK: - Basic traversal

    @Test("traverse: 0-depth returns only the start node")
    func traverseZeroDepth() async throws {
        let store = InMemoryGraphStore()
        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        _ = try await store.addEdge(type: "r", sourceID: a.id, targetID: b.id, attributes: [:], bounds: makeBounds())

        let traverser = GraphTraverser(store: store)
        let result = try await traverser.traverse(from: a.id, maxDepth: 0, at: nil, edgeTypeFilter: nil)
        #expect(result.nodes.count == 1)
        #expect(result.nodes[0].id == a.id)
        #expect(result.edges.isEmpty)
    }

    @Test("traverse: 1-hop returns direct neighbors")
    func traverseOneHop() async throws {
        let store = InMemoryGraphStore()
        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let c = try await store.addNode(type: "C", attributes: [:])
        let bounds = makeBounds()
        _ = try await store.addEdge(type: "r", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)
        _ = try await store.addEdge(type: "r", sourceID: a.id, targetID: c.id, attributes: [:], bounds: bounds)

        let traverser = GraphTraverser(store: store)
        let result = try await traverser.traverse(from: a.id, maxDepth: 1, at: nil, edgeTypeFilter: nil)
        let nodeIDs = Set(result.nodes.map(\.id))
        #expect(nodeIDs.contains(a.id))
        #expect(nodeIDs.contains(b.id))
        #expect(nodeIDs.contains(c.id))
        #expect(result.edges.count == 2)
    }

    @Test("traverse: 2-hop returns neighbors of neighbors")
    func traverseTwoHops() async throws {
        let store = InMemoryGraphStore()
        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let c = try await store.addNode(type: "C", attributes: [:])
        let bounds = makeBounds()
        _ = try await store.addEdge(type: "r", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)
        _ = try await store.addEdge(type: "r", sourceID: b.id, targetID: c.id, attributes: [:], bounds: bounds)

        let traverser = GraphTraverser(store: store)
        let result = try await traverser.traverse(from: a.id, maxDepth: 2, at: nil, edgeTypeFilter: nil)
        let nodeIDs = Set(result.nodes.map(\.id))
        #expect(nodeIDs.contains(a.id))
        #expect(nodeIDs.contains(b.id))
        #expect(nodeIDs.contains(c.id))
    }

    @Test("traverse: throws nodeNotFound for unknown start node")
    func traverseUnknownStart() async throws {
        let store = InMemoryGraphStore()
        let traverser = GraphTraverser(store: store)
        do {
            _ = try await traverser.traverse(from: UUID(), maxDepth: 1, at: nil, edgeTypeFilter: nil)
            Issue.record("Expected nodeNotFound to be thrown")
        } catch TemporalSwiftError.nodeNotFound {
            // expected
        }
    }

    // MARK: - Temporal filtering

    @Test("traverse with date: excludes edges inactive at query date")
    func traverseTemporalFilter() async throws {
        let store = InMemoryGraphStore()
        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let c = try await store.addNode(type: "C", attributes: [:])

        let tNow = Date(timeIntervalSince1970: 1000)
        let tFuture = Date(timeIntervalSince1970: 2000)

        // Edge a→b is active now
        _ = try await store.addEdge(
            type: "r",
            sourceID: a.id,
            targetID: b.id,
            attributes: [:],
            bounds: TemporalBounds(validFrom: tNow, validUntil: nil)
        )
        // Edge a→c only active in the future
        _ = try await store.addEdge(
            type: "r",
            sourceID: a.id,
            targetID: c.id,
            attributes: [:],
            bounds: TemporalBounds(validFrom: tFuture, validUntil: nil)
        )

        let traverser = GraphTraverser(store: store)
        let result = try await traverser.traverse(from: a.id, maxDepth: 1, at: tNow, edgeTypeFilter: nil)
        let nodeIDs = Set(result.nodes.map(\.id))
        #expect(nodeIDs.contains(b.id))
        #expect(!nodeIDs.contains(c.id))
    }

    // MARK: - Edge type filter

    @Test("traverse with edgeTypeFilter: only follows matching edge types")
    func traverseEdgeTypeFilter() async throws {
        let store = InMemoryGraphStore()
        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let c = try await store.addNode(type: "C", attributes: [:])
        let bounds = makeBounds()
        _ = try await store.addEdge(type: "knows", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)
        _ = try await store.addEdge(type: "lives_in", sourceID: a.id, targetID: c.id, attributes: [:], bounds: bounds)

        let traverser = GraphTraverser(store: store)
        let result = try await traverser.traverse(
            from: a.id, maxDepth: 1, at: nil, edgeTypeFilter: ["knows"]
        )
        let nodeIDs = Set(result.nodes.map(\.id))
        #expect(nodeIDs.contains(b.id))
        #expect(!nodeIDs.contains(c.id))
    }
}
