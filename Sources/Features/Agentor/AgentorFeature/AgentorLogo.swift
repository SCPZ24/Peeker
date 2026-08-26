import AgentorProtocol
import AppKit
import SwiftUI

@MainActor
struct AgentorLogo: View {
    let agent: AgentKind
    var size: CGFloat = 22
    var tint: Color = .white

    var body: some View {
        Group {
            if let image = AgentorLogoCatalog.image(for: agent) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .colorMultiply(tint)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(agent.displayName)
    }
}

@MainActor
private enum AgentorLogoCatalog {
    private static let images: [String: NSImage] = {
        guard let resources = Bundle.main.resourceURL?.appendingPathComponent("Agentor/logos", isDirectory: true) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: AgentKind.allCases.compactMap { agent in
            let url = resources.appendingPathComponent("\(agent.rawValue).svg")
            return NSImage(contentsOf: url).map { (agent.rawValue, $0) }
        })
    }()

    static func image(for agent: AgentKind) -> NSImage? {
        images[agent.rawValue]
    }
}
