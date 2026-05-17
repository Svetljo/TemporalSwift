import Foundation
import SwiftData
import TemporalSwiftCore

/// SwiftData persistence model for ``TemporalState``.
///
/// `TemporalBounds` is flattened into `validFrom` + `validUntil` columns to
/// allow future predicate-based temporal queries at the SQLite level.
///
/// Internal to `TemporalSwiftPersistence`. Consumers interact only with
/// the public ``TemporalState`` value type returned by ``SwiftDataGraphStore``.
@Model
final class PersistedTemporalState {
    var id: UUID
    var entityID: UUID
    var validFrom: Date
    var validUntil: Date?
    /// JSON-encoded `[String: AttributeValue]`.
    var attributesData: Data
    var version: UInt64
    var createdAt: Date

    init(
        id: UUID,
        entityID: UUID,
        validFrom: Date,
        validUntil: Date?,
        attributesData: Data,
        version: UInt64,
        createdAt: Date
    ) {
        self.id = id
        self.entityID = entityID
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.attributesData = attributesData
        self.version = version
        self.createdAt = createdAt
    }

    /// Returns `true` if the given date falls within `[validFrom, validUntil)`.
    func isActive(at date: Date) -> Bool {
        guard date >= validFrom else { return false }
        if let until = validUntil { return date < until }
        return true
    }

    /// Converts this persistence model to the public ``TemporalState`` value type.
    func toTemporalState() throws -> TemporalState {
        let attributes = try JSONDecoder().decode([String: AttributeValue].self, from: attributesData)
        let bounds = TemporalBounds(validFrom: validFrom, validUntil: validUntil)
        return TemporalState(
            id: id,
            entityID: entityID,
            bounds: bounds,
            attributes: attributes,
            version: version,
            createdAt: createdAt
        )
    }

    /// Creates a `PersistedTemporalState` from a public ``TemporalState``.
    static func from(_ state: TemporalState) throws -> PersistedTemporalState {
        let data = try JSONEncoder().encode(state.attributes)
        return PersistedTemporalState(
            id: state.id,
            entityID: state.entityID,
            validFrom: state.bounds.validFrom,
            validUntil: state.bounds.validUntil,
            attributesData: data,
            version: state.version,
            createdAt: state.createdAt
        )
    }
}
