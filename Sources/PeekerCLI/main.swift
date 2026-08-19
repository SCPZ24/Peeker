import Foundation
import PeekerIPC
import PeekerProtocol

private let help = """
Usage: peeker <command>

Commands:
  --help                              Show this help
  --version                           Print CLI and protocol versions as JSON
  status                              Report whether Peeker App is running
  timer <command> [arguments]         Manage Timer
  pusher <command> [arguments]        Manage Pusher
  scheduler <command> [arguments]     Manage Scheduler

All command results except --help are one-line JSON. Peeker App must already be running
for feature commands; the CLI never starts the App or opens Peeker.sqlite.
"""

@main
private enum PeekerCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] {
            print(help)
            return
        }
        if arguments == ["--version"] {
            emit(.success(.object([
                "cliVersion": .string(PeekerContract.appVersion),
                "protocolVersion": .number(Double(PeekerContract.protocolVersion)),
            ])), toError: false)
            return
        }
        guard let command = arguments.first else {
            fail(PeekerError(code: "invalid_usage", message: "A command is required"))
        }

        let client = PeekerIPCClient()
        if command == "status" {
            guard arguments.count == 1 else {
                fail(PeekerError(code: "invalid_usage", message: "status accepts no arguments"))
            }
            do {
                let envelope = try await client.request(.status)
                finish(envelope)
            } catch PeekerIPCError.appNotRunning {
                emit(.success(.object(["running": .bool(false)])), toError: false)
            } catch let error as PeekerError {
                fail(error)
            } catch let error as PeekerIPCError {
                fail(error.peekerError)
            } catch {
                fail(PeekerError(code: "ipc_unavailable", message: error.localizedDescription))
            }
            return
        }

        guard ["timer", "pusher", "scheduler"].contains(command), arguments.count >= 2 else {
            fail(PeekerError(code: "invalid_usage", message: "Unknown or incomplete command"))
        }
        let featureArguments = Array(arguments.dropFirst())
        let category = commandCategory(for: featureArguments)
        do {
            let envelope = try await client.request(
                .command(CommandInvocation(
                    featureID: command,
                    arguments: featureArguments,
                    category: category
                )),
                mutation: category == .mutation
            )
            finish(envelope)
        } catch let error as PeekerError {
            fail(error)
        } catch let error as PeekerIPCError {
            fail(error.peekerError)
        } catch {
            fail(PeekerError(code: "ipc_unavailable", message: error.localizedDescription))
        }
    }

    private static func commandCategory(for arguments: [String]) -> CommandCategory {
        guard let command = arguments.first else { return .mutation }
        if command == "list" || command == "get" { return .read }
        if command == "config", arguments.dropFirst().first == "get" { return .read }
        if command == "source", arguments.dropFirst().first == "list" { return .read }
        return .mutation
    }

    private static func finish(_ envelope: PeekerEnvelope) -> Never {
        emit(envelope, toError: !envelope.ok)
        exit(envelope.error?.exitCode ?? 0)
    }

    private static func fail(_ error: PeekerError) -> Never {
        let envelope = PeekerEnvelope.failure(error)
        emit(envelope, toError: true)
        exit(error.exitCode)
    }

    private static func emit(_ envelope: PeekerEnvelope, toError: Bool) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(envelope)) ?? Data()
        let output = data + Data([0x0A])
        (toError ? FileHandle.standardError : FileHandle.standardOutput).write(output)
    }
}
