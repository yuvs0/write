import Foundation

/// A JSON value, used to carry CSL-JSON fields without loss.
nonisolated enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
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
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Foundation representation for JSONSerialization / JavaScriptCore.
    var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .array(let value): return value.map(\.anyValue)
        case .object(let value): return value.mapValues(\.anyValue)
        case .null: return NSNull()
        }
    }

    init?(any: Any) {
        switch any {
        case let value as String: self = .string(value)
        case let value as Bool: self = .bool(value)
        case let value as NSNumber:
            // NSNumber bools are caught above only for Swift Bool; check objCType.
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as [Any]:
            self = .array(value.compactMap(JSONValue.init(any:)))
        case let value as [String: Any]:
            self = .object(value.compactMapValues(JSONValue.init(any:)))
        case is NSNull: self = .null
        default: return nil
        }
    }
}

/// One bibliographic source, faithful to CSL-JSON: `id` is the citekey,
/// every other field is carried verbatim in `fields` so nothing is lost
/// on round-trip and citeproc sees exactly what was stored.
nonisolated struct CSLItem: Identifiable, Hashable, Codable {
    var id: String
    var fields: [String: JSONValue]

    init(id: String, fields: [String: JSONValue] = [:]) {
        self.id = id
        self.fields = fields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        var object = try container.decode([String: JSONValue].self)
        self.id = object.removeValue(forKey: "id")?.stringValue ?? UUID().uuidString
        self.fields = object
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var object = fields
        object["id"] = .string(id)
        try container.encode(object)
    }

    /// Dictionary form for citeproc-js.
    var cslJSONObject: [String: Any] {
        var object = fields.mapValues(\.anyValue)
        object["id"] = id
        return object
    }

    // MARK: - Typed accessors

    var type: String {
        get { fields["type"]?.stringValue ?? "webpage" }
        set { fields["type"] = .string(newValue) }
    }

    var title: String {
        get { fields["title"]?.stringValue ?? "" }
        set { fields["title"] = .string(newValue) }
    }

    var containerTitle: String? {
        get { fields["container-title"]?.stringValue }
        set { fields["container-title"] = newValue.map(JSONValue.string) }
    }

    var doi: String? {
        get { fields["DOI"]?.stringValue }
        set { fields["DOI"] = newValue.map(JSONValue.string) }
    }

    var url: String? {
        get { fields["URL"]?.stringValue }
        set { fields["URL"] = newValue.map(JSONValue.string) }
    }

    /// Authors as (family, given) pairs from the CSL `author` array.
    var authors: [(family: String, given: String)] {
        get {
            guard let array = fields["author"]?.arrayValue else { return [] }
            return array.compactMap { entry in
                guard let object = entry.objectValue else { return nil }
                let family = object["family"]?.stringValue
                    ?? object["literal"]?.stringValue
                    ?? ""
                return (family: family, given: object["given"]?.stringValue ?? "")
            }
        }
        set {
            fields["author"] = .array(newValue.map { author in
                var object: [String: JSONValue] = [:]
                if !author.family.isEmpty { object["family"] = .string(author.family) }
                if !author.given.isEmpty { object["given"] = .string(author.given) }
                return .object(object)
            })
        }
    }

    /// Publication year from the CSL `issued` date-parts.
    var issuedYear: Int? {
        get {
            guard let parts = fields["issued"]?.objectValue?["date-parts"]?.arrayValue,
                  let first = parts.first?.arrayValue,
                  let year = first.first?.numberValue
            else { return nil }
            return Int(year)
        }
        set {
            if let year = newValue {
                fields["issued"] = .object(["date-parts": .array([.array([.number(Double(year))])])])
            } else {
                fields.removeValue(forKey: "issued")
            }
        }
    }

    /// One-line summary for lists: "Smith & Jones (2020)".
    var authorYearSummary: String {
        let names = authors.map(\.family).filter { !$0.isEmpty }
        let authorPart: String
        switch names.count {
        case 0: authorPart = containerTitle ?? "Unknown"
        case 1: authorPart = names[0]
        case 2: authorPart = "\(names[0]) & \(names[1])"
        default: authorPart = "\(names[0]) et al."
        }
        if let year = issuedYear {
            return "\(authorPart) (\(year))"
        }
        return authorPart
    }
}
