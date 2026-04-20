import XCTest
@testable import KefSleepSync

final class SystemAudioOutputRouteTests: XCTestCase {
    func testOpticalRouteHeuristicRecognizesSpdifOutput() {
        let route = SystemAudioOutputRoute(
            deviceID: 1,
            deviceName: "SPDIF Output",
            manufacturer: "CMEDIA",
            dataSourceName: nil
        )

        XCTAssertTrue(route.looksLikeOptical)
    }

    func testOpticalRouteHeuristicRejectsAirPods() {
        let route = SystemAudioOutputRoute(
            deviceID: 2,
            deviceName: "AirPods Pro",
            manufacturer: "Apple",
            dataSourceName: nil
        )

        XCTAssertFalse(route.looksLikeOptical)
    }

    func testRouteMatchingUsesDeviceNameManufacturerAndDataSource() {
        let preferred = PreferredMacOutputRoute(
            deviceName: "MacBook Pro Speakers",
            manufacturer: "Apple",
            dataSourceName: "External Headphones"
        )
        let matching = SystemAudioOutputRoute(
            deviceID: 3,
            deviceName: "MacBook Pro Speakers",
            manufacturer: "Apple",
            dataSourceName: "External Headphones"
        )
        let otherDataSource = SystemAudioOutputRoute(
            deviceID: 3,
            deviceName: "MacBook Pro Speakers",
            manufacturer: "Apple",
            dataSourceName: "MacBook Pro Speakers"
        )

        XCTAssertTrue(matching.matches(preferred))
        XCTAssertFalse(otherDataSource.matches(preferred))
    }
}
