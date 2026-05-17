import Foundation
import SwiftData

/// Singleton SwiftData model that tracks the monotonic version counter and
/// the set of edge types that require acyclic (DAG) structure.
///
/// There is exactly one instance of this model per `ModelContainer`. It is
/// created on first access and updated in place. All mutations are performed
/// within the ``SwiftDataGraphStore`` actor and followed by an explicit
/// `modelContext.save()` to ensure durability.
///
/// Internal to `TemporalSwiftPersistence`.
@Model
final class PersistedStoreConfig {
    /// Last assigned version number for ``PersistedTemporalState`` records.
    var versionCounter: UInt64
    /// JSON-encoded `[String]` (sorted array representing a `Set<String>`).
    var acyclicEdgeTypesData: Data

    init(versionCounter: UInt64, acyclicEdgeTypesData: Data) {
        self.versionCounter = versionCounter
        self.acyclicEdgeTypesData = acyclicEdgeTypesData
    }

    // MARK: - Helpers

    /// Decodes the persisted acyclic edge types into a `Set<String>`.
    func acyclicEdgeTypes() throws -> Set<String> {
        let array = try JSONDecoder().decode([String].self, from: acyclicEdgeTypesData)
        return Set(array)
    }

    /// Encodes and stores the given set of acyclic edge types.
    func setAcyclicEdgeTypes(_ types: Set<String>) throws {
        acyclicEdgeTypesData = try JSONEncoder().encode(Array(types).sorted())
    }

    // MARK: - Factory

    /// Creates a default config with counter = 0 and no constraints.
    static func makeDefault() throws -> PersistedStoreConfig {
        let emptyData = try JSONEncoder().encode([String]())
        return PersistedStoreConfig(versionCounter: 0, acyclicEdgeTypesData: emptyData)
    }
}
