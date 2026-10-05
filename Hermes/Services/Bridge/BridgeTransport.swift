import Foundation

/// JSON value used at the bridge boundary, where response fields evolve with
/// discovered capabilities. It keeps transport decoding independent of UI
/// models while still providing typed access to known fields.
nonisolated enum BridgeJSON: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([BridgeJSON])
    case object([String: BridgeJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([BridgeJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: BridgeJSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(_ key: String) -> BridgeJSON {
        guard case .object(let values) = self else { return .null }
        return values[key] ?? .null
    }

    var object: [String: BridgeJSON] {
        guard case .object(let value) = self else { return [:] }
        return value
    }

    var array: [BridgeJSON] {
        guard case .array(let value) = self else { return [] }
        return value
    }

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var int: Int? {
        switch self {
        case .integer(let value): Int(exactly: value)
        case .number(let value) where value.isFinite && value.rounded(.towardZero) == value: Int(exactly: value)
        default: nil
        }
    }

    var double: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }

    var bool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    static func string(_ value: String?) -> BridgeJSON { value.map(BridgeJSON.string) ?? .null }
    static func integer(_ value: Int?) -> BridgeJSON { value.map { .integer(Int64($0)) } ?? .null }
}

nonisolated enum BridgeHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

nonisolated struct BridgeSSEFrame: Sendable, Equatable {
    /// The SSE id in effect for this frame. The bridge uses it as a replay cursor.
    let id: String?
    let event: String?
    let data: String
}

/// A per-request delegate prevents an authenticated bridge request from being
/// redirected to a different origin (or silently upgraded/downgraded).
nonisolated final class BridgeNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// A single bridge HTTP/SSE transport. It never retries a request: command
/// retries require a deliberate reconciliation step at the service layer.
actor BridgeTransport {
    private let baseURL: URL
    private let hostID: String
    private let credentials: any BridgeCredentialStore
    private let session: URLSession
    private let requestTimeout: TimeInterval

    init(
        baseURL: URL,
        hostID: String,
        credentialStore: any BridgeCredentialStore,
        session: URLSession? = nil,
        requestTimeout: TimeInterval = 30
    ) throws {
        guard Self.isAllowedBaseURL(baseURL), requestTimeout > 0 else {
            throw HermesError.rejected("The bridge address must use HTTPS. Simulator loopback may use HTTP.")
        }
        self.baseURL = baseURL
        self.hostID = hostID
        self.credentials = credentialStore
        self.session = session ?? Self.makeSession()
        self.requestTimeout = requestTimeout
    }

    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// Safely encodes an opaque bridge identifier for a single URL path segment.
    nonisolated static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// `path` is relative to `/mobile/v1`, for example `runs` or
    /// `conversations/<percent-encoded-id>/messages`.
    func request(
        method: BridgeHTTPMethod = .get,
        path: String,
        query: [URLQueryItem] = [],
        body: BridgeJSON? = nil,
        idempotencyKey: UUID? = nil,
        responseTimeout: TimeInterval? = nil
    ) async throws -> BridgeJSON {
        if let responseTimeout, !responseTimeout.isFinite || responseTimeout <= 0 {
            throw HermesError.rejected("The bridge response timeout must be finite and positive.")
        }
        let isMutation = method != .get
        guard !isMutation || idempotencyKey != nil else {
            throw HermesError.rejected("A unique idempotency key is required for this action.")
        }

        var request: URLRequest
        do {
            request = try makeRequest(method: method, path: path, query: query,
                                      body: body, idempotencyKey: idempotencyKey,
                                      accept: "application/json")
        } catch let error as HermesError {
            throw error
        } catch {
            throw HermesError.rejected("The bridge request could not be prepared.")
        }
        if let responseTimeout { request.timeoutInterval = responseTimeout }

        do {
            let (data, response) = try await session.data(for: request, delegate: BridgeNoRedirectDelegate())
            guard let response = response as? HTTPURLResponse else {
                throw HermesError.bridgeUnreachable
            }
            try Self.validate(response: response, data: data, mutationKey: idempotencyKey)
            guard !data.isEmpty else { return .object([:]) }
            do {
                return try JSONDecoder().decode(BridgeJSON.self, from: data)
            } catch {
                if let idempotencyKey { throw HermesError.commandUncertain(idempotencyKey) }
                throw HermesError.rejected("The bridge returned an invalid response.")
            }
        } catch is CancellationError {
            if let idempotencyKey { throw HermesError.commandUncertain(idempotencyKey) }
            throw CancellationError()
        } catch let error as HermesError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled {
                if let idempotencyKey { throw HermesError.commandUncertain(idempotencyKey) }
                throw CancellationError()
            }
            throw Self.map(error: error, mutationKey: idempotencyKey)
        } catch {
            if isMutation, let idempotencyKey {
                throw HermesError.commandUncertain(idempotencyKey)
            }
            throw HermesError.bridgeUnreachable
        }
    }

    /// Convenience surface for service clients that keep HTTP verbs and query
    /// parameters as ordinary strings. The bridge paths remain relative to v1.
    func request(
        method: String,
        path: String,
        query: [String: String] = [:],
        body: BridgeJSON? = nil,
        idempotencyKey: UUID? = nil,
        responseTimeout: TimeInterval? = nil
    ) async throws -> BridgeJSON {
        guard let verb = BridgeHTTPMethod(rawValue: method.uppercased()) else {
            throw HermesError.rejected("The bridge request method is invalid.")
        }
        let items = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        return try await request(method: verb, path: path, query: items,
                                 body: body, idempotencyKey: idempotencyKey, responseTimeout: responseTimeout)
    }

    /// Downloads a bridge-registered artifact or Kanban attachment as bytes.
    /// The server chooses the path; callers never provide a Studio filesystem path.
    func download(path: String, query: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        let request: URLRequest
        do {
            request = try makeRequest(method: .get, path: path, query: query,
                                      body: nil, idempotencyKey: nil,
                                      accept: "application/octet-stream, application/pdf, image/*, text/*")
        } catch let error as HermesError {
            throw error
        } catch {
            throw HermesError.rejected("The bridge request could not be prepared.")
        }

        do {
            let (data, response) = try await session.data(for: request, delegate: BridgeNoRedirectDelegate())
            guard let response = response as? HTTPURLResponse else { throw HermesError.bridgeUnreachable }
            try Self.validate(response: response, data: data, mutationKey: nil)
            return (data, response)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HermesError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw Self.map(error: error, mutationKey: nil)
        } catch {
            throw HermesError.bridgeUnreachable
        }
    }

    func download(path: String, query: [String: String]) async throws -> (Data, HTTPURLResponse) {
        let items = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        return try await download(path: path, query: items)
    }

    /// Opens the bridge's one multiplexed SSE feed. The owner of this client
    /// implements reconnect/backoff and passes its last committed cursor here.
    func events(after cursor: String?) -> AsyncThrowingStream<BridgeSSEFrame, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(128)) { continuation in
            let task = Task {
                do {
                    var query: [URLQueryItem] = []
                    if let cursor { query.append(URLQueryItem(name: "after", value: cursor)) }
                    let request = try self.makeStreamRequest(path: "events/stream", query: query)
                    let (bytes, response) = try await self.session.bytes(for: request, delegate: BridgeNoRedirectDelegate())
                    guard let response = response as? HTTPURLResponse else {
                        throw HermesError.bridgeUnreachable
                    }
                    try Self.validate(response: response, data: Data(), mutationKey: nil)
                    guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else {
                        throw HermesError.rejected("The bridge did not open an event stream.")
                    }

                    var parser = BridgeSSEByteParser()
                    // AsyncBytes.lines omits empty lines on some Foundation versions;
                    // SSE blank separators must be retained exactly.
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if let frame = try parser.consume(byte: byte) {
                            if frame.event == "stream.resync_required" {
                                let body = frame.data.data(using: .utf8) ?? Data()
                                let cursor = (try? JSONDecoder().decode(BridgeJSON.self, from: body))?["error"]["details"]["cursor"].string ?? ""
                                throw HermesError.resyncRequired(cursor)
                            }
                            switch continuation.yield(frame) {
                            case .enqueued:
                                break
                            case .dropped:
                                // Reconnect from the last frame the app durably applied.
                                // Never skip a frame just because the consumer fell behind.
                                continuation.finish(throwing: HermesError.bridgeUnreachable)
                                return
                            case .terminated:
                                return
                            @unknown default:
                                return
                            }
                        }
                    }
                    if !Task.isCancelled { continuation.finish() }
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as HermesError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: Self.map(error: error, mutationKey: nil))
                } catch {
                    continuation.finish(throwing: HermesError.bridgeUnreachable)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func makeStreamRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        try makeRequest(method: .get, path: path, query: query, body: nil,
                        idempotencyKey: nil, accept: "text/event-stream")
    }

    private func makeRequest(
        method: BridgeHTTPMethod,
        path: String,
        query: [URLQueryItem],
        body: BridgeJSON?,
        idempotencyKey: UUID?,
        accept: String
    ) throws -> URLRequest {
        let savedToken: String?
        do {
            savedToken = try credentials.token(forHostID: hostID)
        } catch {
            throw HermesError.rejected("The saved bridge credential is unavailable in secure storage.")
        }
        guard let token = savedToken, !token.isEmpty else {
            throw HermesError.unauthorized
        }
        guard let url = Self.endpoint(baseURL: baseURL, path: path, query: query) else {
            throw HermesError.rejected("The bridge request path is invalid.")
        }

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = method.rawValue
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let idempotencyKey {
            request.setValue(idempotencyKey.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        } else if method != .get {
            // The bridge contract requires a JSON object even for empty actions.
            request.httpBody = try JSONEncoder().encode(BridgeJSON.object([:]))
        }
        return request
    }

    private static func validate(response: HTTPURLResponse, data: Data, mutationKey: UUID?) throws {
        guard (200..<300).contains(response.statusCode) else {
            let code: String? = (try? JSONDecoder().decode(BridgeJSON.self, from: data))?["error"]["code"].string
            switch response.statusCode {
            case 401: throw HermesError.unauthorized
            case 404: throw HermesError.notFound
            case 409:
                if code == "bot_model_confirmation_required" { throw HermesError.botModelConfirmation }
                if code == "command_uncertain", let mutationKey {
                    throw HermesError.commandUncertain(mutationKey)
                }
                if code == "resync_required" {
                    let cursor = (try? JSONDecoder().decode(BridgeJSON.self, from: data))?["error"]["details"]["cursor"].string ?? ""
                    throw HermesError.resyncRequired(cursor)
                }
                if code == "exact_target_unavailable" {
                    throw HermesError.rejected("This request can only be handled on the Studio.")
                }
                if code == "stale_attention" {
                    throw HermesError.rejected("This question is no longer available. Refresh the conversation.")
                }
                throw HermesError.rejected("The bridge rejected a conflicting or stale request.")
            case 503:
                if let mutationKey {
                    throw HermesError.commandUncertain(mutationKey)
                }
                throw HermesError.hermesOffline
            case 403: throw HermesError.rejected("This action isn't permitted by the bridge.")
            case 400, 413, 415, 422: throw HermesError.rejected("The bridge rejected the request. Check its fields and try again.")
            case 502:
                if let mutationKey { throw HermesError.commandUncertain(mutationKey) }
                throw HermesError.rejected("Hermes could not complete the bridge request.")
            default:
                if response.statusCode >= 500, let mutationKey {
                    throw HermesError.commandUncertain(mutationKey)
                }
                throw HermesError.rejected("The bridge request failed. Try again after checking host status.")
            }
        }
    }

    private static func map(error: URLError, mutationKey: UUID?) -> HermesError {
        if let mutationKey { return .commandUncertain(mutationKey) }
        if error.code == .timedOut { return .timeout }
        return .bridgeUnreachable
    }

    private static func endpoint(baseURL: URL, path: String, query: [URLQueryItem]) -> URL? {
        guard !path.contains("?") && !path.contains("#") && !path.contains("\\") else { return nil }
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        let basePath = urlComponents.path.hasSuffix("/") ? String(urlComponents.path.dropLast()) : urlComponents.path
        urlComponents.percentEncodedPath = "\(basePath)/mobile/v1/\(trimmed)"
        urlComponents.queryItems = query.isEmpty ? nil : query
        return urlComponents.url
    }

    private static func isAllowedBaseURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else { return false }
        if scheme == "https" { return true }
        #if DEBUG && targetEnvironment(simulator)
        return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
        #else
        return false
        #endif
    }
}

