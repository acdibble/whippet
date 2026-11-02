import Foundation

/// Any JSON value, for the messages between Whippet and an extension's JavaScript, whose shapes Swift can't know ahead.
public enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let bool): try container.encode(bool)
        case .number(let number): try container.encode(number)
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }

    /// Converts what `JSONSerialization` returns. Booleans arrive as `NSNumber` too, and are told apart by their type.
    public init(object: Any) {
        switch object {
        case let number as NSNumber:
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map(JSONValue.init(object:)))
        case let object as [String: Any]:
            self = .object(object.mapValues(JSONValue.init(object:)))
        default:
            self = .null
        }
    }

    public var string: String? {
        if case .string(let string) = self { return string }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let bool) = self { return bool }
        return nil
    }

    public var number: Double? {
        if case .number(let number) = self { return number }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let array) = self { return array }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let object) = self { return object }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        object?[key]
    }

    /// Compact JSON text, as JavaScript's `JSON.parse` reads it.
    public var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
}
