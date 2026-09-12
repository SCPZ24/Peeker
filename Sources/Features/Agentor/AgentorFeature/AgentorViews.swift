import AgentorProtocol
import FunctionCardKit
import PeekerCore
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
        let visualClock = AgentorVisualClock()
        return FunctionCardRegistration(
            id: .agentor,
            name: "Agentor",
            systemImage: "cpu",
            settingsSystemImage: "cpu",
            defaultOrder: 3,
            introducedConfigurationVersion: 3,
            metrics: metrics,
            isCompactEligible: { store.activeSessionCount > 0 },
            makeCompactLeadingView: { AnyView(AgentorCompactLeadingView(store: store, clock: visualClock).modifier(AgentorVisualScope(clock: visualClock, hasSessions: store.activeSessionCount > 0))) },
            makeCompactTrailingView: { AnyView(AgentorCompactTrailingView(store: store, clock: visualClock).modifier(AgentorVisualScope(clock: visualClock, hasSessions: store.activeSessionCount > 0))) },
            makeExpandedView: { AnyView(AgentorExpandedView(store: store, clock: visualClock).modifier(AgentorVisualScope(clock: visualClock, hasSessions: store.activeSessionCount > 0))) },
            makeSettingsView: { AnyView(AgentorSettingsView(store: store)) }
        )
    }
}

private struct AgentorCompactLeadingView: View {
    @Bindable var store: AgentorStore
    let clock: AgentorVisualClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            ForEach(store.sessions.prefix(2)) { session in
                AgentorLogo(agent: session.key.agent)
                    .opacity(reduceMotion ? 1 : 0.75 + 0.25 * clock.intensity)
            }
            if store.activeSessionCount > 2 {
                Text("\(store.activeSessionCount)").monospacedDigit()
            }
        }
    }
}

private struct AgentorCompactTrailingView: View {
    @Bindable var store: AgentorStore
    let clock: AgentorVisualClock

    var body: some View {
        HStack(spacing: 7) {
            if store.hasPendingQuestions {
                Image(systemName: "questionmark.circle").foregroundStyle(.orange)
                Text(L10n.text("等待回答"))
            } else if let session = store.sessions.first {
                Text(L10n.text(session.status.displayName))
            }
        }
        .font(.system(size: 12, weight: .medium))
    }
}

private struct AgentorExpandedView: View {
    @Bindable var store: AgentorStore
    let clock: AgentorVisualClock

    var body: some View {
        Group {
            if store.sessions.isEmpty && store.retainedDrafts.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(L10n.text("没有运行中的 Agent"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(L10n.text("Agent 开始执行后会显示在这里。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.sessions) { session in
                            AgentorSessionRow(store: store, session: session, clock: clock)
                        }
                        if store.discardedDraftCount > 0 {
                            Text(L10n.text("已清理最早的 %1$@ 份草稿（保留上限 100）。", String(store.discardedDraftCount)))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(store.retainedDrafts) { pending in
                            AgentorRetainedDraftView(pending: pending) { store.discardRetainedDraft(pending.id) }
                        }
                    }
                }
            }
        }
    }
}

private struct AgentorRetainedDraftView: View {
    let pending: AgentorPendingRequest
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.text("请求已结束，草稿保留以便复制。"), systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
            Text(pending.request.title ?? pending.request.session.agent.displayName).font(.headline)
            ForEach(pending.request.questions) { question in
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.body).font(.callout)
                    Text(answer(for: question)).textSelection(.enabled)
                }
            }
            Button(L10n.text("清除草稿"), action: dismiss)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func answer(for question: AgentorQuestion) -> String {
        guard let draft = pending.drafts[question.id] else { return "" }
        if draft.usesOther { return draft.otherText }
        if question.kind == .text { return draft.text }
        return question.options.filter { draft.selectedValues.contains($0.wireValue) }.map(\.label).joined(separator: "\n")
    }
}

