import Foundation

actor KeyboardVolumeController {
    enum Result: Equatable {
        case adjusted(Int)
        case unchanged(Int)
        case unavailableSource(PhysicalSourceValue)
    }

    func readPhysicalSource(on speaker: DiscoveredSpeaker, using apiClient: KefAPIClient) async throws -> PhysicalSourceValue {
        try await apiClient.readPhysicalSource(from: speaker)
    }

    func adjustVolume(on speaker: DiscoveredSpeaker, delta: Int, using apiClient: KefAPIClient) async throws -> Result {
        let source = try await apiClient.readPhysicalSource(from: speaker)
        guard source == .optical else {
            return .unavailableSource(source)
        }

        let currentVolume = try await apiClient.readVolume(from: speaker)
        let newVolume = KefAPIClient.clampVolume(currentVolume + delta)

        guard newVolume != currentVolume else {
            return .unchanged(currentVolume)
        }

        try await apiClient.setVolume(newVolume, on: speaker)
        return .adjusted(newVolume)
    }
}
