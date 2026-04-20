import CoreAudio
import Foundation

final class SystemAudioOutputMonitor {
    var onRouteChange: ((SystemAudioOutputRoute?) -> Void)?

    private let listenerQueue = DispatchQueue.main
    private var defaultOutputDeviceListener: AudioObjectPropertyListenerBlock?
    private var currentDeviceDataSourceListener: AudioObjectPropertyListenerBlock?
    private var observedDeviceID: AudioDeviceID?

    deinit {
        stop()
    }

    func start() {
        guard defaultOutputDeviceListener == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleRouteChange()
        }
        defaultOutputDeviceListener = block

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerQueue,
            block
        )

        handleRouteChange()
        AppLogger.keyboard.info("Started monitoring the macOS default audio output route.")
    }

    func stop() {
        if let block = defaultOutputDeviceListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                listenerQueue,
                block
            )
            defaultOutputDeviceListener = nil
        }

        detachCurrentDeviceListener()
    }

    func currentRoute() -> SystemAudioOutputRoute? {
        let deviceID = currentDefaultOutputDeviceID()
        attachCurrentDeviceListenerIfNeeded(for: deviceID)
        return deviceID.flatMap(readRoute(for:))
    }

    private func handleRouteChange() {
        let route = currentRoute()
        onRouteChange?(route)

        if let route {
            AppLogger.keyboard.debug("Current macOS output route is \(route.displayName, privacy: .public).")
        } else {
            AppLogger.keyboard.debug("No current macOS output route could be read.")
        }
    }

    private func currentDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            return nil
        }

        return deviceID
    }

    private func readRoute(for deviceID: AudioDeviceID) -> SystemAudioOutputRoute? {
        guard let deviceName = stringProperty(
            on: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        ) else {
            return nil
        }

        let manufacturer = stringProperty(
            on: deviceID,
            selector: kAudioObjectPropertyManufacturer,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let dataSourceName = currentDataSourceName(for: deviceID)

        return SystemAudioOutputRoute(
            deviceID: deviceID,
            deviceName: deviceName,
            manufacturer: manufacturer,
            dataSourceName: dataSourceName
        )
    }

    private func stringProperty(
        on objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: NSString?
        var size = UInt32(MemoryLayout<NSString?>.size)

        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        }

        guard status == noErr else {
            return nil
        }

        return value as String?
    }

    private func currentDataSourceName(for deviceID: AudioDeviceID) -> String? {
        var dataSourceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &dataSourceAddress) else {
            return nil
        }

        var dataSourceID = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &dataSourceAddress,
            0,
            nil,
            &size,
            &dataSourceID
        )

        guard status == noErr else {
            return nil
        }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSourceNameForIDCFString,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: NSString?

        let translationStatus = withUnsafeMutablePointer(to: &dataSourceID) { dataSourceIDPointer in
            withUnsafeMutablePointer(to: &name) { namePointer in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(dataSourceIDPointer),
                    mInputDataSize: UInt32(MemoryLayout<UInt32>.size),
                    mOutputData: UnsafeMutableRawPointer(namePointer),
                    mOutputDataSize: UInt32(MemoryLayout<NSString?>.size)
                )
                var translationSize = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return AudioObjectGetPropertyData(
                    deviceID,
                    &nameAddress,
                    0,
                    nil,
                    &translationSize,
                    &translation
                )
            }
        }

        guard translationStatus == noErr else {
            return nil
        }

        return name as String?
    }

    private func attachCurrentDeviceListenerIfNeeded(for deviceID: AudioDeviceID?) {
        guard observedDeviceID != deviceID else {
            return
        }

        detachCurrentDeviceListener()

        guard let deviceID else {
            observedDeviceID = nil
            return
        }

        observedDeviceID = deviceID

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return
        }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleRouteChange()
        }
        currentDeviceDataSourceListener = block

        AudioObjectAddPropertyListenerBlock(deviceID, &address, listenerQueue, block)
    }

    private func detachCurrentDeviceListener() {
        if let observedDeviceID,
           let block = currentDeviceDataSourceListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDataSource,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(observedDeviceID, &address, listenerQueue, block)
        }

        currentDeviceDataSourceListener = nil
        observedDeviceID = nil
    }
}
