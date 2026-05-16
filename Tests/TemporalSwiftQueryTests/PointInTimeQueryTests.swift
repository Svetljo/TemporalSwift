import Testing
import Foundation
@testable import TemporalSwiftCore
@testable import TemporalSwiftStorage
@testable import TemporalSwiftQuery

@Suite("Point-In-Time Query Tests")
struct PointInTimeQueryTests {

    private func makeStore() -> InMemoryGraphStore { InMemoryGraphStore() }

    @Test("query(at:): returns active state at query date")
    func queryActiveState() async throws {
        let store = makeStore()
        let node = try await store.addNode(type: "T", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        _ = try await store.addState(for: node.id, attributes: ["v": .string("active")], bounds: bounds)
        let engine = TemporalQueryEngine(store: store)
        let result = try await engine.query(entityID: node.id, at: Date(timeIntervalSince1970: 1000))
        #expect(result?.attributes["v"] == .string("active"))
    }

    @Test("query(at:): returns nil when queried before any state")
    func queryBeforeAnyState() async throws {
        let store = makeStore()
        let node = try await store.addNode(type: "T", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 1000), validUntil: nil)
        _ = try await store.addState(for: node.id, attributes: [:], bounds: bounds)
        let engine = TemporalQueryEngine(store: store)
        let result = try await engine.query(entityID: node.id, at: Date(timeIntervalSince1970: 500))
        #expect(result == nil)
    }

    @Test("query(at:): returns correct historical state at past date")
    func queryPastState() async throws {
        let store = makeStore()
        let node = try await store.addNode(type: "T", attributes: [:])
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 1000)

        _ = try await store.addState(
            for: node.id,
            attributes: ["phase": .string("old")],
            bounds: TemporalBounds(validFrom: t0, validUntil: t1)
        )
        _ = try await store.addState(
            for: node.id,
            attributes: ["phase": .string("new")],
            bounds: TemporalBounds(validFrom: t1, validUntil: nil)
        )
        let engine = TemporalQueryEngine(store: store)
        let old = try await engine.query(entityID: node.id, at: Date(timeIntervalSince1970: 500))
        #expect(old?.attributes["phase"] == .string("old"))
        let new = try await engine.query(entityID: node.id, at: Date(timeIntervalSince1970: 2000))
        #expect(new?.attributes["phase"] == .string("new"))
    }

    @Test("query(at:): overlapping states — highest version wins")
    func queryOverlappingStatesHighestVersionWins() async throws {
        let store = makeStore()
        let node = try await store.addNode(type: "T", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        _ = try await store.addState(for: node.id, attributes: ["v": .int(1)], bounds: bounds)
        let s2 = try await store.addState(for: node.id, attributes: ["v": .int(2)], bounds: bounds)
        let engine = TemporalQueryEngine(store: store)
        let result = try await engine.query(entityID: node.id, at: Date(timeIntervalSince1970: 500))
        #expect(result?.id == s2.id)
    }

    @Test("query(at:): zero-duration bounds contains nothing")
    func queryZeroDuration() async throws {
        let store = makeStore()
        let node = try await store.addNode(type: "T", attributes: [:])
        let t = Date(timeIntervalSince1970: 1000)
        _ = try await store.addState(
            for: node.id,
            attributes: [:],
            bounds: TemporalBounds(validFrom: t, validUntil: t)
        )
        let engine = TemporalQueryEngine(store: store)
        let result = try await engine.query(entityID: node.id, at: t)
        #expect(result == nil)
    }

    @Test("query(at:): far-future date")
    func queryFarFuture() async throws {
        let store = makeStore()
        let node = try await store.addNode(type: "T", attributes: [:])
        _ = try await store.addState(
            for: node.id,
            attributes: ["tag": .string("exists")],
            bounds: TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        )
        let engine = TemporalQueryEngine(store: store)
        let farFuture = Date(timeIntervalSince1970: 32_503_680_000)
        let result = try await engine.query(entityID: node.id, at: farFuture)
        #expect(result?.attributes["tag"] == .string("exists"))
    }
}
