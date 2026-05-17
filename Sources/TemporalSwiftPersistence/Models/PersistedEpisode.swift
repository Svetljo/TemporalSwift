import Foundation
import SwiftData
import TemporalSwiftCore

/// SwiftData persistence model for ``Episode``.
///
/// `stateIDs` is stored as a JSON-encoded `[UUID]` blob since SwiftData
/// does not support arrays of non-model types natively in all versions.
///
/// Internal to `TemporalSwiftPersistence`. Consumers interact only with
/// the public ``Episode`` value type returned by ``SwiftDataGraphStore``.
@Model
final class PersistedEpisode {
    var id: UUID
    var desc: String?
    /// JSON-encoded `[UUID]`.
    var stateIDsData: Data
    var timestamp: Date

    init(id: UUID, desc: String?, stateIDsData: Data, timestamp: Date) {
        self.id = id
        self.desc = desc
        self.stateIDsData = stateIDsData
        self.timestamp = timestamp
    }

    /// Converts this persistence model to the public ``Episode`` value type.
    func toEpisode() throws -> Episode {
        let stateIDs = try JSONDecoder().decode([UUID].self, from: stateIDsData)
        return Episode(id: id, description: desc, stateIDs: stateIDs, timestamp: timestamp)
    }

    /// Creates a `PersistedEpisode` from a public ``Episode``.
    static func from(_ episode: Episode) throws -> PersistedEpisode {
        let data = try JSONEncoder().encode(episode.stateIDs)
        return PersistedEpisode(
            id: episode.id,
            desc: episode.description,
            stateIDsData: data,
            timestamp: episode.timestamp
        )
    }
}
