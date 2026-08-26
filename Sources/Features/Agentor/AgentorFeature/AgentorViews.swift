import AgentorProtocol
import FunctionCardKit
import SwiftUI

@MainActor
public enum AgentorFeatureFactory {
    public static let metrics = FunctionCardMetrics(
        compactWidth: 340,
        compactHeight: 32,
        compactLeadingWidth: 168,
        compactTrailingWidth: 168,
        expandedWidth: 640,
        expandedHeight: 300
    )

    public static func make(store: AgentorStore) -> FunctionCardRegistration {
        FunctionCardRegistration(
            id: .agentor,
            name: "Agentor",
            systemImage: "cpu",
            settingsSystemImage: "cpu",
            defaultOrder: 3,
            introducedConfigurationVersion: 3,
            metrics: metrics,
            isCompactEligible: { store.activeSessionCount > 0 },
            makeCompactLeadingView: { AnyView(AgentorCompactLeadingView(store: store)) },
            makeCompactTrailingView: { AnyView(AgentorCompactTrailingView(store: store)) },
            makeExpandedView: { AnyView(AgentorExpandedView(store: store)) },
            makeSettingsView: { AnyView(AgentorSettingsView(store: store)) }
        )
    }
}

private struct AgentorCompactLeadingView: View {
    @Bindable var store: AgentorStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                if store.activeSessionCount == 1, let session = store.sessions.first {
                    AgentorGlyph(agent: session.key.agent)
                        .overlay {
                            Circle()
                                .trim(from: 0.08, to: 0.42)
                                .stroke(.white.opacity(0.45), lineWidth: 1)
                                .rotationEffect(reduceMotion ? .zero : .degrees(elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8 * 360))
                                .frame(width: 25, height: 25)
                        }
                } else if store.activeSessionCount == 2 {
                    ForEach(Array(store.sessions.prefix(2).enumerated()), id: \.element.key) { index, session in
                        AgentorGlyph(agent: session.key.agent)
                            .opacity(reduceMotion ? 1 : 0.6 + 0.4 * breathing(elapsed + Double(index) * 0.8))
                    }
                } else {
                    Text("\(store.activeSessionCount)")
                        .font(.headline.monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.16), in: Capsule())
                }
            }
        }
    }

    private func breathing(_ elapsed: TimeInterval) -> Double {
        (sin(elapsed / 1.6 * .pi * 2) + 1) / 2
    }
}

private struct AgentorCompactTrailingView: View {
    @Bindable var store: AgentorStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                if store.hasPendingQuestions {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                        .overlay {
                            Circle()
                                .stroke(.orange.opacity(reduceMotion ? 0.5 : 0.7 * (1 - pulse(elapsed))))
                                .scaleEffect(reduceMotion ? 1 : 0.8 + pulse(elapsed) * 0.45)
                        }
                    Text("等待回答").foregroundStyle(.orange)
                } else if store.activeSessionCount == 1, let session = store.sessions.first {
                    Text(session.status.displayName)
                } else if store.activeSessionCount == 2 {
                    Text("2").font(.headline.monospacedDigit())
                } else {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle().frame(width: 4, height: 4)
                                .offset(y: reduceMotion ? 0 : CGFloat(sin((elapsed / 2.4 + Double(index) / 3) * .pi * 2) * 3))
                        }
                    }
                    Text("\(store.activeSessionCount)").monospacedDigit()
                }
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func pulse(_ elapsed: TimeInterval) -> CGFloat {
        CGFloat(elapsed.truncatingRemainder(dividingBy: 1.2) / 1.2)
    }
}

private struct AgentorGlyph: View {
    let agent: AgentKind

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .frame(width: 22, height: 22)
            .accessibilityLabel(agent.displayName)
    }

    private var systemImage: String {
        switch agent {
        case .claude: "sparkles"
        case .openCode: "chevron.left.forwardslash.chevron.right"
        case .hermes: "paperplane"
        case .pi: "function"
        case .codex: "terminal"
        }
    }
}

