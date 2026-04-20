import Combine
import Darwin
import Foundation
import Network

final class SpeakerDiscoveryService: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var speakers: [DiscoveredSpeaker] = []

    private let browser: NWBrowser
    private let queue = DispatchQueue(label: "com.tristan.kef.KefSleepSync.browser")
    private var hasStarted = false
    private var resolutionTasks: [String: Task<Void, Never>] = [:]

    override init() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        browser = NWBrowser(for: .bonjour(type: "_kef-info._tcp", domain: nil), using: parameters)
        super.init()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                AppLogger.discovery.info("Bonjour browser is ready.")
            case let .failed(error):
                AppLogger.discovery.error("Bonjour browser failed: \(error.localizedDescription, privacy: .public)")
            case let .waiting(error):
                AppLogger.discovery.warning("Bonjour browser waiting: \(error.localizedDescription, privacy: .public)")
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handle(results: Array(results))
        }

        browser.start(queue: queue)
    }

    private func handle(results: [NWBrowser.Result]) {
        let snapshots = results.compactMap(makeSnapshot(from:))
        let activeServiceNames = Set(snapshots.map(\.serviceName))

        Task { @MainActor [weak self] in
            self?.speakers.removeAll { !activeServiceNames.contains($0.serviceName) }
        }

        resolutionTasks.values.forEach { $0.cancel() }
        resolutionTasks.removeAll()

        for snapshot in snapshots {
            resolutionTasks[snapshot.serviceName] = Task { [weak self] in
                await self?.resolve(snapshot)
            }
        }
    }

    private func resolve(_ snapshot: BrowserSnapshot) async {
        do {
            let resolved = try await NetServiceResolver().resolve(
                name: snapshot.serviceName,
                type: snapshot.type,
                domain: snapshot.domain,
                timeout: 3
            )

            guard !Task.isCancelled else { return }

            let speaker = DiscoveredSpeaker(
                id: resolved.kefID,
                name: resolved.name,
                modelName: resolved.modelName,
                serialNumber: resolved.serialNumber,
                host: resolved.host,
                port: resolved.port,
                serviceName: snapshot.serviceName,
                lastSeenAt: Date()
            )

            await MainActor.run {
                self.upsert(speaker)
            }
        } catch {
            guard !Task.isCancelled else { return }
            AppLogger.discovery.warning("Failed to resolve \(snapshot.serviceName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func upsert(_ speaker: DiscoveredSpeaker) {
        if let index = speakers.firstIndex(where: { $0.id == speaker.id }) {
            speakers[index] = speaker
        } else {
            speakers.append(speaker)
        }

        speakers.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func makeSnapshot(from result: NWBrowser.Result) -> BrowserSnapshot? {
        guard case let .service(name: serviceName, type: type, domain: domain, interface: _) = result.endpoint else {
            return nil
        }

        return BrowserSnapshot(
            serviceName: serviceName,
            type: type,
            domain: domain
        )
    }
}

private struct BrowserSnapshot {
    let serviceName: String
    let type: String
    let domain: String
}

private struct ResolvedService {
    let kefID: String
    let name: String
    let modelName: String
    let serialNumber: String?
    let host: String
    let port: Int
}

@MainActor
private final class NetServiceResolver: NSObject, NetServiceDelegate {
    private var continuation: CheckedContinuation<ResolvedService, Error>?
    private var service: NetService?

    func resolve(name: String, type: String, domain: String, timeout: TimeInterval) async throws -> ResolvedService {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let service = NetService(domain: domain, type: type, name: name)
            service.delegate = self
            self.service = service
            service.resolve(withTimeout: timeout)
        }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let hostName = sender.hostName
        let port = sender.port
        let addresses = sender.addresses ?? []
        let txtRecord = Self.parseTXTRecord(from: sender.txtRecordData())

        Task { @MainActor in
            let orderedHosts = Self.orderedHosts(hostName: hostName, addresses: addresses)

            guard let host = orderedHosts.first else {
                finish(with: NSError(domain: "KefSleepSync.NetServiceResolver", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "The KEF speaker did not provide a host name."
                ]))
                return
            }

            let modelName = txtRecord["modelName"] ?? "KEF Speaker"
            let displayName = txtRecord["name"] ?? modelName
            let kefID = txtRecord["kefId"] ?? sender.name
            let serialNumber = txtRecord["serialNumber"]

            finish(with: ResolvedService(
                kefID: kefID,
                name: displayName,
                modelName: modelName,
                serialNumber: serialNumber,
                host: host,
                port: port
            ))
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Task { @MainActor in
            finish(with: NSError(domain: "KefSleepSync.NetServiceResolver", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The KEF speaker service could not be resolved."
            ]))
        }
    }

    private func finish(with result: ResolvedService) {
        continuation?.resume(returning: result)
        continuation = nil
        service = nil
    }

    private func finish(with error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        service = nil
    }

    private nonisolated static func parseTXTRecord(from data: Data?) -> [String: String] {
        guard let data else { return [:] }

        let txtRecord = NetService.dictionary(fromTXTRecord: data)
        return txtRecord.reduce(into: [String: String]()) { partialResult, pair in
            partialResult[pair.key] = String(data: pair.value, encoding: .utf8)
        }
    }

    private nonisolated static func orderedHosts(hostName: String?, addresses: [Data]) -> [String] {
        let numericHosts = addresses.compactMap(numericHost(from:))
        let ipv4Hosts = numericHosts.filter { $0.contains(".") }
        let ipv6Hosts = numericHosts.filter { $0.contains(":") && !$0.lowercased().hasPrefix("fe80:") }

        var orderedHosts = ipv4Hosts + ipv6Hosts
        if let hostName {
            let trimmedHostName = hostName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if !trimmedHostName.isEmpty {
                orderedHosts.append(trimmedHostName)
            }
        }

        var seen: Set<String> = []
        return orderedHosts.filter { seen.insert($0).inserted }
    }

    private nonisolated static func numericHost(from addressData: Data) -> String? {
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))

        let result = addressData.withUnsafeBytes { rawBufferPointer -> Int32 in
            guard let baseAddress = rawBufferPointer.baseAddress else {
                return EAI_FAIL
            }

            let sockaddrPointer = baseAddress.assumingMemoryBound(to: sockaddr.self)
            return getnameinfo(
                sockaddrPointer,
                socklen_t(addressData.count),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
        }

        guard result == 0 else {
            return nil
        }

        let host = String(cString: hostBuffer)
        guard !host.isEmpty else {
            return nil
        }

        return host
    }
}
