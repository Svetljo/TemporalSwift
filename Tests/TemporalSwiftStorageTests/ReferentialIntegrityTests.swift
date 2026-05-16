import Testing
import Foundation
@testable import TemporalSwiftCore
@testable import TemporalSwiftStorage

@Suite("Referential Integrity Tests")
struct ReferentialIntegrityTests {

    @Test("addEdge: succeeds when both nodes exist")
    func addEdgeValidRefs() async throws {
        let store = InMemoryGraphStore()
        let src = try await store.addNode(type: "A", attributes: [:])
        let tgt = try await store.addNode(type: "B", attributes: [:])
        let edge = try await store.addEdge(
            type: "rel",
            sourceID: src.id,
            targetID: tgt.id,
            attributes: [:],
            bounds: TemporalBounds(validFrom: Date(), validUntil: nil)
        )
        #expect(edge.sourceID == src.id)
        #expect(edge.targetID == tgt.id)
    }

    @Test("addEdge: throws referentialIntegrityViolation for missing source node")
    func addEdgeMissingSource() async throws {
        let store = InMemoryGraphStore()
        let tgt = try await store.addNode(type: "B", attributes: [:])
        let missingID = UUID()
        do {
            _ = try await store.addEdge(
                type: "rel",
                sourceID: missingID,
                targetID: tgt.id,
                attributes: [:],
                bounds: TemporalBounds(validFrom: Date(), validUntil: nil)
            )
            Issue.record("Expected referentialIntegrityViolation to be thrown")
        } catch TemporalSwiftError.referentialIntegrityViolation(let id) {
            #expect(id == missingID)
        }
    }

    @Test("addEdge: throws referentialIntegrityViolation for missing target node")
    func addEdgeMissingTarget() async throws {
        let store = InMemoryGraphStore()
        let src = try await store.addNode(type: "A", attributes: [:])
        let missingID = UUID()
        do {
            _ = try await store.addEdge(
                type: "rel",
                sourceID: src.id,
                targetID: missingID,
                attributes: [:],
                bounds: TemporalBounds(validFrom: Date(), validUntil: nil)
            )
            Issue.record("Expected referentialIntegrityViolation to be thrown")
        } catch TemporalSwiftError.referentialIntegrityViolation(let id) {
            #expect(id == missingID)
        }
    }

    @Test("edges(from:): returns all outgoing edges for a node")
    func edgesFrom() async throws {
        let store = InMemoryGraphStore()
        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let c = try await store.addNode(type: "C", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(), validUntil: nil)
        _ = try await store.addEdge(type: "r", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)
        _ = try await store.addEdge(type: "r", sourceID: a.id, targetID: c.id, attributes: [:], bounds: bounds)
        _ = try await store.addEdge(type: "r", sourceID: b.id, targetID: c.id, attributes: [:], bounds: bounds)
        let aEdges = try await store.edges(from: a.id)
        #expect(aEdges.count == 2)
    }

    @Test("edges(to:): returns all incoming edges for a node")
    func edgesTo() async throws {
        let store = InMemoryGraphStore()
        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let c = try await store.addNode(type: "C", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(), validUntil: nil)
        _ = try await store.addEdge(type: "r", sourceID: a.id, targetID: c.id, attributes: [:], bounds: bounds)
        _ = try await store.addEdge(type: "r", sourceID: b.id, targetID: c.id, attributes: [:], bounds: bounds)
        let cIncoming = try await store.edges(to: c.id)
        #expect(cIncoming.count == 2)
    }

    @Test("edges(from:ofType:): filters by edge type")
    func edgesFromOfType() async throws {
        let store = InMemoryGraphStore()
        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let c = try await store.addNode(type: "C", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(), validUntil: nil)
        _ = try await store.addEdge(type: "knows", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)
        _ = try await store.addEdge(type: "lives_in", sourceID: a.id, targetID: c.id, attributes: [:], bounds: bounds)
        let knows = try await store.edges(from: a.id, ofType: "knows")
        #expect(knows.count == 1)
        #expect(knows[0].type == "knows")
    }
}
