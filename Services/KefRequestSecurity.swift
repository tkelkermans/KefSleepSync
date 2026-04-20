import CommonCrypto
import CryptoKit
import Foundation
import Security

enum WebServerAuthMode: String, Codable {
    case none
    case setData
    case all
}

struct KefRequestSecuritySeed {
    var salt: Data?
    var iv: Data?
    var timestampMilliseconds: String?

    init(salt: Data? = nil, iv: Data? = nil, timestampMilliseconds: String? = nil) {
        self.salt = salt
        self.iv = iv
        self.timestampMilliseconds = timestampMilliseconds
    }
}

enum KefRequestSecurity {
    enum Error: LocalizedError {
        case randomBytesFailed(OSStatus)
        case invalidKeyLength(Int)
        case invalidIVLength(Int)
        case encryptionFailed(CCCryptorStatus)
        case invalidBodyString

        var errorDescription: String? {
            switch self {
            case let .randomBytesFailed(status):
                return "Generating KEF authentication bytes failed (\(status))."
            case let .invalidKeyLength(length):
                return "KEF authentication expected a 32-byte key but received \(length)."
            case let .invalidIVLength(length):
                return "KEF authentication expected a 16-byte IV but received \(length)."
            case let .encryptionFailed(status):
                return "KEF request encryption failed (\(status))."
            case .invalidBodyString:
                return "KEF request body could not be encoded as UTF-8."
            }
        }
    }

    private static let username = "user"

    static func makeSecureWriteRequest(
        url: URL,
        path: String,
        role: String,
        value: NSDKValue,
        password: String,
        seed: KefRequestSecuritySeed = KefRequestSecuritySeed()
    ) throws -> URLRequest {
        let salt = try seed.salt ?? randomBytes(count: 6)
        let iv = try seed.iv ?? randomBytes(count: kCCBlockSizeAES128)
        let timestamp = seed.timestampMilliseconds ?? String(Int(Date().timeIntervalSince1970 * 1_000))

        let key = deriveKey(salt: salt, password: password)
        let wrappedValueData = try JSONEncoder().encode(value)
        let encryptedValue = try encrypt(plaintext: wrappedValueData, key: key, iv: iv)

        var combinedEncryptedValue = Data()
        combinedEncryptedValue.append(iv)
        combinedEncryptedValue.append(encryptedValue)

        let body = SecureWriteBody(
            path: path,
            role: role,
            value: combinedEncryptedValue.base64EncodedString()
        )
        let bodyData = try JSONEncoder().encode(body)

        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            throw Error.invalidBodyString
        }

        let saltBase64 = salt.base64EncodedString()
        let usernameBase64 = Data(username.utf8).base64EncodedString()
        let message = "\(username).\(saltBase64).\(timestamp).\(url.absoluteString).\(bodyString)"
        let signature = Data(
            HMAC<SHA256>.authenticationCode(
                for: Data(message.utf8),
                using: SymmetricKey(data: key)
            )
        ).base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "HMAC_SHA256_AES256 \(usernameBase64).\(saltBase64).\(timestamp).\(signature)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    static func deriveKey(salt: Data, password: String) -> Data {
        var saltedPassword = Data()
        saltedPassword.append(salt)
        saltedPassword.append(Data(password.utf8))
        return Data(SHA256.hash(data: saltedPassword))
    }

    private static func encrypt(plaintext: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES256 else {
            throw Error.invalidKeyLength(key.count)
        }

        guard iv.count == kCCBlockSizeAES128 else {
            throw Error.invalidIVLength(iv.count)
        }

        var output = Data(count: plaintext.count + kCCBlockSizeAES128)
        var outputLength: size_t = 0
        let outputCapacity = output.count
        let keyLength = key.count
        let plaintextLength = plaintext.count

        let status = output.withUnsafeMutableBytes { outputBytes in
            plaintext.withUnsafeBytes { plainBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            keyLength,
                            ivBytes.baseAddress,
                            plainBytes.baseAddress,
                            plaintextLength,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw Error.encryptionFailed(status)
        }

        output.removeSubrange(outputLength ..< output.count)
        return output
    }

    private static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }

        guard status == errSecSuccess else {
            throw Error.randomBytesFailed(status)
        }

        return data
    }
}

private struct SecureWriteBody: Encodable {
    let path: String
    let role: String
    let value: String
}