private struct AgentorSessionRow: View {
    @Bindable var store: AgentorStore
    let session: AgentorSessionState
    let clock: AgentorVisualClock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AgentorLogo(agent: session.key.agent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.key.agent.displayName).font(.caption).foregroundStyle(.secondary)
                    Text(session.label).font(.headline).foregroundStyle(.primary).lineLimit(1)
                }
                Spacer()
                if !session.activeSubagentIDs.isEmpty {
                    Text(L10n.text("并行子任务 ×%1$@", String(describing: session.activeSubagentIDs.count)))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                VisualTimeline { date in
                    Text(duration(date.timeIntervalSince(session.startedAt)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(L10n.text(session.status.displayName))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            if let notice = session.resolutionNotice {
                Label(L10n.text(notice), systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.white.opacity(0.78))
            }
            ForEach(store.pendingRequests(for: session)) { pending in
                AgentorQuestionForm(store: store, pending: pending)
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            AgentorSessionBorder(
                status: session.status,
                clock: clock
            )
        }
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
                Label(L10n.text("问题格式无法安全解析，请在 Agent 中回答。"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                ForEach(Array(pending.request.questions.enumerated()), id: \.element.id) { index, question in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(index + 1).").font(.headline)
                        questionView(question)
                    }
                    if index + 1 < pending.request.questions.count { Divider() }
                }
            }
            HStack {
                Button(L10n.text("在 Agent 中回答")) { store.answerInAgent(requestID: pending.id) }
                Spacer()
                if pending.supportsWriteback, !isImmediateSingleChoice || usesOtherForImmediateChoice {
                    Button(pending.status == .submitting ? L10n.text("提交中…") : L10n.text("提交回答")) {
                        store.submit(requestID: pending.id)
                    }
                    .disabled(!pending.isSubmittable || pending.status == .submitting)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 8)
        .onChange(of: focusedQuestionID) { _, value in store.setEditingText(value != nil) }
        .onDisappear { store.setEditingText(false) }
    }

    @ViewBuilder
    private func questionView(_ question: AgentorQuestion) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title = question.title { Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.78)) }
            Text(question.body).font(.subheadline).foregroundStyle(.primary)
            switch question.kind {
            case .single, .multiple:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(question.options) { option in
                        Button {
                            store.selectOption(requestID: pending.id, questionID: question.id, wireValue: option.wireValue)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: question.kind == .multiple
                                    ? (isSelected(option.wireValue, questionID: question.id) ? "checkmark.square" : "square")
                                    : (isSelected(option.wireValue, questionID: question.id) ? "largecircle.fill.circle" : "circle"))
                                VStack(alignment: .leading, spacing: 3) {
                                Text(option.label).fixedSize(horizontal: false, vertical: true).foregroundStyle(.primary)
                                if let detail = option.detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(isSelected(option.wireValue, questionID: question.id) ? .blue.opacity(0.3) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .disabled(!pending.supportsWriteback || pending.status != .waiting)
                    }
                }
                if question.allowsOther {
                    Toggle(L10n.text("自定义回答"), isOn: otherBinding(question.id))
                        .disabled(!pending.supportsWriteback || pending.status != .waiting)
                    if draft(question.id).usesOther {
                        TextField(L10n.text("自定义回答"), text: otherTextBinding(question.id), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedQuestionID, equals: question.id)
                            .disabled(!pending.supportsWriteback || pending.status != .waiting)
                    }
                }
            case .text:
                TextField(L10n.text("输入回答"), text: textBinding(question.id), axis: .vertical)
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

private struct AgentorSettingsView: View {
    @Bindable var store: AgentorStore
    @State private var removalAgent: AgentKind?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L10n.text("Agent 接入"))
                    Spacer()
                    Button { Task { await store.refreshIntegrations() } } label: {
                        if store.isScanning { ProgressView().controlSize(.small) }
                        else { Label(L10n.text("刷新"), systemImage: "arrow.clockwise") }
                    }
                    .disabled(store.isScanning || store.operatingAgent != nil)
                }
            }
            ForEach(AgentKind.allCases) { agent in
                Section {
                    integrationRow(agent)
                } header: {
                    HStack(spacing: 6) {
                        AgentorLogo(agent: agent, size: 14, tint: .primary)
                        Text(agent.displayName)
                    }
                }
            }
            if let error = store.integrationError { Text(error).font(.caption).foregroundStyle(.red) }
            if let message = store.focusMessage { Text(message).font(.caption).foregroundStyle(.orange) }
        }
        .formStyle(.grouped)
        .task { await store.scanIfNeeded() }
        .confirmationDialog(L10n.text("移除 %1$@ 接入？", String(describing: removalAgent?.displayName ?? "Agent")), isPresented: Binding(
            get: { removalAgent != nil }, set: { if !$0 { removalAgent = nil } }
        )) {
            if let agent = removalAgent {
                Button(L10n.text("移除接入"), role: .destructive) {
                    removalAgent = nil
                    Task { await store.perform(.remove, for: agent) }
                }
            }
            Button(L10n.text("取消"), role: .cancel) { removalAgent = nil }
        }
    }

    @ViewBuilder
    private func integrationRow(_ agent: AgentKind) -> some View {
        let status = store.integrationStatuses.first { $0.agent == agent }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status.map { L10n.text($0.state.displayName) } ?? L10n.text("未扫描")).font(.headline)
                Spacer()
                ForEach((status?.capabilities ?? capabilities(agent)).filter { $0 != .status }, id: \.self) { capability in
                    Text(L10n.text(capability.rawValue)).font(.system(size: 11)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }
            if let status {
                HStack(alignment: .top, spacing: 12) {
                    if status.paths.isEmpty {
                        Text(L10n.text("检测路径（0）"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        DisclosureGroup(L10n.text("检测路径（%1$@）", String(describing: status.paths.count))) {
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
                    Spacer(minLength: 8)
                    Text(status.scannedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: AppLanguageContext.shared.locale)))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(status.detailMessage?.resolve() ?? status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if status.state == .integrated {
                        Button(L10n.text("移除接入"), role: .destructive) { removalAgent = agent }
                    } else {
                        Button(status.state == .notIntegrated ? L10n.text("接入/修复") : L10n.text("未发现")) {
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
