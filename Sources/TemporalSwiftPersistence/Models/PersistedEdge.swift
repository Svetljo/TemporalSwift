import Foundation
import SwiftData
import TemporalSwiftCore

/// SwiftData persistence model for ``Edge``.
///
/// Internal to `TemporalSwiftPersistence`. Consumers interact only with
/// the public ``Edge`` value type returned by ``SwiftDataGraphStore``.
@Model
final class PersistedEdge {
    var id: UUID
    var type: String
    var sourceID: UUID
    var targetID: UUID
    /// JSON-encoded `[String: AttributeValue]`.
    var attributesData: Data
    var createdAt: Date

    init(
        id: UUID,
        type: String,
        sourceID: UUID,
        targetID: UUID,
        attributesData: Data,
        createdAt: Date
    ) {
        self.id = id
        self.type = type
        self.sourceID = sourceID
        self.targetID = targetID
        self.attributesData = attributesData
        self.createdAt = createdAt
    }

    /// Converts this persistence model to the public ``Edge`` value type.
    func toEdge() throws -> Edge {
        let attributes = try JSONDecoder().decode([String: AttributeValue].self, from: attributesData)
        return Edge(
            id: id,
            type: type,
            sourceID: sourceID,
            targetID: targetID,
            attributes: attributes,
            createdAt: createdAt
        )
    }

    /// Creates a `PersistedEdge` from a public ``Edge``.
    static func from(_ edge: Edge) throws -> PersistedEdge {
        let data = try JSONEncoder().encode(edge.attributes)
        return PersistedEdge(
            id: edge.id,
            type: edge.type,
            sourceID: edge.sourceID,
            targetID: edge.targetID,
            attributesData: data,
            createdAt: edge.createdAt
        )
    }
}
