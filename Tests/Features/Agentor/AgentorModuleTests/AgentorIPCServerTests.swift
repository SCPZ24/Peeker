import AgentorProtocol
import Foundation
import XCTest
@testable import AgentorModule

final class AgentorIPCServerTests: XCTestCase {
    func testServerAcceptsSameUserAndReturnsAck() async throws {
        let root = URL(fileURLWithPath: "/tmp/agentor-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let socket = AgentorPaths.socketURL(applicationSupportDirectory: root)
        let server = AgentorIPCServer(socketURL: socket) { request in
            request.event?.eventID == "event" ? .ack : .rejected("unexpected")
        }
        try server.start()
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let event = AgentorEvent(
            eventID: "event",
            session: AgentorSessionKey(agent: .pi, sessionID: "session"),
            name: .turnStarted
        )
        let response = try await Task.detached {
            try AgentorIPCClient(socketURL: socket).request(AgentorRequest(event: event), timeout: 2)
        }.value

        XCTAssertEqual(response, .ack)
        let attributes = try FileManager.default.attributesOfItem(atPath: socket.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testServerReplacesStaleSocketButNotActiveServer() throws {
        let root = URL(fileURLWithPath: "/tmp/agentor-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let socket = AgentorPaths.socketURL(applicationSupportDirectory: root)
        try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: socket.path, contents: Data())
        let first = AgentorIPCServer(socketURL: socket) { _ in .ack }
        try first.start()
        defer {
            first.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let second = AgentorIPCServer(socketURL: socket) { _ in .ack }
        XCTAssertThrowsError(try second.start()) { error in
            XCTAssertEqual(error as? AgentorTransportError, .activeServer)
        }
    }
}
