import CommonCrypto
import CryptoKit
import Foundation
import XCTest
@testable import KefSleepSync

final class KefRequestSecurityTests: XCTestCase {
    func testSecureWriteRequestEncryptsTypedNSDKPayload() throws {
        let url = URL(string: "http://speaker.local/api/setData")!
        let salt = Data([0x10, 0x11, 0x12, 0x13, 0x14, 0x15])
        let iv = Data((0 ..< 16).map(UInt8.init))
        let seed = KefRequestSecuritySeed(
            salt: salt,
            iv: iv,
            timestampMilliseconds: "1776598287367"
        )

        let request = try KefRequestSecurity.makeSecureWriteRequest(
            url: url,
            path: "settings:/kef/host/standbyMode",
            role: "value",
            value: .string("standby_none"),
            password: "",
            seed: seed
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let authorization = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(authorization.hasPrefix("HMAC_SHA256_AES256 "))

        let bodyData = try XCTUnwrap(request.httpBody)
        let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(bodyObject["path"] as? String, "settings:/kef/host/standbyMode")
        XCTAssertEqual(bodyObject["role"] as? String, "value")

        let encryptedValue = try XCTUnwrap(bodyObject["value"] as? String)
        let decryptedPayload = try decrypt(encryptedValue, password: "", salt: salt)
        let payloadObject = try XCTUnwrap(JSONSerialization.jsonObject(with: decryptedPayload) as? [String: String])
        XCTAssertEqual(payloadObject["type"], "string_")
        XCTAssertEqual(payloadObject["string_"], "standby_none")

        let parts = authorization.replacingOccurrences(of: "HMAC_SHA256_AES256 ", with: "").split(separator: ".")
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(String(parts[0]), Data("user".utf8).base64EncodedString())
        XCTAssertEqual(String(parts[1]), salt.base64EncodedString())
        XCTAssertEqual(String(parts[2]), "1776598287367")

        let expectedSignature = try expectedSignature(
            url: url,
            salt: salt,
            timestamp: "1776598287367",
            bodyData: bodyData,
            password: ""
        )
        XCTAssertEqual(String(parts[3]), expectedSignature)
    }

    private func expectedSignature(
        url: URL,
        salt: Data,
        timestamp: String,
        bodyData: Data,
        password: String
    ) throws -> String {
        let key = KefRequestSecurity.deriveKey(salt: salt, password: password)
        let bodyString = try XCTUnwrap(String(data: bodyData, encoding: .utf8))
        let message = "user.\(salt.base64EncodedString()).\(timestamp).\(url.absoluteString).\(bodyString)"

        return Data(
            HMAC<SHA256>.authenticationCode(
                for: Data(message.utf8),
                using: SymmetricKey(data: key)
            )
        ).base64EncodedString()
    }

    private func decrypt(_ base64Value: String, password: String, salt: Data) throws -> Data {
        let combined = try XCTUnwrap(Data(base64Encoded: base64Value))
        let iv = combined.prefix(16)
        let ciphertext = combined.dropFirst(16)
        let key = KefRequestSecurity.deriveKey(salt: salt, password: password)

        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var outputLength: size_t = 0
        let outputCapacity = output.count
        let keyLength = key.count
        let ciphertextLength = ciphertext.count

        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            keyLength,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertextLength,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        XCTAssertEqual(Int(status), kCCSuccess)
        output.removeSubrange(outputLength ..< output.count)
        return output
    }
}
