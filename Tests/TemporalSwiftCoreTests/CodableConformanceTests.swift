import Testing
import Foundation
@testable import TemporalSwiftCore

@Suite("Codable Conformance Tests")
struct CodableConformanceTests {

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Node

    @Test("Node: Codable round-trip")
    func nodeRoundTrip() throws {
        let node = Node(
            id: UUID(),
            type: "Person",
            attributes: ["name": .string("Alice"), "age": .int(30)],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try makeEncoder().encode(node)
        let decoded = try makeDecoder().decode(Node.self, from: data)
        #expect(decoded.id == node.id)
        #expect(decoded.type == node.type)
        #expect(decoded.attributes == node.attributes)
    }

    // MARK: - Edge

    @Test("Edge: Codable round-trip")
    func edgeRoundTrip() throws {
        let srcID = UUID()
        let tgtID = UUID()
        let edge = Edge(
            id: UUID(),
            type: "knows",
            sourceID: srcID,
            targetID: tgtID,
            attributes: ["since": .int(2020)],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try makeEncoder().encode(edge)
        let decoded = try makeDecoder().decode(Edge.self, from: data)
        #expect(decoded.id == edge.id)
        #expect(decoded.type == edge.type)
        #expect(decoded.sourceID == srcID)
        #expect(decoded.targetID == tgtID)
        #expect(decoded.attributes == edge.attributes)
    }

    // MARK: - TemporalState

    @Test("TemporalState: Codable round-trip")
    func temporalStateRoundTrip() throws {
        let state = TemporalState(
            id: UUID(),
            entityID: UUID(),
            bounds: TemporalBounds(
                validFrom: Date(timeIntervalSince1970: 1_000_000),
                validUntil: Date(timeIntervalSince1970: 2_000_000)
            ),
            attributes: ["status": .string("active")],
            version: 7,
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let data = try makeEncoder().encode(state)
        let decoded = try makeDecoder().decode(TemporalState.self, from: data)
        #expect(decoded.id == state.id)
        #expect(decoded.entityID == state.entityID)
        #expect(decoded.version == state.version)
        #expect(decoded.attributes == state.attributes)
    }

    // MARK: - Episode

    @Test("Episode: Codable round-trip")
    func episodeRoundTrip() throws {
        let episode = Episode(
            id: UUID(),
            description: "Test episode",
            stateIDs: [UUID(), UUID()],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try makeEncoder().encode(episode)
        let decoded = try makeDecoder().decode(Episode.self, from: data)
        #expect(decoded.id == episode.id)
        #expect(decoded.description == episode.description)
        #expect(decoded.stateIDs == episode.stateIDs)
    }

    // MARK: - ContextSnapshot

    @Test("ContextSnapshot: Codable round-trip")
    func contextSnapshotRoundTrip() throws {
        let nodeID = UUID()
        let node = Node(id: nodeID, type: "Person", attributes: [:], createdAt: Date(timeIntervalSince1970: 1_000))
        let snapshot = ContextSnapshot(
            focalEntityID: nodeID,
            nodes: [node],
            edges: [],
            states: [],
            generatedAt: Date(timeIntervalSince1970: 2_000),
            characterBudget: 8000,
            actualCharacters: 100
        )
        let data = try makeEncoder().encode(snapshot)
        let decoded = try makeDecoder().decode(ContextSnapshot.self, from: data)
        #expect(decoded.focalEntityID == snapshot.focalEntityID)
        #expect(decoded.characterBudget == 8000)
        #expect(decoded.actualCharacters == 100)
        #expect(decoded.nodes.count == 1)
    }

    // MARK: - TemporalBounds with nil validUntil

    @Test("TemporalBounds: nil validUntil round-trips correctly")
    func boundsNilUntilRoundTrip() throws {
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 0), validUntil: nil)
        let data = try makeEncoder().encode(bounds)
        let decoded = try makeDecoder().decode(TemporalBounds.self, from: data)
        #expect(decoded.validUntil == nil)
    }
}
