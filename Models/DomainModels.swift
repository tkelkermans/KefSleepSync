import Foundation
import CoreAudio

struct DiscoveredSpeaker: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let modelName: String
    let serialNumber: String?
    let host: String
    let port: Int
    let serviceName: String
    let lastSeenAt: Date

    var identity: SelectedSpeakerIdentity {
        SelectedSpeakerIdentity(
            kefId: id,
            name: name,
            modelName: modelName,
            serialNumber: serialNumber
        )
    }

    var hostDisplayName: String {
        "\(host):\(port)"
    }
}

struct SelectedSpeakerIdentity: Codable, Equatable, Identifiable {
    let kefId: String
    let name: String
    let modelName: String
    let serialNumber: String?

    var id: String { kefId }
}

enum PhysicalSourceValue: String, CaseIterable, Codable {
    case wifi
    case bluetooth
    case optical
    case coaxial
    case analogue
    case usb
    case standby

    var displayName: String {
        switch self {
        case .wifi:
            return "Wi‑Fi"
        case .bluetooth:
            return "Bluetooth"
        case .optical:
            return "Optical"
        case .coaxial:
            return "Coaxial"
        case .analogue:
            return "Analogue"
        case .usb:
            return "USB"
        case .standby:
            return "Standby"
        }
    }
}

enum StandbyModeValue: String, CaseIterable, Codable {
    case eco = "networkStandby"
    case standby20Minutes = "standby_20mins"
    case standby30Minutes = "standby_30mins"
    case standby60Minutes = "standby_60mins"
    case standbyNone = "standby_none"

    var displayName: String {
        switch self {
        case .eco:
            return "Eco"
        case .standby20Minutes:
            return "20 Minutes"
        case .standby30Minutes:
            return "30 Minutes"
        case .standby60Minutes:
            return "60 Minutes"
        case .standbyNone:
            return "Never"
        }
    }
}

enum PowerCommand: String, Codable {
    case networkStandby
    case powerOn
}

struct PowerTargetValue: Codable, Equatable {
    let nextReason: String
    let nextTarget: String
    let target: String
}

extension PowerTargetValue {
    var displayName: String {
        target
    }
}

struct AutomationState: Codable, Equatable {
    var isEnabled: Bool = false
    var originalStandbyMode: StandbyModeValue?
    var lastSyncDescription: String?
    var lastSyncAt: Date?

    var lastSyncSummary: String {
        guard let lastSyncDescription else {
            return "No sync has run yet."
        }

        guard let lastSyncAt else {
            return lastSyncDescription
        }

        return "\(lastSyncDescription) (\(lastSyncAt.formatted(date: .abbreviated, time: .shortened)))"
    }
}

struct KeyboardVolumeControlState: Codable, Equatable {
    static let defaultStepSize = 4

    var isEnabled: Bool = false
    var stepSize: Int = Self.defaultStepSize
    var preferredMacOutputRoute: PreferredMacOutputRoute?
}

struct PreferredMacOutputRoute: Codable, Equatable {
    let deviceName: String
    let manufacturer: String?
    let dataSourceName: String?

    var displayName: String {
        guard let dataSourceName,
              !dataSourceName.isEmpty,
              dataSourceName.caseInsensitiveCompare(deviceName) != .orderedSame else {
            return deviceName
        }

        return "\(deviceName) (\(dataSourceName))"
    }
}

struct SystemAudioOutputRoute: Equatable {
    let deviceID: AudioDeviceID
    let deviceName: String
    let manufacturer: String?
    let dataSourceName: String?

    var preferredRoute: PreferredMacOutputRoute {
        PreferredMacOutputRoute(
            deviceName: deviceName,
            manufacturer: manufacturer,
            dataSourceName: dataSourceName
        )
    }

    var displayName: String {
        preferredRoute.displayName
    }

    var looksLikeOptical: Bool {
        let terms = [deviceName, manufacturer, dataSourceName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return terms.contains("spdif")
            || terms.contains("optical")
            || terms.contains("digital out")
            || terms.contains("digital output")
            || terms.contains("toslink")
    }

    func matches(_ preferredRoute: PreferredMacOutputRoute) -> Bool {
        guard deviceName == preferredRoute.deviceName else {
            return false
        }

        if let preferredManufacturer = preferredRoute.manufacturer,
           manufacturer != preferredManufacturer {
            return false
        }

        if let preferredDataSourceName = preferredRoute.dataSourceName {
            return dataSourceName == preferredDataSourceName
        }

        return true
    }
}
