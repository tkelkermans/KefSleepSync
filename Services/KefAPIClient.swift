import Foundation

actor KefAPIClient {
    enum APIPath {
        static let getData = "/api/getData"
        static let setData = "/api/setData"
        static let speakerStatus = "settings:/kef/host/speakerStatus"
        static let physicalSource = "settings:/kef/play/physicalSource"
        static let standbyMode = "settings:/kef/host/standbyMode"
        static let webserverAuthMode = "settings:/webserver/authMode"
        static let changePassword = "webserver:changePassword"
        static let powerTargetRequest = "powermanager:targetRequest"
        static let powerTarget = "powermanager:target"
    }

    enum KefAPIClientError: LocalizedError {
        case invalidURL
        case emptyResponse(String)
        case unsupportedEnumValue(path: String, value: String)
        case unexpectedValue(path: String)
        case httpStatus(Int)
        case passwordRequired

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The speaker URL could not be built."
            case let .emptyResponse(path):
                return "KEF returned no value for \(path)."
            case let .unsupportedEnumValue(path, value):
                return "KEF returned an unsupported value '\(value)' for \(path)."
            case let .unexpectedValue(path):
                return "KEF returned an unexpected value payload for \(path)."
            case let .httpStatus(status):
                return "KEF returned HTTP \(status)."
            case .passwordRequired:
                return "The KEF speaker requires authenticated writes. Set or clear the speaker's web password first, then try again."
            }
        }
    }

    private let injectedSession: URLSession?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession? = nil) {
        self.injectedSession = session
    }

    func readSpeakerStatusRaw(from speaker: DiscoveredSpeaker) async throws -> String {
        try await readRawStringValue(from: speaker, path: APIPath.speakerStatus)
    }

    func readStandbyMode(from speaker: DiscoveredSpeaker) async throws -> StandbyModeValue {
        let rawValue = try await readRawStringValue(from: speaker, path: APIPath.standbyMode)
        guard let standbyMode = StandbyModeValue(rawValue: rawValue) else {
            throw KefAPIClientError.unsupportedEnumValue(path: APIPath.standbyMode, value: rawValue)
        }
        return standbyMode
    }

    func setStandbyMode(_ mode: StandbyModeValue, on speaker: DiscoveredSpeaker) async throws {
        try await writeValue(.enumString(type: "kefStandbyMode", value: mode.rawValue), to: APIPath.standbyMode, on: speaker)
    }

    func readPhysicalSource(from speaker: DiscoveredSpeaker) async throws -> PhysicalSourceValue {
        let rawValue = try await readRawStringValue(from: speaker, path: APIPath.physicalSource)
        guard let source = PhysicalSourceValue(rawValue: rawValue) else {
            throw KefAPIClientError.unsupportedEnumValue(path: APIPath.physicalSource, value: rawValue)
        }
        return source
    }

    func setPhysicalSource(_ source: PhysicalSourceValue, on speaker: DiscoveredSpeaker) async throws {
        try await writeValue(.enumString(type: "kefPhysicalSource", value: source.rawValue), to: APIPath.physicalSource, on: speaker)
    }

    func requestPower(_ command: PowerCommand, on speaker: DiscoveredSpeaker) async throws {
        var lastError: Error?

        for path in [APIPath.powerTargetRequest, APIPath.powerTarget] {
            do {
                try await writeValue(.string(command.rawValue), to: path, on: speaker)
                return
            } catch {
                lastError = error
                AppLogger.api.warning("Power request on \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        throw lastError ?? KefAPIClientError.unexpectedValue(path: APIPath.powerTargetRequest)
    }

    func readValue(from speaker: DiscoveredSpeaker, path: String) async throws -> NSDKValue {
        let url = try url(for: APIPath.getData, speaker: speaker, queryItems: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "roles", value: "value")
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("close", forHTTPHeaderField: "Connection")

        let values: [NSDKValue] = try await perform(request)
        guard let value = values.first else {
            throw KefAPIClientError.emptyResponse(path)
        }
        return value
    }

    func writeValue(_ value: NSDKValue, to path: String, on speaker: DiscoveredSpeaker, role: String = "value") async throws {
        let authMode = try await readWebServerAuthMode(from: speaker)

        switch authMode {
        case .none:
            try await writePlainValue(value, to: path, on: speaker, role: role)
        case .setData, .all:
            do {
                try await writeSecureValue(value, to: path, on: speaker, role: role)
            } catch {
                if isAuthenticationFailure(error),
                   try await isWebPasswordConfigured(for: speaker) {
                    throw KefAPIClientError.passwordRequired
                }
                throw error
            }
        }
    }

    private func readRawStringValue(from speaker: DiscoveredSpeaker, path: String) async throws -> String {
        let value = try await readValue(from: speaker, path: path)
        guard let rawValue = value.rawString else {
            throw KefAPIClientError.unexpectedValue(path: path)
        }
        return rawValue
    }

    private func readWebServerAuthMode(from speaker: DiscoveredSpeaker) async throws -> WebServerAuthMode {
        do {
            let rawValue = try await readRawStringValue(from: speaker, path: APIPath.webserverAuthMode)
            guard let authMode = WebServerAuthMode(rawValue: rawValue) else {
                throw KefAPIClientError.unsupportedEnumValue(path: APIPath.webserverAuthMode, value: rawValue)
            }
            return authMode
        } catch {
            if isAuthenticationFailure(error) {
                return .all
            }
            throw error
        }
    }

    private func isWebPasswordConfigured(for speaker: DiscoveredSpeaker) async throws -> Bool {
        let url = try url(for: APIPath.getData, speaker: speaker, queryItems: [
            URLQueryItem(name: "path", value: APIPath.changePassword),
            URLQueryItem(name: "roles", value: "@all"),
            URLQueryItem(name: "type", value: "structure")
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("close", forHTTPHeaderField: "Connection")

        let (_, response) = try await makeSession().data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw KefAPIClientError.httpStatus(-1)
        }

        switch httpResponse.statusCode {
        case 200:
            return false
        case 401, 403:
            return true
        default:
            throw KefAPIClientError.httpStatus(httpResponse.statusCode)
        }
    }

    private func writePlainValue(_ value: NSDKValue, to path: String, on speaker: DiscoveredSpeaker, role: String) async throws {
        let url = try url(for: APIPath.setData, speaker: speaker)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.httpBody = try encoder.encode(NSDKSetDataRequest(path: path, role: role, value: value))

        _ = try await performRaw(request)
    }

    private func writeSecureValue(_ value: NSDKValue, to path: String, on speaker: DiscoveredSpeaker, role: String) async throws {
        let url = try url(for: APIPath.setData, speaker: speaker)
        let request = try KefRequestSecurity.makeSecureWriteRequest(
            url: url,
            path: path,
            role: role,
            value: value,
            password: ""
        )
        var closeRequest = request
        closeRequest.setValue("close", forHTTPHeaderField: "Connection")

        _ = try await performRaw(closeRequest)
    }

    private func url(for apiPath: String, speaker: DiscoveredSpeaker, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = speaker.host
        if speaker.port != 80 {
            components.port = speaker.port
        }
        components.path = apiPath
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw KefAPIClientError.invalidURL
        }

        return url
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await performRaw(request)
        return try decoder.decode(Response.self, from: data)
    }

    private func performRaw(_ request: URLRequest) async throws -> Data {
        let session = makeSession()
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            AppLogger.api.error("Request \(request.httpMethod ?? "GET", privacy: .public) \(request.url?.absoluteString ?? "<missing>", privacy: .public) failed before response: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KefAPIClientError.httpStatus(-1)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if let envelope = try? decoder.decode(NSDKErrorEnvelope.self, from: data) {
                throw envelope.error
            }
            throw KefAPIClientError.httpStatus(httpResponse.statusCode)
        }

        if let errorEnvelope = try? decoder.decode(NSDKErrorEnvelope.self, from: data),
           !errorEnvelope.error.message.isEmpty {
            throw errorEnvelope.error
        }

        return data
    }

    private func makeSession() -> URLSession {
        if let injectedSession {
            return injectedSession
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private func isAuthenticationFailure(_ error: Error) -> Bool {
        if let apiError = error as? KefAPIClientError,
           case let .httpStatus(status) = apiError,
           status == 401 || status == 403 {
            return true
        }

        if let remoteError = error as? NSDKRemoteError {
            return remoteError.message.localizedCaseInsensitiveContains("forbidden")
        }

        return false
    }
}
