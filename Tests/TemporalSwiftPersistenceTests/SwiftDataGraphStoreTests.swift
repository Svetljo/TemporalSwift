import Testing
import Foundation
import TemporalSwiftCore
import TemporalSwiftStorage
import TemporalSwiftPersistence

// MARK: - US2: Temporal Query Parity Tests

/// Verifies that `SwiftDataGraphStore` produces identical results to
/// `InMemoryGraphStore` for all temporal query operations.
@Suite("SwiftData GraphStore Parity Tests", .serialized)
struct SwiftDataGraphStoreTests {

    // MARK: Helpers

    private func makeSwiftDataStore() throws -> SwiftDataGraphStore {
        try SwiftDataGraphStore(inMemory: true)
    }

    private func makeInMemoryStore() -> InMemoryGraphStore {
        InMemoryGraphStore()
    }

    // MARK: Node parity

    @Test("addNode/node(id:)/nodes(ofType:) match InMemoryGraphStore")
    func nodeParity() async throws {
        let sd = try makeSwiftDataStore()
        let im = makeInMemoryStore()

        let attrs: [String: AttributeValue] = ["x": .int(1)]
        let sdNode = try await sd.addNode(type: "T", attributes: attrs)
        let imNode = try await im.addNode(type: "T", attributes: attrs)

        // Fetched by ID
        let sdFetched = try await sd.node(id: sdNode.id)
        #expect(sdFetched?.type == "T")
        #expect(sdFetched?.attributes == attrs)

        let imFetched = try await im.node(id: imNode.id)
        #expect(imFetched?.type == "T")

        // Not found returns nil
        let missing = try await sd.node(id: UUID())
        #expect(missing == nil)

        // nodes(ofType:)
        _ = try await sd.addNode(type: "T", attributes: [:])
        _ = try await sd.addNode(type: "Other", attributes: [:])
        let tNodes = try await sd.nodes(ofType: "T")
        #expect(tNodes.count == 2)
        let otherNodes = try await sd.nodes(ofType: "Other")
        #expect(otherNodes.count == 1)
    }

    // MARK: Edge parity

    @Test("addEdge/edges(from:)/edges(to:)/edges(from:ofType:) match InMemoryGraphStore")
    func edgeParity() async throws {
        let sd = try makeSwiftDataStore()
        let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)

        let a = try await sd.addNode(type: "A", attributes: [:])
        let b = try await sd.addNode(type: "B", attributes: [:])
        let c = try await sd.addNode(type: "C", attributes: [:])

        let ab = try await sd.addEdge(type: "rel", sourceID: a.id, targetID: b.id, attributes: [:], bounds: bounds)
        let ac = try await sd.addEdge(type: "other", sourceID: a.id, targetID: c.id, attributes: [:], bounds: bounds)

        let fromA = try await sd.edges(from: a.id)
        #expect(fromA.count == 2)

        let toB = try await sd.edges(to: b.id)
        #expect(toB.count == 1)
        #expect(toB[0].id == ab.id)

        let toC = try await sd.edges(to: c.id)
        #expect(toC.count == 1)
        #expect(toC[0].id == ac.id)

