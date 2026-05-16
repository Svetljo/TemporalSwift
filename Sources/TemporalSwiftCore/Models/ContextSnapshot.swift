import Foundation

/// A serialized extract of a subgraph designed for inclusion in an LLM context window.
///
/// A `ContextSnapshot` is produced by a ``ContextPackaging`` implementation.
/// It contains the subgraph reachable from a focal entity, pruned to fit within
/// a character budget.
public struct ContextSnapshot: Codable, Sendable {
    /// The entity at the centre of the snapshot.
    public let focalEntityID: UUID
    /// Included nodes, ordered by relevance (closest/most recent first).
    public let nodes: [Node]
    /// Included edges connecting the nodes in this snapshot.
    public let edges: [Edge]
    /// Active temporal states for the included entities at the snapshot time.
    public let states: [TemporalState]
    /// When this snapshot was produced.
    public let generatedAt: Date
    /// Target character budget supplied by the caller.
    public let characterBudget: Int
    /// Actual character count of the serialized snapshot content.
    public let actualCharacters: Int

    /// Creates a new `ContextSnapshot`.
    ///
    /// - Parameters:
    ///   - focalEntityID: The focal entity ID.
    ///   - nodes: Included nodes.
    ///   - edges: Included edges.
    ///   - states: Active temporal states.
    ///   - generatedAt: Snapshot generation timestamp.
    ///   - characterBudget: Caller-supplied character budget.
    ///   - actualCharacters: Actual serialized character count.
    public init(
        focalEntityID: UUID,
        nodes: [Node],
        edges: [Edge],
        states: [TemporalState],
        generatedAt: Date,
        characterBudget: Int,
        actualCharacters: Int
    ) {
        self.focalEntityID = focalEntityID
        self.nodes = nodes
        self.edges = edges
        self.states = states
        self.generatedAt = generatedAt
        self.characterBudget = characterBudget
        self.actualCharacters = actualCharacters
    }
}
