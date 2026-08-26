import Darwin
import Foundation

public enum AgentorTransportError: Error, Sendable, Equatable {
    case unavailable
    case timedOut
    case malformedFrame
    case frameTooLarge
    case activeServer
    case peerRejected
}

public struct AgentorUnixSocketAddress {
    private var value: sockaddr_un
    public let length: socklen_t

    public init(path: String) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw AgentorTransportError.unavailable
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            bytes.withUnsafeBytes { buffer.copyBytes(from: $0) }
        }
        #if os(macOS)
        address.sun_len = UInt8(MemoryLayout<sa_family_t>.size + bytes.count)
        #endif
        value = address
        length = socklen_t(MemoryLayout<sockaddr_un>.size)
    }

    public mutating func withSockAddr<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) rethrows -> T {
        try withUnsafePointer(to: &value) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { try body($0, length) }
        }
    }
}

public final class AgentorSocketConnection: @unchecked Sendable {
    public let descriptor: Int32
    private let lock = NSLock()
    private var closed = false

    public init(descriptor: Int32, timeout: TimeInterval) {
        self.descriptor = descriptor
        var noSignal: Int32 = 1
        withUnsafePointer(to: &noSignal) {
            _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        setTimeout(timeout)
    }

    deinit { close() }

    public func setTimeout(_ timeout: TimeInterval) {
        var value = timeval(
            tv_sec: Int(timeout.rounded(.down)),
            tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1) * 1_000_000).rounded())
        )
        withUnsafePointer(to: &value) {
            _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        _ = Darwin.shutdown(descriptor, SHUT_RDWR)
        _ = Darwin.close(descriptor)
    }

    public func write<T: Encodable>(_ value: T) throws {
        try writeAll(AgentorFrameCodec.encode(value))
    }

    public func read<T: Decodable>(_ type: T.Type) throws -> T {
        let header = try readExactly(4)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= AgentorContract.maximumFrameBytes else { throw AgentorTransportError.frameTooLarge }
        let payload = try readExactly(Int(length))
        do { return try JSONDecoder.agentor.decode(type, from: payload) }
        catch { throw AgentorTransportError.malformedFrame }
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
                if count > 0 { offset += count; continue }
                if count < 0, errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw AgentorTransportError.timedOut }
                throw AgentorTransportError.unavailable
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
                if readCount == 0 { throw AgentorTransportError.unavailable }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw AgentorTransportError.timedOut }
                throw AgentorTransportError.unavailable
            }
        }
        return data
    }
}

public struct AgentorIPCClient: Sendable {
    public let socketURL: URL

    public init(socketURL: URL = AgentorPaths.socketURL()) {
        self.socketURL = socketURL
    }

    public func request(_ request: AgentorRequest, timeout: TimeInterval) throws -> AgentorResponse {
        guard FileManager.default.fileExists(atPath: socketURL.path) else { throw AgentorTransportError.unavailable }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw AgentorTransportError.unavailable }
        var address = try AgentorUnixSocketAddress(path: socketURL.path)
        guard address.withSockAddr({ Darwin.connect(descriptor, $0, $1) }) == 0 else {
            _ = Darwin.close(descriptor)
            throw AgentorTransportError.unavailable
        }
        let connection = AgentorSocketConnection(descriptor: descriptor, timeout: timeout)
        try connection.write(request)
        return try connection.read(AgentorResponse.self)
    }
}
