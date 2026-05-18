import Testing
import Foundation
@testable import TemporalSwiftCore
@testable import TemporalSwiftSQLite

@Suite("SQLite Performance Tests")
struct SQLitePerformanceTests {

    /// Baseline performance test: 1,000 nodes + 5,000 temporal states.
    ///
    /// Numbers are intentionally modest to run in CI without timeout.
    /// Scale to 10K/100K manually when validating US3.
    @Test("Insert 1000 nodes and 5000 states, then query completes without timeout")
    func insertAndQueryAtScale() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)

        // Insert 1000 nodes
        var nodeIDs: [UUID] = []
        for _ in 0..<1000 {
            let n = try await store.addNode(type: "T", attributes: ["k": .string("v")])
            nodeIDs.append(n.id)
        }

        // Insert 5 states per node = 5000 states
        for id in nodeIDs {
            for _ in 0..<5 {
                _ = try await store.addState(for: id, attributes: ["v": .int(1)], bounds: bounds)
            }
        }

        // Query: activeState for last node — exercises entity+version index
        let queryDate = Date(timeIntervalSince1970: 1_000_000)
        let lastID = nodeIDs.last!
        let active = try await store.activeState(for: lastID, at: queryDate)
        #expect(active != nil)

        // Query: all states for first node
        let firstStates = try await store.states(for: nodeIDs[0])
        #expect(firstStates.count == 5)

        // Query: nodes of type T
        let allT = try await store.nodes(ofType: "T")
        #expect(allT.count == 1000)

        // Query: changedEntitiesInRange
        let range = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        let changed = try await store.changedEntitiesInRange(range)
        #expect(changed.count == 1000)
    }
}
