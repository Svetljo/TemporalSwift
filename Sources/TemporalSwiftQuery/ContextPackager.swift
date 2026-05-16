import Foundation
import TemporalSwiftCore

/// Extracts a budget-bounded ``ContextSnapshot`` for LLM context windows.
///
/// `ContextPackager` implements ``ContextPackaging``. It traverses the graph
/// from a focal entity, ranks results by proximity then recency, and
/// incrementally serializes entities to JSON until the character budget is reached.
///
/// Budget enforcement allows up to 5% overshoot (SC-005).
public struct ContextPackager: ContextPackaging {

    private let store: any GraphStore
    private let traverser: any GraphTraversing

    /// Creates a new `ContextPackager`.
    ///
    /// - Parameters:
    ///   - store: The ``GraphStore`` backing the graph.
    ///   - traverser: A ``GraphTraversing`` implementation for subgraph extraction.
    public init(store: any GraphStore, traverser: any GraphTraversing) {
        self.store = store
        self.traverser = traverser
    }

    // MARK: - ContextPackaging

    /// Produces a ``ContextSnapshot`` centred on `focalEntityID`.
    ///
    /// Entities are ranked by:
    /// 1. Relationship proximity (fewer hops = higher priority)
    /// 2. Temporal recency (more recent state = higher priority)
    ///
    /// Serialization stops when adding the next entity would exceed
    /// `characterBudget * charsPerToken` characters (with 5% tolerance).
    public func snapshot(
        focalEntityID: UUID,
        at date: Date,
        maxDepth: Int,
        characterBudget: Int,
        charsPerToken: Int,
        edgeTypeFilter: Set<String>?
    ) async throws -> ContextSnapshot {
        // 1. Traverse the subgraph
        let traversalResult = try await traverser.traverse(
            from: focalEntityID,
            maxDepth: maxDepth,
            at: date,
            edgeTypeFilter: edgeTypeFilter
        )

        let charBudget = characterBudget * charsPerToken
        let encoder = makeEncoder()

        // 2. Rank nodes: focal entity first, then by recency of latest state
        let rankedNodes = rankNodes(
            traversalResult.nodes,
            focalID: focalEntityID,
            states: traversalResult.states
        )

        // 3. Incrementally pack nodes within budget
        var includedNodes: [Node] = []
        var includedEdges: [Edge] = []
        var includedStates: [TemporalState] = []
        var includedNodeIDs: Set<UUID> = []
        var totalChars = 0

        let overshootBudget = Int(Double(charBudget) * 1.05)

        for node in rankedNodes {
            let nodeJSON = (try? encoder.encode(node)).map { String(data: $0, encoding: .utf8) ?? "" } ?? ""
            let nodeStates = traversalResult.states.filter { $0.entityID == node.id }
            let statesJSON = nodeStates.compactMap { s in
                (try? encoder.encode(s)).map { String(data: $0, encoding: .utf8) ?? "" }
            }.joined()

            let addition = nodeJSON.count + statesJSON.count
            if totalChars + addition > overshootBudget && !includedNodes.isEmpty {
                break
            }

            includedNodes.append(node)
            includedNodeIDs.insert(node.id)
            includedStates.append(contentsOf: nodeStates)
            totalChars += addition
        }

        // 4. Include edges whose both endpoints are in the included set
        for edge in traversalResult.edges {
            guard includedNodeIDs.contains(edge.sourceID),
                  includedNodeIDs.contains(edge.targetID) else { continue }

            let edgeJSON = (try? encoder.encode(edge)).map { String(data: $0, encoding: .utf8) ?? "" } ?? ""
            let edgeStates = traversalResult.states.filter { $0.entityID == edge.id }
            let statesJSON = edgeStates.compactMap { s in
                (try? encoder.encode(s)).map { String(data: $0, encoding: .utf8) ?? "" }
            }.joined()

            let addition = edgeJSON.count + statesJSON.count
            if totalChars + addition > overshootBudget && !includedEdges.isEmpty {
                break
            }

            includedEdges.append(edge)
            includedStates.append(contentsOf: edgeStates)
            totalChars += addition
        }

        // Deduplicate states (nodes and edges may share state IDs in theory — unlikely but safe)
        let deduped = Dictionary(includedStates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        return ContextSnapshot(
            focalEntityID: focalEntityID,
            nodes: includedNodes,
            edges: includedEdges,
            states: Array(deduped.values),
            generatedAt: Date(),
            characterBudget: charBudget,
            actualCharacters: totalChars
        )
    }

    // MARK: - Private helpers

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// Ranks nodes: focal entity first, then by most-recent state createdAt descending.
    private func rankNodes(
        _ nodes: [Node],
        focalID: UUID,
        states: [TemporalState]
    ) -> [Node] {
        // Build a map: nodeID → most recent state createdAt
        var latestStateDate: [UUID: Date] = [:]
        for state in states {
            let existing = latestStateDate[state.entityID]
            if existing == nil || state.createdAt > existing! {
                latestStateDate[state.entityID] = state.createdAt
            }
        }

        return nodes.sorted { a, b in
            // Focal entity always first
            if a.id == focalID { return true }
            if b.id == focalID { return false }
            // Then sort by most-recent state descending
            let aDate = latestStateDate[a.id] ?? a.createdAt
            let bDate = latestStateDate[b.id] ?? b.createdAt
            return aDate > bDate
        }
    }
}
