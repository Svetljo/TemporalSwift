import Foundation

/// Represents a temporal interval during which a fact is valid.
///
/// A `TemporalBounds` with a `nil` `validUntil` represents an open-ended
/// (currently active) interval. An instance with both fields set represents
/// a closed interval.
public struct TemporalBounds: Codable, Sendable, Hashable, Equatable {
    /// The start of the validity period (inclusive).
    public let validFrom: Date
    /// The end of the validity period (exclusive). `nil` means currently active.
    public let validUntil: Date?

    /// Creates a new `TemporalBounds`.
    ///
    /// - Parameters:
    ///   - validFrom: Start of validity (inclusive).
    ///   - validUntil: End of validity (exclusive). Pass `nil` for open-ended.
    public init(validFrom: Date, validUntil: Date?) {
        self.validFrom = validFrom
        self.validUntil = validUntil
    }

    /// Returns `true` if the given date falls within this interval.
    ///
    /// The interval is `[validFrom, validUntil)` — inclusive start, exclusive end.
    /// If `validUntil` is `nil` the interval is open-ended.
    ///
    /// - Parameter date: The date to test.
    /// - Returns: `true` if `date >= validFrom` and (`validUntil == nil` or `date < validUntil`).
    public func contains(_ date: Date) -> Bool {
        guard date >= validFrom else { return false }
        if let until = validUntil {
            return date < until
        }
        return true
    }

    /// Returns `true` if this interval shares any point in time with `other`.
    ///
    /// - Parameter other: Another `TemporalBounds` to test against.
    /// - Returns: `true` if the two intervals overlap.
    public func overlaps(_ other: TemporalBounds) -> Bool {
        // Two intervals do NOT overlap only if one ends before the other starts.
        if let myUntil = validUntil, myUntil <= other.validFrom {
            return false
        }
        if let otherUntil = other.validUntil, otherUntil <= validFrom {
            return false
        }
        return true
    }
}
