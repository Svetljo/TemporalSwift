import Testing
import Foundation
@testable import TemporalSwiftCore
@testable import TemporalSwiftStorage
@testable import TemporalSwiftQuery

@Suite("Cycle Constraint Tests")
struct CycleConstraintTests {

    private func makeBounds() -> TemporalBounds {
        TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
    }

    @Test("unconstrained edge type allows cycles")
    func unconstrainedAllowsCycles() async throws {
        let store = InMemoryGraphStore()
        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let bounds = makeBounds()
        _ = try await store.addEdge(type: "cycle_ok", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)
        // This would form a cycle: b → a
        _ = try await store.addEdge(type: "cycle_ok", sourceID: b.id, targetID: a.id, attributes: [:], bounds: bounds)
        // Should succeed with no error
        let edges = try await store.edges(from: b.id)
        #expect(!edges.isEmpty)
    }

    @Test("constrained edge type rejects cycle-forming write")
    func constrainedRejectsCycle() async throws {
        let store = InMemoryGraphStore()
        await store.setAcyclicConstraint(for: "parent_of")

        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let bounds = makeBounds()
        _ = try await store.addEdge(type: "parent_of", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)

        // Attempt to create a cycle: b → a (which would mean a is parent of b AND b is parent of a)
        do {
            _ = try await store.addEdge(
                type: "parent_of",
                sourceID: b.id,
                targetID: a.id,
                attributes: [:],
                bounds: bounds
            )
            Issue.record("Expected cycleViolation to be thrown")
        } catch TemporalSwiftError.cycleViolation(let edgeType, let srcID, let tgtID) {
            #expect(edgeType == "parent_of")
            #expect(srcID == b.id)
            #expect(tgtID == a.id)
        }
    }

    @Test("constrained edge type allows non-cycle-forming writes")
    func constrainedAllowsNonCycle() async throws {
        let store = InMemoryGraphStore()
        await store.setAcyclicConstraint(for: "parent_of")

        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let c = try await store.addNode(type: "C", attributes: [:])
        let bounds = makeBounds()

        _ = try await store.addEdge(type: "parent_of", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)
        _ = try await store.addEdge(type: "parent_of", sourceID: b.id, targetID: c.id, attributes: [:], bounds: bounds)
        // a → b → c: no cycle
        let bEdges = try await store.edges(from: b.id)
        #expect(!bEdges.isEmpty)
    }

    @Test("removing constraint re-allows cycle-forming writes")
    func removeConstraintAllowsCycle() async throws {
        let store = InMemoryGraphStore()
        await store.setAcyclicConstraint(for: "parent_of")

        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let bounds = makeBounds()
        _ = try await store.addEdge(type: "parent_of", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)

        // Remove constraint — now cycles should be allowed
        await store.removeAcyclicConstraint(for: "parent_of")

        _ = try await store.addEdge(type: "parent_of", sourceID: b.id, targetID: a.id, attributes: [:], bounds: bounds)
        let bEdges = try await store.edges(from: b.id, ofType: "parent_of")
        #expect(!bEdges.isEmpty)
    }

    @Test("constrained edge type detects multi-hop cycle")
    func constrainedDetectsMultiHopCycle() async throws {
        let store = InMemoryGraphStore()
        await store.setAcyclicConstraint(for: "parent_of")

        let a = try await store.addNode(type: "A", attributes: [:])
        let b = try await store.addNode(type: "B", attributes: [:])
        let c = try await store.addNode(type: "C", attributes: [:])
        let bounds = makeBounds()

        _ = try await store.addEdge(type: "parent_of", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)
        _ = try await store.addEdge(type: "parent_of", sourceID: b.id, targetID: c.id, attributes: [:], bounds: bounds)

        // c → a would form: a→b→c→a (3-hop cycle)
        do {
            _ = try await store.addEdge(
                type: "parent_of",
                sourceID: c.id,
                targetID: a.id,
                attributes: [:],
                bounds: bounds
            )
            Issue.record("Expected cycleViolation to be thrown")
        } catch TemporalSwiftError.cycleViolation {
            // expected
        }
    }
}
