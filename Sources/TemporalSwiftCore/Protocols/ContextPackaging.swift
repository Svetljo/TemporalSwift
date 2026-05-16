import Foundation

/// Interface for extracting a subgraph as a ``ContextSnapshot`` for LLM consumption.
///
/// Implementations traverse from a focal entity, rank by proximity and recency,
/// then prune to fit within the caller-supplied character budget.
public protocol ContextPackaging: Sendable {
    /// Produces a ``ContextSnapshot`` centred on `focalEntityID`.
    ///
    /// - Parameters:
    ///   - focalEntityID: The entity at the centre of the snapshot.
    ///   - date: Point in time for temporal filtering of edges and states.
    ///   - maxDepth: Maximum traversal depth from the focal entity.
    ///   - characterBudget: Target character budget for the serialized output.
    ///   - charsPerToken: Estimated characters per token (default 4). Used to
    ///     convert a token budget to a character budget if needed.
    ///   - edgeTypeFilter: Optional set of edge types to traverse. `nil` = all types.
    /// - Returns: A ``ContextSnapshot`` containing the pruned subgraph.
    func snapshot(
        focalEntityID: UUID,
        at date: Date,
        maxDepth: Int,
        characterBudget: Int,
        charsPerToken: Int,
        edgeTypeFilter: Set<String>?
    ) async throws -> ContextSnapshot
}