private struct AgentorExpandedView: View {
    @Bindable var store: AgentorStore

    var body: some View {
        Group {
            if store.sessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("没有运行中的 Agent")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text("Agent 开始执行后会显示在这里。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.sessions) { session in
                            AgentorSessionRow(store: store, session: session)
                        }
                    }
                }
            }
        }
    }
}

private struct AgentorSessionRow: View {
    @Bindable var store: AgentorStore
    let session: AgentorSessionState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AgentorGlyph(agent: session.key.agent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.key.agent.displayName).font(.caption).foregroundStyle(.white.opacity(0.72))
                    Text(session.label).font(.headline).foregroundStyle(.white).lineLimit(1)
                }
                Spacer()
                if !session.activeSubagentIDs.isEmpty {
                    Text("并行子任务 ×\(session.activeSubagentIDs.count)")
                        .font(.caption2).foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    Text(duration(context.date.timeIntervalSince(session.startedAt)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.72))
                }
                Text(session.status.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(session.status == .waitingForAnswer ? .orange : .white.opacity(0.82))
            }
            if let notice = session.resolutionNotice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.white.opacity(0.78))
            }
            ForEach(store.pendingRequests(for: session)) { pending in
                AgentorQuestionForm(store: store, pending: pending)
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct AgentorQuestionForm: View {
    @Bindable var store: AgentorStore
    let pending: AgentorPendingRequest
    @FocusState private var focusedQuestionID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !pending.isSchemaSafe {
                Label("问题格式无法安全解析，请在 Agent 中回答。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                ForEach(pending.request.questions) { question in
                    questionView(question)
                }
            }
            HStack {
                Button("在 Agent 中回答") { store.answerInAgent(requestID: pending.id) }
                Spacer()
                if pending.supportsWriteback, !isImmediateSingleChoice || usesOtherForImmediateChoice {
                    Button(pending.status == .submitting ? "提交中…" : "提交回答") {
                        store.submit(requestID: pending.id)
                    }
                    .disabled(!pending.isSubmittable || pending.status == .submitting)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: focusedQuestionID) { _, value in store.setEditingText(value != nil) }
        .onDisappear { store.setEditingText(false) }
    }

    @ViewBuilder
    private func questionView(_ question: AgentorQuestion) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title = question.title { Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.78)) }
            Text(question.body).font(.subheadline).foregroundStyle(.white)
            switch question.kind {
            case .single, .multiple:
                FlowLayout(spacing: 6) {
                    ForEach(question.options) { option in
                        Button {
                            store.selectOption(requestID: pending.id, questionID: question.id, wireValue: option.wireValue)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.label).foregroundStyle(.white)
                                if let detail = option.detail { Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.72)) }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(isSelected(option.wireValue, questionID: question.id) ? .blue.opacity(0.3) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .disabled(!pending.supportsWriteback || pending.status != .waiting)
                    }
                }
                if question.allowsOther {
                    Toggle("Other", isOn: otherBinding(question.id))
                        .disabled(!pending.supportsWriteback || pending.status != .waiting)
                    if draft(question.id).usesOther {
                        TextField("自定义回答", text: otherTextBinding(question.id))
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedQuestionID, equals: question.id)
                            .disabled(!pending.supportsWriteback || pending.status != .waiting)
                    }
                }
            case .text:
                TextField("输入回答", text: textBinding(question.id), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedQuestionID, equals: question.id)
                    .disabled(!pending.supportsWriteback || pending.status != .waiting)
            }
        }
    }

    private var isImmediateSingleChoice: Bool {
        pending.request.questions.count == 1
            && pending.request.questions[0].kind == .single
    }

    private var usesOtherForImmediateChoice: Bool {
        guard isImmediateSingleChoice, let question = pending.request.questions.first else { return false }
        return draft(question.id).usesOther
    }

    private func draft(_ questionID: String) -> AgentorQuestionDraft {
        store.reducer.pendingRequests[pending.id]?.drafts[questionID] ?? AgentorQuestionDraft()
    }

    private func updateDraft(_ questionID: String, _ update: (inout AgentorQuestionDraft) -> Void) {
        var value = draft(questionID)
        update(&value)
        store.setDraft(value, questionID: questionID, requestID: pending.id)
    }

    private func isSelected(_ value: String, questionID: String) -> Bool { draft(questionID).selectedValues.contains(value) }
    private func textBinding(_ id: String) -> Binding<String> { Binding(get: { draft(id).text }, set: { value in updateDraft(id) { $0.text = value } }) }
    private func otherTextBinding(_ id: String) -> Binding<String> { Binding(get: { draft(id).otherText }, set: { value in updateDraft(id) { $0.otherText = value } }) }
    private func otherBinding(_ id: String) -> Binding<Bool> { Binding(get: { draft(id).usesOther }, set: { value in updateDraft(id) { $0.usesOther = value; if value { $0.selectedValues.removeAll() } } }) }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 600
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}

