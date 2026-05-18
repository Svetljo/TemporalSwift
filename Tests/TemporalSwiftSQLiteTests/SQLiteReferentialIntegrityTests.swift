import Testing
import Foundation
@testable import TemporalSwiftCore
@testable import TemporalSwiftSQLite

@Suite("SQLite Referential Integrity Tests")
struct SQLiteReferentialIntegrityTests {

    @Test("addEdge: succeeds when both nodes exist")
    func addEdgeValidRefs() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
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
        let store = try SQLiteGraphStore(path: ":memory:")
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
        let store = try SQLiteGraphStore(path: ":memory:")
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
        let store = try SQLiteGraphStore(path: ":memory:")
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
        let store = try SQLiteGraphStore(path: ":memory:")
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
        let store = try SQLiteGraphStore(path: ":memory:")
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

    @Test("setAcyclicConstraint: cycle-forming edge throws cycleViolation")
    func cycleViolationThrown() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        await store.setAcyclicConstraint(for: "parent")
        let a = try await store.addNode(type: "N", attributes: [:])
        let b = try await store.addNode(type: "N", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(), validUntil: nil)

        _ = try await store.addEdge(type: "parent", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)

        do {
            _ = try await store.addEdge(type: "parent", sourceID: b.id, targetID: a.id, attributes: [:], bounds: bounds)
            Issue.record("Expected cycleViolation")
        } catch TemporalSwiftError.cycleViolation(let edgeType, _, _) {
            #expect(edgeType == "parent")
        }
    }

    @Test("removeAcyclicConstraint: edge that would have been cycle is now allowed")
    func removeConstraintAllowsCycle() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        await store.setAcyclicConstraint(for: "parent")
        await store.removeAcyclicConstraint(for: "parent")
        let a = try await store.addNode(type: "N", attributes: [:])
        let b = try await store.addNode(type: "N", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(), validUntil: nil)

        _ = try await store.addEdge(type: "parent", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)
        // This would be a cycle — but constraint was removed
        let edge = try await store.addEdge(type: "parent", sourceID: b.id, targetID: a.id, attributes: [:], bounds: bounds)
        #expect(edge.type == "parent")
    }
}
