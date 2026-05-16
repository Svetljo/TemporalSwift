import Foundation

/// The result of a graph traversal operation.
///
/// Contains all nodes, edges, and active temporal states discovered
/// within the requested depth and time constraints.
public struct TraversalResult: Codable, Sendable {
    /// All nodes discovered during traversal (including the start node).
    public let nodes: [Node]
    /// All edges traversed.
    public let edges: [Edge]
    /// Active temporal states for the discovered nodes and edges at the query time.
    public let states: [TemporalState]

    /// Creates a new `TraversalResult`.
    ///
    /// - Parameters:
    ///   - nodes: Discovered nodes.
    ///   - edges: Traversed edges.
    ///   - states: Active temporal states.
    public init(nodes: [Node], edges: [Edge], states: [TemporalState]) {
        self.nodes = nodes
        self.edges = edges
        self.states = states
    }
}

/// Interface for BFS/DFS graph traversal with temporal and type filtering.
public protocol GraphTraversing: Sendable {
    /// Traverses the graph from the given node up to `maxDepth` hops.
    ///
    /// - Parameters:
    ///   - nodeID: Starting node for traversal.
    ///   - maxDepth: Maximum number of hops from the start node.
    ///   - date: Optional point in time for temporal filtering.
    ///     Only edges whose bounds are active at this date are followed.
    ///     Pass `nil` to traverse all edges regardless of temporal state.
    ///   - edgeTypeFilter: Optional set of edge type labels to follow.
    ///     Pass `nil` to follow all edge types.
    /// - Returns: A ``TraversalResult`` with all reachable nodes, edges, and states.
    func traverse(
        from nodeID: UUID,
        maxDepth: Int,
        at date: Date?,
        edgeTypeFilter: Set<String>?
    ) async throws -> TraversalResult
}
