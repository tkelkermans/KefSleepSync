import Foundation

enum NSDKValue: Codable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case enumString(type: String, value: String)
    case powerTarget(PowerTargetValue)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let typeKey = DynamicCodingKey("type")
        let type = try container.decode(String.self, forKey: typeKey)

        switch type {
        case "string_":
            self = .string(try container.decode(String.self, forKey: DynamicCodingKey("string_")))
        case "bool_":
            self = .bool(try container.decode(Bool.self, forKey: DynamicCodingKey("bool_")))
        case "i16_", "i32_", "i64_":
            self = .int(try container.decode(Int.self, forKey: DynamicCodingKey(type)))
        case "double_":
            self = .double(try container.decode(Double.self, forKey: DynamicCodingKey("double_")))
        case "powerTarget":
            self = .powerTarget(try container.decode(PowerTargetValue.self, forKey: DynamicCodingKey("powerTarget")))
        default:
            if let raw = try? container.decode(String.self, forKey: DynamicCodingKey(type)) {
                self = .enumString(type: type, value: raw)
            } else if let rawInt = try? container.decode(Int.self, forKey: DynamicCodingKey(type)) {
                self = .int(rawInt)
            } else if let rawBool = try? container.decode(Bool.self, forKey: DynamicCodingKey(type)) {
                self = .bool(rawBool)
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: DynamicCodingKey(type),
                    in: container,
                    debugDescription: "Unsupported NSDK value type \(type)"
                )
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(storage.type, forKey: DynamicCodingKey("type"))

        switch storage {
        case let .string(value):
            try container.encode(value, forKey: DynamicCodingKey("string_"))
        case let .bool(value):
            try container.encode(value, forKey: DynamicCodingKey("bool_"))
        case let .int(value):
            try container.encode(value, forKey: DynamicCodingKey("i32_"))
        case let .double(value):
            try container.encode(value, forKey: DynamicCodingKey("double_"))
        case let .enumString(type, value):
            try container.encode(value, forKey: DynamicCodingKey(type))
        case let .powerTarget(value):
            try container.encode(value, forKey: DynamicCodingKey("powerTarget"))
        }
    }

    var rawString: String? {
        switch self {
        case let .string(value):
            return value
        case let .enumString(_, value):
            return value
        default:
            return nil
        }
    }

    private var storage: Storage {
        switch self {
        case let .string(value):
            return .string(value)
        case let .bool(value):
            return .bool(value)
        case let .int(value):
            return .int(value)
        case let .double(value):
            return .double(value)
        case let .enumString(type, value):
            return .enumString(type: type, value: value)
        case let .powerTarget(value):
            return .powerTarget(value)
        }
    }

    private enum Storage {
        case string(String)
        case bool(Bool)
        case int(Int)
        case double(Double)
        case enumString(type: String, value: String)
        case powerTarget(PowerTargetValue)

        var type: String {
            switch self {
            case .string:
                return "string_"
            case .bool:
                return "bool_"
            case .int:
                return "i32_"
            case .double:
                return "double_"
            case let .enumString(type, _):
                return type
            case .powerTarget:
                return "powerTarget"
            }
        }
    }
}

struct NSDKSetDataRequest: Encodable, Equatable {
    let path: String
    let role: String
    let value: NSDKValue
}

struct NSDKRemoteError: Decodable, Error, LocalizedError, Equatable {
    let title: String
    let name: String
    let message: String

    var errorDescription: String? { message }
}

struct NSDKErrorEnvelope: Decodable, Equatable {
    let error: NSDKRemoteError
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
