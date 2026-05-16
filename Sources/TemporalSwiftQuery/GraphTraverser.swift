import Foundation
import TemporalSwiftCore

/// BFS-based graph traversal with temporal and edge-type filtering.
///
/// `GraphTraverser` implements ``GraphTraversing``. It traverses the graph
/// breadth-first from a starting node, optionally filtering by point-in-time
/// temporal activity and edge type.
public struct GraphTraverser: GraphTraversing {

    private let store: any GraphStore

    /// Creates a new `GraphTraverser` backed by the given store.
    ///
    /// - Parameter store: The ``GraphStore`` to traverse.
    public init(store: any GraphStore) {
        self.store = store
    }

    // MARK: - GraphTraversing

    /// Traverses the graph BFS from `nodeID` up to `maxDepth` hops.
    ///
    /// - Parameters:
    ///   - nodeID: Starting node.
    ///   - maxDepth: Maximum hops. `0` returns only the start node.
    ///   - date: Optional temporal filter. Only edges with an active state at
    ///     this date are followed. Pass `nil` to follow all edges.
    ///   - edgeTypeFilter: Optional set of edge types to follow. `nil` = all types.
    /// - Throws: ``TemporalSwiftError/nodeNotFound(id:)`` if the start node does not exist.
    public func traverse(
        from nodeID: UUID,
        maxDepth: Int,
        at date: Date?,
        edgeTypeFilter: Set<String>?
    ) async throws -> TraversalResult {
        guard let startNode = try await store.node(id: nodeID) else {
            throw TemporalSwiftError.nodeNotFound(id: nodeID)
        }

        var visitedNodes: [UUID: Node] = [nodeID: startNode]
        var visitedEdges: [UUID: Edge] = [:]
        var collectedStates: [UUID: TemporalState] = [:]

        // Collect active states for the start node if temporal filtering requested
        if let date {
            if let state = try await store.activeState(for: nodeID, at: date) {
                collectedStates[state.id] = state
            }
        }

        // BFS frontier: (nodeID, currentDepth)
        var frontier: [(UUID, Int)] = [(nodeID, 0)]

        while !frontier.isEmpty {
            var nextFrontier: [(UUID, Int)] = []
            for (currentID, depth) in frontier {
                guard depth < maxDepth else { continue }

                var outgoing = try await store.edges(from: currentID)

                // Apply edge type filter
                if let filter = edgeTypeFilter {
                    outgoing = outgoing.filter { filter.contains($0.type) }
                }

                // Apply temporal filter: only follow edges active at the given date
                if let date {
                    var temporallyActive: [Edge] = []
                    for edge in outgoing {
                        if let _ = try await store.activeState(for: edge.id, at: date) {
                            temporallyActive.append(edge)
                        }
                    }
                    outgoing = temporallyActive
                }

                for edge in outgoing {
                    visitedEdges[edge.id] = edge

                    // Collect edge temporal state
                    if let date {
                        if let state = try await store.activeState(for: edge.id, at: date) {
                            collectedStates[state.id] = state
                        }
                    }

                    let targetID = edge.targetID
                    if visitedNodes[targetID] == nil {
                        if let targetNode = try await store.node(id: targetID) {
                            visitedNodes[targetID] = targetNode

                            // Collect target node temporal state
                            if let date {
                                if let state = try await store.activeState(for: targetID, at: date) {
                                    collectedStates[state.id] = state
                                }
                            }

                            nextFrontier.append((targetID, depth + 1))
                        }
                    }
                }
            }
            frontier = nextFrontier
        }

        return TraversalResult(
            nodes: Array(visitedNodes.values),
            edges: Array(visitedEdges.values),
            states: Array(collectedStates.values)
        )
    }
}
