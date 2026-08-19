import Darwin
import Foundation
import PeekerProtocol

public enum PeekerIPCError: Error, Equatable, Sendable {
    case appNotRunning
    case unavailable(String)
    case timedOut
    case frameTooLarge
    case malformedFrame
    case peerRejected
    case activeServer
    case outcomeUnknown

    public var peekerError: PeekerError {
        switch self {
        case .appNotRunning:
            PeekerError(code: "app_not_running", message: "Peeker App is not running")
        case let .unavailable(message):
            PeekerError(code: "ipc_unavailable", message: message)
        case .timedOut:
            PeekerError(code: "ipc_timeout", message: "IPC request timed out")
        case .frameTooLarge:
            PeekerError(code: "validation_error", message: "IPC frame exceeds 16 MiB")
        case .malformedFrame:
            PeekerError(code: "ipc_unavailable", message: "Malformed IPC frame")
        case .peerRejected:
            PeekerError(code: "ipc_unavailable", message: "IPC peer user was rejected")
        case .activeServer:
            PeekerError(code: "conflict", message: "An IPC server is already active")
        case .outcomeUnknown:
            PeekerError(code: "outcome_unknown", message: "The request may have committed before IPC disconnected")
        }
    }
}

public enum PeekerIPCPaths {
    public static func socketURL(
        temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ) -> URL {
        temporaryDirectory
            .appendingPathComponent("com.scpz24.Peeker", isDirectory: true)
            .appendingPathComponent("ipc-v1.sock", isDirectory: false)
    }
}

public enum PeekerFrameCodec {
    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= PeekerContract.maximumFrameBytes else { throw PeekerIPCError.frameTooLarge }
        var length = UInt32(payload.count).bigEndian
        var result = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        result.append(payload)
        return result
    }

    public static func decode(_ frame: Data) throws -> Data {
        guard frame.count >= 4 else { throw PeekerIPCError.malformedFrame }
        let length = frame.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= PeekerContract.maximumFrameBytes else { throw PeekerIPCError.frameTooLarge }
        guard frame.count == 4 + Int(length) else { throw PeekerIPCError.malformedFrame }
        return frame.dropFirst(4)
    }
}

private struct UnixSocketAddress {
    var value: sockaddr_un
    let length: socklen_t

    init(path: String) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= capacity else {
            throw PeekerIPCError.unavailable("IPC socket path is too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            bytes.withUnsafeBytes { source in
                buffer.copyBytes(from: source)
            }
        }
        #if os(macOS)
        address.sun_len = UInt8(MemoryLayout<sa_family_t>.size + bytes.count)
        #endif
        value = address
        length = socklen_t(MemoryLayout<sockaddr_un>.size)
    }

    mutating func withSockAddr<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) rethrows -> T {
        try withUnsafePointer(to: &value) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                try body(pointer, length)
            }
        }
    }
}

private final class SocketConnection: @unchecked Sendable {
    private let descriptor: Int32
    private let lock = NSLock()
    private var closed = false

    init(descriptor: Int32, timeout: TimeInterval) {
        self.descriptor = descriptor
        var value = timeval(
            tv_sec: Int(timeout.rounded(.down)),
            tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1) * 1_000_000).rounded())
        )
        withUnsafePointer(to: &value) { pointer in
            _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
        }
    }

    deinit { closeConnection() }

    func closeConnection() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        _ = Darwin.shutdown(descriptor, SHUT_RDWR)
        _ = Darwin.close(descriptor)
    }

    func writeFrame<T: Encodable>(_ value: T) throws {
        let payload = try JSONEncoder().encode(value)
        let frame = try PeekerFrameCodec.encode(payload)
        try writeAll(frame)
    }

    func readFrame<T: Decodable>(_ type: T.Type) throws -> T {
        let header = try readExactly(4)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= PeekerContract.maximumFrameBytes else { throw PeekerIPCError.frameTooLarge }
        let payload = try readExactly(Int(length))
        do { return try JSONDecoder().decode(type, from: payload) }
        catch { throw PeekerIPCError.malformedFrame }
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
                if count > 0 { offset += count; continue }
                if count < 0, errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw PeekerIPCError.timedOut }
                throw PeekerIPCError.unavailable(String(cString: strerror(errno)))
            }
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            while offset < count {
                let readCount = Darwin.read(descriptor, base.advanced(by: offset), count - offset)
                if readCount > 0 { offset += readCount; continue }
                if readCount == 0 { throw PeekerIPCError.unavailable("IPC connection closed") }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw PeekerIPCError.timedOut }
                throw PeekerIPCError.unavailable(String(cString: strerror(errno)))
            }
        }
        return data
    }
}

public struct PeekerIPCClient: Sendable {
    public let socketURL: URL
    public let connectionTimeout: TimeInterval
    public let requestTimeout: TimeInterval

    public init(
        socketURL: URL = PeekerIPCPaths.socketURL(),
        connectionTimeout: TimeInterval = 2,
        requestTimeout: TimeInterval = 120
    ) {
        self.socketURL = socketURL
        self.connectionTimeout = connectionTimeout
        self.requestTimeout = requestTimeout
    }

