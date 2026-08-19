import Foundation
import XCTest
import PeekerProtocol
@testable import PeekerIPC

final class PeekerIPCTests: XCTestCase {
    func testFrameCodecUsesBigEndianLengthAndRejectsOversizedFrames() throws {
        let frame = try PeekerFrameCodec.encode(Data("abc".utf8))
        XCTAssertEqual(Array(frame.prefix(4)), [0, 0, 0, 3])
        XCTAssertEqual(try PeekerFrameCodec.decode(frame), Data("abc".utf8))
        XCTAssertThrowsError(try PeekerFrameCodec.decode(Data([0, 0, 0, 4, 1])))
    }

    func testClientAndServerCompleteHandshakeAndOneRequest() async throws {
        let socket = temporarySocket()
        let server = PeekerIPCServer(socketURL: socket) { request in
            guard case .status = request else {
                return .failure(PeekerError(code: "invalid_usage", message: "unexpected"))
            }
            return .success(.object(["running": .bool(true)]))
        }
        try server.start()
        defer { server.stop() }

        let envelope = try await PeekerIPCClient(socketURL: socket).request(.status)
        XCTAssertEqual(envelope, .success(.object(["running": .bool(true)])))

        let attributes = try FileManager.default.attributesOfItem(atPath: socket.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testServerRemovesStaleSocketButDoesNotReplaceActiveServer() async throws {
        let socket = temporarySocket()
        try FileManager.default.createDirectory(
            at: socket.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stale".utf8).write(to: socket)
        let first = PeekerIPCServer(socketURL: socket) { _ in .success() }
        try first.start()
        defer { first.stop() }

        do {
            let second = PeekerIPCServer(socketURL: socket) { _ in .success() }
            XCTAssertThrowsError(try second.start()) { error in
                XCTAssertEqual(error as? PeekerIPCError, .activeServer)
            }
        }

        let envelope = try await PeekerIPCClient(socketURL: socket).request(.status)
        XCTAssertTrue(envelope.ok)
    }

    func testMissingSocketIsAppNotRunning() async {
        do {
            _ = try await PeekerIPCClient(socketURL: temporarySocket()).request(.status)
            XCTFail("Expected appNotRunning")
        } catch {
            XCTAssertEqual(error as? PeekerIPCError, .appNotRunning)
        }
    }

    private func temporarySocket() -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("pkr-\(UUID().uuidString.prefix(8))", isDirectory: true)
            .appendingPathComponent("s")
    }
}
