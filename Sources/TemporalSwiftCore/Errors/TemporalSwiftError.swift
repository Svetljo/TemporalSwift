import Foundation

/// Errors thrown by TemporalSwift operations.
public enum TemporalSwiftError: Error, Sendable {
    /// No node with the given ID exists in the store.
    case nodeNotFound(id: UUID)
    /// No edge with the given ID exists in the store.
    case edgeNotFound(id: UUID)
    /// No temporal state with the given ID exists in the store.
    case stateNotFound(id: UUID)
    /// No episode with the given ID exists in the store.
    case episodeNotFound(id: UUID)
    /// The supplied edge type string is invalid (e.g., empty).
    case invalidEdgeType(String)
    /// Adding this edge would create a cycle in a constrained edge type.
    case cycleViolation(edgeType: String, sourceID: UUID, targetID: UUID)
    /// The supplied `TemporalBounds` are logically invalid.
    case invalidTemporalBounds(reason: String)
    /// An edge references a node ID that does not exist in the store.
    case referentialIntegrityViolation(missingNodeID: UUID)
    /// The serialized snapshot exceeds the requested character budget.
    case budgetExceeded(requested: Int, actual: Int)
}
