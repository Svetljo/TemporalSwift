import Foundation
import SwiftData
import TemporalSwiftCore

/// SwiftData persistence model for ``Node``.
///
/// Internal to `TemporalSwiftPersistence`. Consumers interact only with
/// the public ``Node`` value type returned by ``SwiftDataGraphStore``.
@Model
final class PersistedNode {
    var id: UUID
    var type: String
    /// JSON-encoded `[String: AttributeValue]`.
    var attributesData: Data
    var createdAt: Date

    init(id: UUID, type: String, attributesData: Data, createdAt: Date) {
        self.id = id
        self.type = type
        self.attributesData = attributesData
        self.createdAt = createdAt
    }

    /// Converts this persistence model to the public ``Node`` value type.
    func toNode() throws -> Node {
        let attributes = try JSONDecoder().decode([String: AttributeValue].self, from: attributesData)
        return Node(id: id, type: type, attributes: attributes, createdAt: createdAt)
    }

    /// Creates a `PersistedNode` from a public ``Node``.
    static func from(_ node: Node) throws -> PersistedNode {
        let data = try JSONEncoder().encode(node.attributes)
        return PersistedNode(id: node.id, type: node.type, attributesData: data, createdAt: node.createdAt)
    }
}
