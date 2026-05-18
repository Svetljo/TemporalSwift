import Testing
import Foundation
@testable import TemporalSwiftCore
@testable import TemporalSwiftSQLite

@Suite("SQLite GraphStore Tests")
struct SQLiteGraphStoreTests {

    // MARK: - Node operations

    @Test("addNode: returns node with correct type and attributes")
    func addNodeReturnsCorrectNode() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let node = try await store.addNode(type: "Person", attributes: ["name": .string("Alice")])
        #expect(node.type == "Person")
        #expect(node.attributes["name"] == .string("Alice"))
    }

    @Test("node(id:): returns node when it exists")
    func nodeByIDFound() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let created = try await store.addNode(type: "Location", attributes: [:])
        let fetched = try await store.node(id: created.id)
        #expect(fetched?.id == created.id)
    }

    @Test("node(id:): returns nil for unknown ID")
    func nodeByIDNotFound() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let result = try await store.node(id: UUID())
        #expect(result == nil)
    }

    @Test("nodes(ofType:): returns only nodes of matching type")
    func nodesByType() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        _ = try await store.addNode(type: "Person", attributes: [:])
        _ = try await store.addNode(type: "Person", attributes: [:])
        _ = try await store.addNode(type: "Location", attributes: [:])
        let persons = try await store.nodes(ofType: "Person")
        #expect(persons.count == 2)
        let locations = try await store.nodes(ofType: "Location")
        #expect(locations.count == 1)
    }

    @Test("nodes(ofType:): returns empty array for unknown type")
    func nodesByTypeEmpty() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let result = try await store.nodes(ofType: "Unknown")
        #expect(result.isEmpty)
    }

    // MARK: - Temporal state operations

    @Test("addState: version numbers are monotonically increasing")
    func stateVersionsMonotonic() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let node = try await store.addNode(type: "T", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        let s1 = try await store.addState(for: node.id, attributes: [:], bounds: bounds)
        let s2 = try await store.addState(for: node.id, attributes: [:], bounds: bounds)
        let s3 = try await store.addState(for: node.id, attributes: [:], bounds: bounds)
        #expect(s1.version < s2.version)
        #expect(s2.version < s3.version)
    }

    @Test("states(for:): returns states ordered by version ascending")
    func statesOrderedByVersion() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let node = try await store.addNode(type: "T", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        _ = try await store.addState(for: node.id, attributes: [:], bounds: bounds)
        _ = try await store.addState(for: node.id, attributes: [:], bounds: bounds)
        _ = try await store.addState(for: node.id, attributes: [:], bounds: bounds)
        let fetched = try await store.states(for: node.id)
        for i in 0..<(fetched.count - 1) {
            #expect(fetched[i].version < fetched[i + 1].version)
        }
    }

    @Test("activeState: highest version wins when multiple states overlap")
    func activeStateHighestVersionWins() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let node = try await store.addNode(type: "T", attributes: [:])
        let now = Date(timeIntervalSince1970: 1_000_000)
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        _ = try await store.addState(for: node.id, attributes: ["v": .int(1)], bounds: bounds)
        let s2 = try await store.addState(for: node.id, attributes: ["v": .int(2)], bounds: bounds)
        let active = try await store.activeState(for: node.id, at: now)
        #expect(active?.id == s2.id)
        #expect(active?.attributes["v"] == .int(2))
    }

    @Test("activeState: returns nil when no state is active at date")
    func activeStateNoneActive() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let node = try await store.addNode(type: "T", attributes: [:])
        let past = TemporalBounds(
            validFrom: Date(timeIntervalSince1970: 0),
            validUntil: Date(timeIntervalSince1970: 500)
        )
        _ = try await store.addState(for: node.id, attributes: [:], bounds: past)
        let result = try await store.activeState(for: node.id, at: Date(timeIntervalSince1970: 1000))
        #expect(result == nil)
    }

    @Test("append-only: both states preserved after update")
    func appendOnlyHistoryPreserved() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let node = try await store.addNode(type: "Person", attributes: [:])
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)

        _ = try await store.addState(
            for: node.id,
            attributes: ["city": .string("New York")],
            bounds: TemporalBounds(validFrom: t0, validUntil: t1)
        )
        _ = try await store.addState(
            for: node.id,
            attributes: ["city": .string("Milan")],
            bounds: TemporalBounds(validFrom: t1, validUntil: nil)
        )

        let allStates = try await store.states(for: node.id)
        #expect(allStates.count == 2)

        let oldState = try await store.activeState(for: node.id, at: Date(timeIntervalSince1970: 500))
        #expect(oldState?.attributes["city"] == .string("New York"))

        let newState = try await store.activeState(for: node.id, at: t2)
        #expect(newState?.attributes["city"] == .string("Milan"))
    }

    // MARK: - AttributeValue round-trips

    @Test("AttributeValue round-trips all variants through SQLite")
    func attributeValueRoundTrips() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let now = Date(timeIntervalSince1970: 1_000_000)
        let attrs: [String: AttributeValue] = [
            "str":  .string("hello"),
            "int":  .int(42),
            "dbl":  .double(3.14),
            "bool": .bool(true),
            "date": .date(now),
            "null": .null
        ]
        let node = try await store.addNode(type: "T", attributes: attrs)
        let fetched = try await store.node(id: node.id)
        #expect(fetched?.attributes["str"] == .string("hello"))
        #expect(fetched?.attributes["int"] == .int(42))
        #expect(fetched?.attributes["bool"] == .bool(true))
        #expect(fetched?.attributes["null"] == .null)
        if case .double(let v) = fetched?.attributes["dbl"] {
            #expect(abs(v - 3.14) < 0.0001)
        } else {
            Issue.record("Expected .double attribute")
        }
    }

    // MARK: - changedEntitiesInRange

    @Test("changedEntitiesInRange returns correct entity IDs")
    func changedEntitiesInRange() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let t0 = Date(timeIntervalSinceNow: -10)
        let t1 = Date(timeIntervalSinceNow: +10)

        let node = try await store.addNode(type: "T", attributes: [:])
        _ = try await store.addState(
            for: node.id,
            attributes: [:],
            bounds: TemporalBounds(validFrom: t0, validUntil: nil)
        )

        let range = TemporalBounds(validFrom: t0, validUntil: t1)
        let ids = try await store.changedEntitiesInRange(range)
        #expect(ids.contains(node.id))
    }
}