    public func request(_ request: IPCRequest, mutation: Bool = false) async throws -> PeekerEnvelope {
        try await Task.detached {
            guard FileManager.default.fileExists(atPath: socketURL.path) else {
                throw PeekerIPCError.appNotRunning
            }
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw PeekerIPCError.unavailable(String(cString: strerror(errno))) }
            var address = try UnixSocketAddress(path: socketURL.path)
            guard address.withSockAddr({ Darwin.connect(descriptor, $0, $1) }) == 0 else {
                let code = errno
                _ = Darwin.close(descriptor)
                if code == ECONNREFUSED || code == ENOENT { throw PeekerIPCError.appNotRunning }
                throw PeekerIPCError.unavailable(String(cString: strerror(code)))
            }
            let connection = SocketConnection(descriptor: descriptor, timeout: requestTimeout)
            do {
                try connection.writeFrame(IPCRequest.handshake(ProtocolHandshake()))
                let handshake = try connection.readFrame(IPCResponse.self)
                guard handshake.protocolVersion == PeekerContract.protocolVersion,
                      handshake.envelope.ok else {
                    throw handshake.envelope.error ?? PeekerError(code: "protocol_mismatch", message: "IPC protocol mismatch")
                }
                try connection.writeFrame(request)
                return try connection.readFrame(IPCResponse.self).envelope
            } catch let error as PeekerIPCError where mutation {
                if case .timedOut = error { throw error }
                throw PeekerIPCError.outcomeUnknown
            }
        }.value
    }
}

public final class PeekerIPCServer: @unchecked Sendable {
    public typealias Handler = @Sendable (IPCRequest) async -> PeekerEnvelope

    public let socketURL: URL
    private let handler: Handler
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var ownsSocket = false
    private var acceptTask: Task<Void, Never>?

    public init(socketURL: URL = PeekerIPCPaths.socketURL(), handler: @escaping Handler) {
        self.socketURL = socketURL
        self.handler = handler
    }

    deinit { stop() }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor < 0 else { throw PeekerIPCError.activeServer }
        var address = try UnixSocketAddress(path: socketURL.path)
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        var staleMetadata = stat()
        if lstat(socketURL.path, &staleMetadata) == 0 {
            if Self.canConnect(to: socketURL.path) { throw PeekerIPCError.activeServer }
            if unlink(socketURL.path) != 0, errno != ENOENT {
                throw PeekerIPCError.unavailable(String(cString: strerror(errno)))
            }
        }

        let serverDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverDescriptor >= 0 else { throw PeekerIPCError.unavailable(String(cString: strerror(errno))) }
        guard address.withSockAddr({ Darwin.bind(serverDescriptor, $0, $1) }) == 0,
              listen(serverDescriptor, 16) == 0 else {
            let message = String(cString: strerror(errno))
            _ = Darwin.close(serverDescriptor)
            throw PeekerIPCError.unavailable(message)
        }
        guard chmod(socketURL.path, 0o600) == 0 else {
            let message = String(cString: strerror(errno))
            _ = Darwin.close(serverDescriptor)
            _ = unlink(socketURL.path)
            throw PeekerIPCError.unavailable(message)
        }
        descriptor = serverDescriptor
        ownsSocket = true
        acceptTask = Task.detached { [weak self] in self?.acceptLoop(serverDescriptor) }
    }

    public func stop() {
        lock.lock()
        let activeDescriptor = descriptor
        descriptor = -1
        let shouldRemoveSocket = ownsSocket
        ownsSocket = false
        let task = acceptTask
        acceptTask = nil
        lock.unlock()
        task?.cancel()
        if activeDescriptor >= 0 {
            _ = Darwin.shutdown(activeDescriptor, SHUT_RDWR)
            _ = Darwin.close(activeDescriptor)
        }
        if shouldRemoveSocket { try? FileManager.default.removeItem(at: socketURL) }
    }

    private func acceptLoop(_ serverDescriptor: Int32) {
        while !Task.isCancelled {
            let client = accept(serverDescriptor, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            Task.detached { [weak self] in await self?.handleClient(client) }
        }
    }

    private func handleClient(_ descriptor: Int32) async {
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(descriptor, &peerUID, &peerGID) == 0, peerUID == geteuid() else {
            _ = Darwin.close(descriptor)
            return
        }
        let connection = SocketConnection(descriptor: descriptor, timeout: 120)
        do {
            let first = try connection.readFrame(IPCRequest.self)
            guard case let .handshake(handshake) = first else { throw PeekerIPCError.malformedFrame }
            guard handshake.protocolVersion == PeekerContract.protocolVersion else {
                try connection.writeFrame(IPCResponse(envelope: .failure(PeekerError(
                    code: "protocol_mismatch",
                    message: "CLI/App protocol versions differ"
                ))))
                return
            }
            try connection.writeFrame(IPCResponse(envelope: .success(.object([
                "protocolVersion": .number(Double(PeekerContract.protocolVersion)),
            ]))))
            let request = try connection.readFrame(IPCRequest.self)
            guard case .handshake = request else {
                try connection.writeFrame(IPCResponse(envelope: await handler(request)))
                return
            }
            throw PeekerIPCError.malformedFrame
        } catch {
            connection.closeConnection()
        }
    }

    private static func canConnect(to path: String) -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { _ = Darwin.close(descriptor) }
        guard var address = try? UnixSocketAddress(path: path) else { return false }
        return address.withSockAddr { Darwin.connect(descriptor, $0, $1) } == 0
    }
}
