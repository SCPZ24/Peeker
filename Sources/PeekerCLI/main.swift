import Foundation
import PeekerIPC
import PeekerProtocol

private enum PeekerCLI {
    static func run() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let helpIndex = arguments.firstIndex(where: { $0 == "--help" || $0 == "-h" }) {
            guard helpIndex == arguments.index(before: arguments.endIndex),
                  let help = CLIHelp.text(for: Array(arguments[..<helpIndex])) else {
                fail(PeekerError(code: "invalid_usage", message: "Unknown or malformed help path"))
            }
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

        if command == "status" {
            guard arguments.count == 1 else {
                fail(PeekerError(code: "invalid_usage", message: "status accepts no arguments"))
            }
            let client = PeekerIPCClient()
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
        let client = PeekerIPCClient()
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

await PeekerCLI.run()
