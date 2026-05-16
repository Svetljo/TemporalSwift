import Testing
import Foundation
@testable import TemporalSwiftCore

@Suite("AttributeValue Tests")
struct AttributeValueTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func roundTrip(_ value: AttributeValue) throws -> AttributeValue {
        let data = try encoder.encode(value)
        return try decoder.decode(AttributeValue.self, from: data)
    }

    @Test("Codable round-trip: string")
    func roundTripString() throws {
        let value = AttributeValue.string("hello world")
        #expect(try roundTrip(value) == value)
    }

    @Test("Codable round-trip: int")
    func roundTripInt() throws {
        let value = AttributeValue.int(42)
        #expect(try roundTrip(value) == value)
    }

    @Test("Codable round-trip: double")
    func roundTripDouble() throws {
        let value = AttributeValue.double(3.14159)
        #expect(try roundTrip(value) == value)
    }

    @Test("Codable round-trip: bool true")
    func roundTripBoolTrue() throws {
        let value = AttributeValue.bool(true)
        #expect(try roundTrip(value) == value)
    }

    @Test("Codable round-trip: bool false")
    func roundTripBoolFalse() throws {
        let value = AttributeValue.bool(false)
        #expect(try roundTrip(value) == value)
    }

    @Test("Codable round-trip: date")
    func roundTripDate() throws {
        // Use integer seconds to avoid sub-second precision issues with ISO 8601
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let value = AttributeValue.date(date)
        let decoded = try roundTrip(value)
        guard case .date(let decodedDate) = decoded else {
            Issue.record("Expected .date case")
            return
        }
        // ISO 8601 has second precision
        #expect(abs(decodedDate.timeIntervalSince(date)) < 1.0)
    }

    @Test("Codable round-trip: null")
    func roundTripNull() throws {
        let value = AttributeValue.null
        #expect(try roundTrip(value) == value)
    }

    @Test("Hashable: same cases are equal")
    func hashableEquality() {
        let a = AttributeValue.string("test")
        let b = AttributeValue.string("test")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Hashable: different cases are not equal")
    func hashableInequality() {
        #expect(AttributeValue.string("x") != AttributeValue.int(0))
        #expect(AttributeValue.bool(true) != AttributeValue.bool(false))
        #expect(AttributeValue.null != AttributeValue.string(""))
    }
}