/// Minimal SSE line parser implementing data/event/id and multi-line data.
/// Comments and retry hints are ignored. The last event id follows SSE rules.
nonisolated struct BridgeSSEParser: Sendable {
    private(set) var lastEventID: String?
    private var eventName: String?
    private var dataLines: [String] = []
    private var firstLine = true

    mutating func consume(line input: String) -> BridgeSSEFrame? {
        var line = input
        if firstLine {
            firstLine = false
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
        }
        if line.isEmpty {
            defer {
                eventName = nil
                dataLines.removeAll(keepingCapacity: true)
            }
            guard !dataLines.isEmpty else { return nil }
            return BridgeSSEFrame(id: lastEventID, event: eventName, data: dataLines.joined(separator: "\n"))
        }
        guard !line.hasPrefix(":") else { return nil }

        let field: Substring
        let value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            var remainder = line[line.index(after: colon)...]
            if remainder.first == " " { remainder = remainder.dropFirst() }
            value = remainder
        } else {
            field = Substring(line)
            value = ""
        }

        switch field {
        case "data": dataLines.append(String(value))
        case "event": eventName = String(value)
        case "id":
            if !value.contains("\0") { lastEventID = String(value) }
        default: break
        }
        return nil
    }
}

/// Preserves LF/CR/CRLF boundaries and UTF-8 split across network chunks.
nonisolated struct BridgeSSEByteParser: Sendable {
    private var line: [UInt8] = []
    private var skipLF = false
    private var parser = BridgeSSEParser()

    mutating func consume(byte: UInt8) throws -> BridgeSSEFrame? {
        if skipLF { skipLF = false; if byte == 10 { return nil } }
        if byte == 13 || byte == 10 {
            skipLF = byte == 13
            let text = String(decoding: line, as: UTF8.self)
            line.removeAll(keepingCapacity: true)
            return parser.consume(line: text)
        }
        guard line.count < 4 * 1024 * 1024 else { throw HermesError.rejected("Bridge event exceeds the streaming limit") }
        line.append(byte)
        return nil
    }
}