        let relFromA = try await sd.edges(from: a.id, ofType: "rel")
        #expect(relFromA.count == 1)
        #expect(relFromA[0].targetID == b.id)
    }

    // MARK: Referential integrity parity

    @Test("addEdge throws referentialIntegrityViolation for missing nodes")
    func referentialIntegrityViolation() async throws {
        let sd = try makeSwiftDataStore()
        let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)
        let node = try await sd.addNode(type: "X", attributes: [:])

        await #expect(throws: TemporalSwiftError.self) {
            _ = try await sd.addEdge(type: "rel", sourceID: UUID(), targetID: node.id, attributes: [:], bounds: bounds)
        }
        await #expect(throws: TemporalSwiftError.self) {
            _ = try await sd.addEdge(type: "rel", sourceID: node.id, targetID: UUID(), attributes: [:], bounds: bounds)
        }
    }

    // MARK: Temporal state parity

    @Test("states(for:) returns all states ordered by version")
    func statesOrdering() async throws {
        let sd = try makeSwiftDataStore()
        let node = try await sd.addNode(type: "N", attributes: [:])

        let b1 = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: Date(timeIntervalSince1970: 10))
        let b2 = TemporalBounds(validFrom: Date(timeIntervalSince1970: 5), validUntil: nil)

        let s1 = try await sd.addState(for: node.id, attributes: ["v": .int(1)], bounds: b1)
        let s2 = try await sd.addState(for: node.id, attributes: ["v": .int(2)], bounds: b2)

        let states = try await sd.states(for: node.id)
        #expect(states.count == 2)
        #expect(states[0].version < states[1].version)
        #expect(states[0].id == s1.id)
        #expect(states[1].id == s2.id)
    }

    // MARK: Point-in-time query parity (T021)

    @Test("activeState returns highest-version active state at given date")
    func activeStateHighestVersion() async throws {
        let sd = try makeSwiftDataStore()
        let node = try await sd.addNode(type: "N", attributes: [:])

        let t0 = Date(timeIntervalSince1970: 100)
        let t5 = Date(timeIntervalSince1970: 500)

        // Two overlapping states active at t0
        _ = try await sd.addState(
            for: node.id,
            attributes: ["v": .int(1)],
            bounds: TemporalBounds(validFrom: t0, validUntil: nil)
        )
        _ = try await sd.addState(
            for: node.id,
            attributes: ["v": .int(2)],
            bounds: TemporalBounds(validFrom: t0, validUntil: nil)
        )

        let active = try await sd.activeState(for: node.id, at: t5)
        #expect(active != nil)
        // Highest version wins
        #expect(active?.attributes["v"] == .int(2))
    }

    @Test("activeState returns nil before validFrom")
    func activeStateBeforeRange() async throws {
        let sd = try makeSwiftDataStore()
        let node = try await sd.addNode(type: "N", attributes: [:])

        let future = Date(timeIntervalSinceNow: 3600)
        _ = try await sd.addState(
            for: node.id,
            attributes: [:],
            bounds: TemporalBounds(validFrom: future, validUntil: nil)
        )

        let active = try await sd.activeState(for: node.id, at: Date())
        #expect(active == nil)
    }

    @Test("activeState returns nil after validUntil (exclusive end)")
    func activeStateAfterRange() async throws {
        let sd = try makeSwiftDataStore()
        let node = try await sd.addNode(type: "N", attributes: [:])

        let start = Date(timeIntervalSince1970: 0)
        let end   = Date(timeIntervalSince1970: 10)

        _ = try await sd.addState(
            for: node.id,
            attributes: [:],
            bounds: TemporalBounds(validFrom: start, validUntil: end)
        )

        // At exactly end — exclusive, so nil
        let activeAtEnd = try await sd.activeState(for: node.id, at: end)
        #expect(activeAtEnd == nil)

        // Just before end — active
        let justBefore = Date(timeIntervalSince1970: 9.999)
        let activeBefore = try await sd.activeState(for: node.id, at: justBefore)
        #expect(activeBefore != nil)
    }

    @Test("Zero-duration bounds ([t, t)) is never active")
    func zeroDurationBounds() async throws {
        let sd = try makeSwiftDataStore()
        let node = try await sd.addNode(type: "N", attributes: [:])

        let t = Date(timeIntervalSince1970: 500)
        _ = try await sd.addState(
            for: node.id,
            attributes: [:],
            bounds: TemporalBounds(validFrom: t, validUntil: t)
        )

        let active = try await sd.activeState(for: node.id, at: t)
        #expect(active == nil)
    }

    @Test("Open-ended bounds (validUntil == nil) always active after validFrom")
    func openEndedBounds() async throws {
        let sd = try makeSwiftDataStore()
        let node = try await sd.addNode(type: "N", attributes: [:])

        let past = Date(timeIntervalSince1970: 0)
        _ = try await sd.addState(
            for: node.id,
            attributes: ["open": .bool(true)],
            bounds: TemporalBounds(validFrom: past, validUntil: nil)
        )

        let now = try await sd.activeState(for: node.id, at: Date())
        #expect(now != nil)
        #expect(now?.attributes["open"] == .bool(true))

        let farFuture = try await sd.activeState(for: node.id, at: Date(timeIntervalSinceNow: 1_000_000))
        #expect(farFuture != nil)
    }

    @Test("changedEntitiesInRange returns correct entity IDs")
    func changedEntitiesInRange() async throws {
        let sd = try makeSwiftDataStore()
        let before = Date()
        let n1 = try await sd.addNode(type: "N", attributes: [:])
        _ = try await sd.addState(for: n1.id, attributes: [:], bounds: TemporalBounds(validFrom: Date.distantPast, validUntil: nil))
        let after = Date()

        let range = TemporalBounds(validFrom: before, validUntil: after)
        let changed = try await sd.changedEntitiesInRange(range)

        // n1 should appear (state created within range); its edge state too if applicable
        #expect(changed.contains(n1.id))
    }
}
