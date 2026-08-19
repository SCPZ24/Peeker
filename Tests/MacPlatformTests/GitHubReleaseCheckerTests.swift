import Foundation
import XCTest
@testable import MacPlatform

final class GitHubReleaseCheckerTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testLatestReleaseRequestsPeekerRepositoryAndReturnsFirstStableRelease() async throws {
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://api.github.com/repos/SCPZ24/Peeker/releases"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Peeker/2.0")

            let body = """
            [
              {
                "tag_name": "v2.0.0-beta.1",
                "body": "Beta",
                "html_url": "https://github.com/SCPZ24/Peeker/releases/tag/v2.0.0-beta.1",
                "draft": false,
                "prerelease": true
              },
              {
                "tag_name": "v1.1.0",
                "body": "Stable notes",
                "html_url": "https://github.com/SCPZ24/Peeker/releases/tag/v1.1.0",
                "draft": false,
                "prerelease": false
              },
              {
                "tag_name": "v1.0.0",
                "body": "Older",
                "html_url": "https://github.com/SCPZ24/Peeker/releases/tag/v1.0.0",
                "draft": false,
                "prerelease": false
              }
            ]
            """
            return (Self.response(for: request, statusCode: 200), Data(body.utf8))
        }

        let release = try await makeChecker().latestRelease()

        XCTAssertEqual(release?.version, "1.1.0")
        XCTAssertEqual(release?.notes, "Stable notes")
        XCTAssertEqual(
            release?.pageURL.absoluteString,
            "https://github.com/SCPZ24/Peeker/releases/tag/v1.1.0"
        )
    }

    func testLatestReleaseReturnsNilWhenRepositoryHasNoPublicStableRelease() async throws {
        URLProtocolStub.requestHandler = { request in
            let body = """
            [
              {
                "tag_name": "v1.0.0",
                "body": "Draft",
                "html_url": "https://github.com/SCPZ24/Peeker/releases/tag/v1.0.0",
                "draft": true,
                "prerelease": false
              }
            ]
            """
            return (Self.response(for: request, statusCode: 200), Data(body.utf8))
        }

        let release = try await makeChecker().latestRelease()

        XCTAssertNil(release)
    }

    func testLatestReleaseRejectsNonSuccessfulHTTPResponse() async {
        URLProtocolStub.requestHandler = { request in
            (Self.response(for: request, statusCode: 503), Data())
        }

        do {
            _ = try await makeChecker().latestRelease()
            XCTFail("Expected a bad-server-response error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badServerResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeChecker() -> GitHubReleaseChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return GitHubReleaseChecker(session: URLSession(configuration: configuration))
    }

    private static func response(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.requestHandler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