private struct AgentorSettingsView: View {
    @Bindable var store: AgentorStore
    @State private var removalAgent: AgentKind?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Agent 接入")
                    Spacer()
                    Button { Task { await store.refreshIntegrations() } } label: {
                        if store.isScanning { ProgressView().controlSize(.small) }
                        else { Label("刷新", systemImage: "arrow.clockwise") }
                    }
                    .disabled(store.isScanning || store.operatingAgent != nil)
                }
            }
            ForEach(AgentKind.allCases) { agent in
                Section(agent.displayName) { integrationRow(agent) }
            }
            if let error = store.integrationError { Text(error).font(.caption).foregroundStyle(.red) }
            if let message = store.focusMessage { Text(message).font(.caption).foregroundStyle(.orange) }
        }
        .formStyle(.grouped)
        .task { await store.scanIfNeeded() }
        .confirmationDialog("移除 \(removalAgent?.displayName ?? "Agent") 接入？", isPresented: Binding(
            get: { removalAgent != nil }, set: { if !$0 { removalAgent = nil } }
        )) {
            if let agent = removalAgent {
                Button("移除接入", role: .destructive) {
                    removalAgent = nil
                    Task { await store.perform(.remove, for: agent) }
                }
            }
            Button("取消", role: .cancel) { removalAgent = nil }
        }
    }

    @ViewBuilder
    private func integrationRow(_ agent: AgentKind) -> some View {
        let status = store.integrationStatuses.first { $0.agent == agent }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status?.state.displayName ?? "未扫描").font(.headline)
                Spacer()
                ForEach((status?.capabilities ?? capabilities(agent)).filter { $0 != .status }, id: \.self) { capability in
                    Text(capability.rawValue).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }
            if let status {
                Text(status.detail).font(.caption).foregroundStyle(.secondary)
                if !status.paths.isEmpty {
                    DisclosureGroup("检测路径（\(status.paths.count)）") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(status.paths, id: \.self) {
                                Text($0).font(.caption2.monospaced()).textSelection(.enabled)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Text(status.scannedAt.formatted()).font(.caption2).foregroundStyle(.tertiary)
                HStack {
                    Spacer()
                    if status.state == .integrated {
                        Button("移除接入", role: .destructive) { removalAgent = agent }
                    } else {
                        Button(status.state == .notIntegrated ? "接入/修复" : "未发现") {
                            Task { await store.perform(.install, for: agent) }
                        }
                        .disabled(status.state == .notFound)
                    }
                }
            }
            if store.operatingAgent == agent { ProgressView().controlSize(.small) }
        }
        .disabled(store.operatingAgent != nil || store.isScanning)
    }

    private func capabilities(_ agent: AgentKind) -> [AgentCapability] {
        agent == .claude || agent == .openCode ? [.status, .answer] : [.status, .reminder]
    }
}
