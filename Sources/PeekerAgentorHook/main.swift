import AgentorProtocol
import Foundation

private func runAgentorHook() {
    let arguments = CommandLine.arguments
    guard arguments.count == 3,
          let agent = AgentKind(rawValue: arguments[1]),
          let input = try? FileHandle.standardInput.read(upToCount: AgentorContract.maximumFrameBytes + 1),
          input.count <= AgentorContract.maximumFrameBytes else { return }
    let operation = arguments[2]
    let client = AgentorIPCClient()

    switch operation {
    case "state", "resolved", "writeback-result":
        guard let request = AgentorHookNormalizer.state(agent: agent, data: input) else { return }
        _ = try? client.request(request, timeout: 2)
    case "question":
        guard let (question, claudeContext) = AgentorHookNormalizer.question(agent: agent, data: input),
              let response = try? client.request(AgentorRequest(question: question), timeout: AgentorContract.questionWaitSeconds + 5) else { return }
        if let claudeContext {
            if let output = AgentorHookNormalizer.claudeOutput(response: response, context: claudeContext) {
                FileHandle.standardOutput.write(output)
            }
        } else if let output = try? JSONEncoder.agentor.encode(response) {
            FileHandle.standardOutput.write(output)
        }
    default:
        return
    }
}

runAgentorHook()
