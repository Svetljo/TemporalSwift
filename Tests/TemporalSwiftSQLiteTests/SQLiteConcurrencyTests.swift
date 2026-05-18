import Testing
import Foundation
@testable import TemporalSwiftCore
@testable import TemporalSwiftSQLite

@Suite("SQLite Concurrency Tests")
struct SQLiteConcurrencyTests {

    @Test("10 concurrent tasks adding nodes produce zero data corruption")
    func concurrentNodeAdds() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let taskCount = 10
        let nodesPerTask = 10

        try await withThrowingTaskGroup(of: [Node].self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    var created: [Node] = []
                    for i in 0..<nodesPerTask {
                        let node = try await store.addNode(
                            type: "Person",
                            attributes: ["index": .int(i)]
                        )
                        created.append(node)
                    }
                    return created
                }
            }
            var allNodes: [Node] = []
            for try await batch in group {
                allNodes.append(contentsOf: batch)
            }
            let ids = Set(allNodes.map(\.id))
            #expect(ids.count == taskCount * nodesPerTask)
        }
    }

    @Test("10 concurrent tasks adding states produce unique version numbers")
    func concurrentStateAdds() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let node = try await store.addNode(type: "T", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)

        try await withThrowingTaskGroup(of: [TemporalState].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    var created: [TemporalState] = []
                    for _ in 0..<5 {
                        let s = try await store.addState(for: node.id, attributes: [:], bounds: bounds)
                        created.append(s)
                    }
                    return created
                }
            }
            var allStates: [TemporalState] = []
            for try await batch in group {
                allStates.append(contentsOf: batch)
            }
            let versions = allStates.map(\.version)
            let uniqueVersions = Set(versions)
            #expect(uniqueVersions.count == versions.count,
                "Found duplicate versions: \(versions.count - uniqueVersions.count) duplicates")
        }
    }

    @Test("Concurrent edge and node adds do not corrupt referential integrity")
    func concurrentEdgeAndNodeAdds() async throws {
        let store = try SQLiteGraphStore(path: ":memory:")
        let nodes = try await withThrowingTaskGroup(of: Node.self, returning: [Node].self) { group in
            for _ in 0..<5 {
                group.addTask { try await store.addNode(type: "N", attributes: [:]) }
            }
            var result: [Node] = []
            for try await n in group { result.append(n) }
            return result
        }

        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        var edgeCount = 0
        try await withThrowingTaskGroup(of: Int.self) { group in
            for i in 0..<nodes.count {
                let src = nodes[i]
                let tgt = nodes[(i + 1) % nodes.count]
                group.addTask {
                    _ = try await store.addEdge(
                        type: "link",
                        sourceID: src.id,
                        targetID: tgt.id,
                        attributes: [:],
                        bounds: bounds
                    )
                    return 1
                }
            }
            for try await count in group { edgeCount += count }
        }
        #expect(edgeCount == nodes.count)
    }
}
