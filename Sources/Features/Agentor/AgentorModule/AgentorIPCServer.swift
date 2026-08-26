import AgentorProtocol
import Darwin
import Foundation

final class AgentorIPCServer: @unchecked Sendable {
    typealias Handler = @Sendable (AgentorRequest) async -> AgentorResponse

    let socketURL: URL
    private let handler: Handler
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var acceptTask: Task<Void, Never>?
    private var ownsSocket = false

    init(socketURL: URL = AgentorPaths.socketURL(), handler: @escaping Handler) {
        self.socketURL = socketURL
        self.handler = handler
    }

    deinit { stop() }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor < 0 else { throw AgentorTransportError.activeServer }
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        var metadata = stat()
        if lstat(socketURL.path, &metadata) == 0 {
            if Self.canConnect(path: socketURL.path) { throw AgentorTransportError.activeServer }
            guard unlink(socketURL.path) == 0 || errno == ENOENT else { throw AgentorTransportError.unavailable }
        }

        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        guard server >= 0 else { throw AgentorTransportError.unavailable }
        var address = try AgentorUnixSocketAddress(path: socketURL.path)
        guard address.withSockAddr({ Darwin.bind(server, $0, $1) }) == 0,
              listen(server, 128) == 0,
              chmod(socketURL.path, 0o600) == 0 else {
            _ = Darwin.close(server)
            _ = unlink(socketURL.path)
            throw AgentorTransportError.unavailable
        }
        descriptor = server
        ownsSocket = true
        acceptTask = Task.detached { [weak self] in self?.acceptLoop(server) }
    }

    func stop() {
        lock.lock()
        let active = descriptor
        descriptor = -1
        let remove = ownsSocket
        ownsSocket = false
        let task = acceptTask
        acceptTask = nil
        lock.unlock()
        task?.cancel()
        if active >= 0 {
            _ = Darwin.shutdown(active, SHUT_RDWR)
            _ = Darwin.close(active)
        }
        if remove { try? FileManager.default.removeItem(at: socketURL) }
    }

    private func acceptLoop(_ server: Int32) {
        while !Task.isCancelled {
            let client = accept(server, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            Task.detached { [weak self] in await self?.handleClient(client) }
        }
    }

    private func handleClient(_ descriptor: Int32) async {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(descriptor, &uid, &gid) == 0, uid == geteuid() else {
            _ = Darwin.close(descriptor)
            return
        }
        let connection = AgentorSocketConnection(descriptor: descriptor, timeout: 2)
        let request: AgentorRequest
        do { request = try connection.read(AgentorRequest.self) }
        catch {
            connection.close()
            return
        }
        do {
            try request.validate()
            if request.kind == .question { connection.setTimeout(AgentorContract.questionWaitSeconds + 10) }
            try connection.write(await handler(request))
        } catch {
            try? connection.write(AgentorResponse.rejected("invalid_request"))
        }
        connection.close()
    }

    private static func canConnect(path: String) -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { _ = Darwin.close(descriptor) }
        guard var address = try? AgentorUnixSocketAddress(path: path) else { return false }
        return address.withSockAddr { Darwin.connect(descriptor, $0, $1) } == 0
    }
}
