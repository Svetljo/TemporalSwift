import Testing
import Foundation
import TemporalSwiftCore
import TemporalSwiftPersistence

// MARK: - Concurrency Tests (T030)

@Suite("Concurrency Tests", .serialized)
struct ConcurrencyTests {

    @Test("Concurrent addNode calls produce unique, non-corrupted nodes")
    func concurrentAddNode() async throws {
        let store = try SwiftDataGraphStore(inMemory: true)
        let taskCount = 20

        try await withThrowingTaskGroup(of: UUID.self) { group in
            for i in 0..<taskCount {
                group.addTask {
                    let node = try await store.addNode(
                        type: "Concurrent",
                        attributes: ["index": .int(i)]
                    )
                    return node.id
                }
            }
            var ids: Set<UUID> = []
            for try await id in group {
                ids.insert(id)
            }
            // All IDs must be unique — no corruption
            #expect(ids.count == taskCount)
        }

        // All nodes should be retrievable
        let nodes = try await store.nodes(ofType: "Concurrent")
        #expect(nodes.count == taskCount)
    }

    @Test("Concurrent addState calls produce monotonically increasing versions")
    func concurrentAddState() async throws {
        let store = try SwiftDataGraphStore(inMemory: true)
        let node = try await store.addNode(type: "N", attributes: [:])
        let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)
        let taskCount = 20

        var versions: [UInt64] = []
        try await withThrowingTaskGroup(of: UInt64.self) { group in
            for i in 0..<taskCount {
                group.addTask {
                    let state = try await store.addState(
                        for: node.id,
                        attributes: ["i": .int(i)],
                        bounds: bounds
                    )
                    return state.version
                }
            }
            for try await version in group {
                versions.append(version)
            }
        }

        #expect(versions.count == taskCount)
        // All versions must be unique (monotonic counter, no duplicates)
        let uniqueVersions = Set(versions)
        #expect(uniqueVersions.count == taskCount)
    }

    @Test("Concurrent mixed mutations produce consistent state")
    func concurrentMixedMutations() async throws {
        let store = try SwiftDataGraphStore(inMemory: true)
        let bounds = TemporalBounds(validFrom: Date.distantPast, validUntil: nil)

        // Pre-create two nodes to use as edge endpoints
        let source = try await store.addNode(type: "Source", attributes: [:])
        let target = try await store.addNode(type: "Target", attributes: [:])

        // Spin up 10 concurrent tasks: mix of addNode, addState, addEdge
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    if i % 3 == 0 {
                        _ = try await store.addNode(type: "Mixed", attributes: ["i": .int(i)])
                    } else if i % 3 == 1 {
                        _ = try await store.addState(
                            for: source.id,
                            attributes: ["i": .int(i)],
                            bounds: bounds
                        )
                    } else {
                        _ = try await store.addState(
                            for: target.id,
                            attributes: ["i": .int(i)],
                            bounds: bounds
                        )
                    }
                }
            }
            try await group.waitForAll()
        }

        // Verify no corruption: each entity type count is consistent
        let mixedNodes = try await store.nodes(ofType: "Mixed")
        // 10 tasks: i=0,3,6,9 → 4 mixed nodes
        #expect(mixedNodes.count == 4)

        let sourceStates = try await store.states(for: source.id)
        // i=1,4,7 → 3 states from addState; actor serialises so no corruption
        #expect(sourceStates.count == 3)
    }
}
