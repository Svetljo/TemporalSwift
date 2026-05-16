import Testing
import Foundation
@testable import TemporalSwiftCore

@Suite("TemporalBounds Tests")
struct TemporalBoundsTests {

    // MARK: - contains(_:)

    @Test("contains: date at validFrom boundary is included")
    func containsAtStart() {
        let start = Date(timeIntervalSince1970: 1000)
        let bounds = TemporalBounds(validFrom: start, validUntil: nil)
        #expect(bounds.contains(start))
    }

    @Test("contains: date before validFrom is excluded")
    func containsBeforeStart() {
        let start = Date(timeIntervalSince1970: 1000)
        let bounds = TemporalBounds(validFrom: start, validUntil: nil)
        #expect(!bounds.contains(Date(timeIntervalSince1970: 999)))
    }

    @Test("contains: date after validFrom with nil validUntil is included")
    func containsOpenEnded() {
        let start = Date(timeIntervalSince1970: 1000)
        let bounds = TemporalBounds(validFrom: start, validUntil: nil)
        #expect(bounds.contains(Date(timeIntervalSince1970: 999_999)))
    }

    @Test("contains: date at validUntil is excluded (exclusive end)")
    func containsAtEnd() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 2000)
        let bounds = TemporalBounds(validFrom: start, validUntil: end)
        #expect(!bounds.contains(end))
    }

    @Test("contains: date just before validUntil is included")
    func containsJustBeforeEnd() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 2000)
        let bounds = TemporalBounds(validFrom: start, validUntil: end)
        #expect(bounds.contains(Date(timeIntervalSince1970: 1999.999)))
    }

    @Test("contains: zero-duration bounds (validFrom == validUntil) contains nothing")
    func zeroDurationBoundsContainsNothing() {
        let t = Date(timeIntervalSince1970: 1000)
        let bounds = TemporalBounds(validFrom: t, validUntil: t)
        #expect(!bounds.contains(t))
    }

    @Test("contains: far-future date")
    func containsFarFuture() {
        let start = Date(timeIntervalSince1970: 0)
        let bounds = TemporalBounds(validFrom: start, validUntil: nil)
        let farFuture = Date(timeIntervalSince1970: 32_503_680_000) // year 3000
        #expect(bounds.contains(farFuture))
    }

    @Test("contains: far-past date excluded when bounds start is recent")
    func containsFarPast() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let bounds = TemporalBounds(validFrom: start, validUntil: nil)
        let farPast = Date(timeIntervalSince1970: 0)
        #expect(!bounds.contains(farPast))
    }

    // MARK: - overlaps(_:)

    @Test("overlaps: identical bounds overlap")
    func overlapsIdentical() {
        let bounds = TemporalBounds(validFrom: Date(timeIntervalSince1970: 100), validUntil: Date(timeIntervalSince1970: 200))
        #expect(bounds.overlaps(bounds))
    }

    @Test("overlaps: adjacent bounds do not overlap (exclusive end)")
    func overlapsAdjacent() {
        let a = TemporalBounds(validFrom: Date(timeIntervalSince1970: 100), validUntil: Date(timeIntervalSince1970: 200))
        let b = TemporalBounds(validFrom: Date(timeIntervalSince1970: 200), validUntil: Date(timeIntervalSince1970: 300))
        #expect(!a.overlaps(b))
        #expect(!b.overlaps(a))
    }

    @Test("overlaps: partially overlapping bounds")
    func overlapsPartial() {
        let a = TemporalBounds(validFrom: Date(timeIntervalSince1970: 100), validUntil: Date(timeIntervalSince1970: 250))
        let b = TemporalBounds(validFrom: Date(timeIntervalSince1970: 200), validUntil: Date(timeIntervalSince1970: 350))
        #expect(a.overlaps(b))
        #expect(b.overlaps(a))
    }

    @Test("overlaps: open-ended bounds overlap any later bounds")
    func overlapsOpenEnded() {
        let a = TemporalBounds(validFrom: Date(timeIntervalSince1970: 100), validUntil: nil)
        let b = TemporalBounds(validFrom: Date(timeIntervalSince1970: 999_999), validUntil: nil)
        #expect(a.overlaps(b))
    }

    @Test("overlaps: disjoint closed bounds do not overlap")
    func overlapsDisjoint() {
        let a = TemporalBounds(validFrom: Date(timeIntervalSince1970: 100), validUntil: Date(timeIntervalSince1970: 200))
        let b = TemporalBounds(validFrom: Date(timeIntervalSince1970: 300), validUntil: Date(timeIntervalSince1970: 400))
        #expect(!a.overlaps(b))
        #expect(!b.overlaps(a))
    }
}
