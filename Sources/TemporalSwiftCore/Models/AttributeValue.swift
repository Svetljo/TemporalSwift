import Foundation

/// Represents the possible types for entity attributes in the temporal graph.
///
/// `AttributeValue` supports all common scalar types and an explicit null case,
/// enabling heterogeneous attribute dictionaries on nodes and edges.
public enum AttributeValue: Codable, Sendable, Hashable, Equatable {
    /// A text string value.
    case string(String)
    /// An integer value.
    case int(Int)
    /// A floating-point value.
    case double(Double)
    /// A boolean value.
    case bool(Bool)
    /// A date/time value, serialized as ISO 8601.
    case date(Date)
    /// An explicit null value.
    case null

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    private enum TypeTag: String, Codable {
        case string, int, double, bool, date, null
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(TypeTag.self, forKey: .type)
        switch tag {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .int:
            self = .int(try container.decode(Int.self, forKey: .value))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .value))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .date:
            self = .date(try container.decode(Date.self, forKey: .value))
        case .null:
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let v):
            try container.encode(TypeTag.string, forKey: .type)
            try container.encode(v, forKey: .value)
        case .int(let v):
            try container.encode(TypeTag.int, forKey: .type)
            try container.encode(v, forKey: .value)
        case .double(let v):
            try container.encode(TypeTag.double, forKey: .type)
            try container.encode(v, forKey: .value)
        case .bool(let v):
            try container.encode(TypeTag.bool, forKey: .type)
            try container.encode(v, forKey: .value)
        case .date(let v):
            try container.encode(TypeTag.date, forKey: .type)
            try container.encode(v, forKey: .value)
        case .null:
            try container.encode(TypeTag.null, forKey: .type)
        }
    }
}
