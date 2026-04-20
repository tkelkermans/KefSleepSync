import XCTest
@testable import KefSleepSync

final class NSDKValueTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func testSpeakerStatusPayloadDecodes() throws {
        let payload = #"{"kefSpeakerStatus":"standby","type":"kefSpeakerStatus"}"#.data(using: .utf8)!
        let value = try decoder.decode(NSDKValue.self, from: payload)

        XCTAssertEqual(value, .enumString(type: "kefSpeakerStatus", value: "standby"))
    }

    func testPhysicalSourcePayloadDecodes() throws {
        let payload = #"{"kefPhysicalSource":"optical","type":"kefPhysicalSource"}"#.data(using: .utf8)!
        let value = try decoder.decode(NSDKValue.self, from: payload)

        XCTAssertEqual(value, .enumString(type: "kefPhysicalSource", value: "optical"))
    }

    func testStandbyModePayloadDecodes() throws {
        let payload = #"{"kefStandbyMode":"standby_20mins","type":"kefStandbyMode"}"#.data(using: .utf8)!
        let value = try decoder.decode(NSDKValue.self, from: payload)

        XCTAssertEqual(value, .enumString(type: "kefStandbyMode", value: "standby_20mins"))
    }

    func testPowerTargetPayloadDecodes() throws {
        let payload = #"{"powerTarget":{"nextReason":"none","nextTarget":"none","target":"networkStandby"},"type":"powerTarget"}"#.data(using: .utf8)!
        let value = try decoder.decode(NSDKValue.self, from: payload)

        XCTAssertEqual(
            value,
            .powerTarget(PowerTargetValue(nextReason: "none", nextTarget: "none", target: "networkStandby"))
        )
    }

    func testSetDataRequestEncodesStringValue() throws {
        let request = NSDKSetDataRequest(
            path: "settings:/kef/play/physicalSource",
            role: "value",
            value: .string("optical")
        )

        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let value = json?["value"] as? [String: String]

        XCTAssertEqual(json?["path"] as? String, "settings:/kef/play/physicalSource")
        XCTAssertEqual(json?["role"] as? String, "value")
        XCTAssertEqual(value?["type"], "string_")
        XCTAssertEqual(value?["string_"], "optical")
    }
}
