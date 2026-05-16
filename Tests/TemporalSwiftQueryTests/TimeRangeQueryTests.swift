import Testing
import Foundation
@testable import TemporalSwiftCore
@testable import TemporalSwiftStorage
@testable import TemporalSwiftQuery

@Suite("Time-Range Query Tests")
struct TimeRangeQueryTests {

    private func makeStore() -> InMemoryGraphStore { InMemoryGraphStore() }

    @Test("query(from:to:): returns states overlapping the range")
    func queryRangeOverlap() async throws {
        let store = makeStore()
        let node = try await store.addNode(type: "T", attributes: [:])
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        let t3 = Date(timeIntervalSince1970: 3000)

        _ = try await store.addState(
            for: node.id,
            attributes: ["era": .string("ancient")],
            bounds: TemporalBounds(validFrom: t0, validUntil: t1)
        )
        _ = try await store.addState(
            for: node.id,
            attributes: ["era": .string("modern")],
            bounds: TemporalBounds(validFrom: t1, validUntil: t3)
        )
        _ = try await store.addState(
            for: node.id,
            attributes: ["era": .string("future")],
            bounds: TemporalBounds(validFrom: t3, validUntil: nil)
        )

        let engine = TemporalQueryEngine(store: store)
        // Range [t1, t2) should overlap "modern" and not "future"
        let results = try await engine.query(entityID: node.id, from: t1, to: t2)
        let eras = results.compactMap { $0.attributes["era"] }
        #expect(eras.contains(.string("modern")))
        #expect(!eras.contains(.string("future")))
    }

    @Test("query(from:to:): disjoint range returns nothing")
    func queryDisjointRange() async throws {
        let store = makeStore()
        let node = try await store.addNode(type: "T", attributes: [:])
        // State valid only in [0, 100)
        _ = try await store.addState(
            for: node.id,
            attributes: [:],
            bounds: TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: Date(timeIntervalSince1970: 100))
        )
        let engine = TemporalQueryEngine(store: store)
        // Query range [200, 300) does not overlap [0, 100)
        let results = try await engine.query(
            entityID: node.id,
            from: Date(timeIntervalSince1970: 200),
            to: Date(timeIntervalSince1970: 300)
        )
        #expect(results.isEmpty)
    }

    @Test("query(from:to:): range with no facts returns empty")
    func queryRangeNoFacts() async throws {
        let store = makeStore()
        let node = try await store.addNode(type: "T", attributes: [:])
        let engine = TemporalQueryEngine(store: store)
        let results = try await engine.query(
            entityID: node.id,
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 1000)
        )
        #expect(results.isEmpty)
    }

    @Test("changedEntities: detects transitions within range")
    func changedEntitiesDetected() async throws {
        let store = makeStore()
        let n1 = try await store.addNode(type: "A", attributes: [:])
        let n2 = try await store.addNode(type: "B", attributes: [:])

        let rangeStart = Date()
        _ = try await store.addState(
            for: n1.id,
            attributes: [:],
            bounds: TemporalBounds(validFrom: rangeStart, validUntil: nil)
        )
        let rangeEnd = Date().addingTimeInterval(1)

        let engine = TemporalQueryEngine(store: store)
        let changed = try await engine.changedEntities(from: rangeStart, to: rangeEnd)
        // n1 had a state created in range; n2 did not
        #expect(changed.contains(n1.id))
        #expect(!changed.contains(n2.id))
    }

    @Test("changedEntities: no changes outside range")
    func changedEntitiesNoneOutsideRange() async throws {
        let store = makeStore()
        let node = try await store.addNode(type: "T", attributes: [:])
        _ = try await store.addState(
            for: node.id,
            attributes: [:],
            bounds: TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        )
        let engine = TemporalQueryEngine(store: store)
        // Query a future range where no states were created
        let futureStart = Date(timeIntervalSince1970: 99_999_999)
        let futureEnd = Date(timeIntervalSince1970: 100_000_000)
        let changed = try await engine.changedEntities(from: futureStart, to: futureEnd)
        #expect(changed.isEmpty)
    }
}
