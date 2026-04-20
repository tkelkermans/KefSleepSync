import XCTest
import IOKit.hidsystem
@testable import KefSleepSync

final class MediaKeyMonitorTests: XCTestCase {
    func testParsesVolumeUpKeyDown() {
        let data1 = makeData1(keyCode: NX_KEYTYPE_SOUND_UP, state: 0xA)
        XCTAssertEqual(
            MediaKeyAction.fromSystemDefinedEvent(
                subtype: Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                data1: data1
            ),
            .volumeUp
        )
    }

    func testParsesVolumeDownKeyDown() {
        let data1 = makeData1(keyCode: NX_KEYTYPE_SOUND_DOWN, state: 0xA)
        XCTAssertEqual(
            MediaKeyAction.fromSystemDefinedEvent(
                subtype: Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                data1: data1
            ),
            .volumeDown
        )
    }

    func testIgnoresMuteKey() {
        let data1 = makeData1(keyCode: NX_KEYTYPE_MUTE, state: 0xA)
        XCTAssertNil(
            MediaKeyAction.fromSystemDefinedEvent(
                subtype: Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                data1: data1
            )
        )
    }

    func testIgnoresKeyUpEvents() {
        let data1 = makeData1(keyCode: NX_KEYTYPE_SOUND_UP, state: 0xB)
        XCTAssertNil(
            MediaKeyAction.fromSystemDefinedEvent(
                subtype: Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                data1: data1
            )
        )
    }

    func testIgnoresOtherSystemDefinedSubtypes() {
        let data1 = makeData1(keyCode: NX_KEYTYPE_SOUND_UP, state: 0xA)
        XCTAssertNil(
            MediaKeyAction.fromSystemDefinedEvent(
                subtype: 0,
                data1: data1
            )
        )
    }

    private func makeData1(keyCode: Int32, state: Int32) -> Int32 {
        (keyCode << 16) | (state << 8)
    }
}
