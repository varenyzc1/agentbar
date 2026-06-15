import AgentBarCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AgentBarModel

    @State private var refreshIntervalSeconds = "300"
    @State private var monthlyTokenBudget = ""
    @State private var monthlyCostBudget = ""
    @State private var autosaveTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                compactSection(copy.menuBar) {
                    menuBarControls
                }

                HStack(alignment: .top, spacing: 12) {
                    compactSection(copy.refresh) {
                        VStack(alignment: .leading, spacing: 9) {
                            settingRow(copy.refresh, labelWidth: 58) {
                                HStack(spacing: 6) {
                                    TextField("", text: $refreshIntervalSeconds)
                                        .textFieldStyle(AgentBarTextFieldStyle())
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 64)

                                    Stepper("", value: refreshBinding, in: 30...(24 * 60 * 60), step: 30)
                                        .labelsHidden()

                                    Text(language == .simplifiedChinese ? "秒" : "sec")
                                        .agentBarSecondaryText()
                                }
                            }

                            settingRow(copy.login, labelWidth: 58) {
                                Button {
                                    launchAtLoginBinding.wrappedValue.toggle()
                                } label: {
                                    AgentBarSwitch(isOn: launchAtLoginBinding.wrappedValue)
                                }
                                .fixedSize()
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    compactSection(copy.budgets) {
                        VStack(alignment: .leading, spacing: 9) {
                            settingRow(copy.tokenBudget, labelWidth: 58) {
                                HStack(spacing: 6) {
                                    TextField("", text: $monthlyTokenBudget)
                                        .textFieldStyle(AgentBarTextFieldStyle())
                                        .frame(width: 98)
                                    Text(copy.tokens)
                                        .agentBarSecondaryText()
                                }
                            }

                            settingRow(copy.cost, labelWidth: 58) {
                                HStack(spacing: 6) {
                                    TextField("", text: $monthlyCostBudget)
                                        .textFieldStyle(AgentBarTextFieldStyle())
                                        .frame(width: 98)
                                    Text("USD")
                                        .agentBarSecondaryText()
                                }
                            }
                        }
                    }
                }

                compactSection(copy.maintenance) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 10) {
                            Button {
                                saveSettingsFromFields()
                            } label: {
                                Label(copy.save, systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(AgentBarCommandButtonStyle())
                            .keyboardShortcut("s", modifiers: [.command])

                            Button {
                                Task { await model.refresh(force: true) }
                            } label: {
                                Label(copy.scan, systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(AgentBarCommandButtonStyle())
                            .disabled(model.isRefreshing)
                        }

                        HStack(spacing: 10) {
                            Button {
                                model.recalculateCosts()
                            } label: {
                                Label(copy.recalculate, systemImage: "dollarsign.arrow.circlepath")
                            }
                            .buttonStyle(AgentBarCommandButtonStyle())

                            Button {
                                model.resetPricing()
                            } label: {
                                Label(copy.resetPricing, systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(AgentBarCommandButtonStyle())
                        }

                        settingRow(copy.database, labelWidth: 58) {
                            Text(databaseLocationText)
                                .font(.caption2)
                                .agentBarSecondaryText()
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }

                compactSection(copy.updates) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 10) {
                            Text(appVersionText)
                                .font(.caption.weight(.medium))
                                .agentBarSecondaryText()
                                .textSelection(.enabled)

                            Spacer(minLength: 0)

                            Button {
                                Task { await model.checkForUpdates() }
                            } label: {
                                Label(copy.check, systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(AgentBarCommandButtonStyle())
                            .disabled(model.updateState == .checking)

                            updateActionButton
                        }

                        Text(updateStatusText)
                            .font(.caption2)
                            .foregroundStyle(updateStatusColor)
                            .lineLimit(2)
                    }
                }

                footer
            }
            .padding(16)
        }
        .agentBarPanelBackground()
        .controlSize(.small)
        .onAppear(perform: loadFields)
        .task {
            await model.refreshInstallMethod()
        }
        .onDisappear {
            autosaveTask?.cancel()
            saveSettingsFromFields()
        }
        .onChange(of: refreshIntervalSeconds) {
            scheduleSettingsAutosave()
        }
        .onChange(of: monthlyTokenBudget) {
            scheduleSettingsAutosave()
        }
        .onChange(of: monthlyCostBudget) {
            scheduleSettingsAutosave()
        }
    }

    private var language: AppLanguage {
        model.settings.language
    }

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    private var menuBarModeBinding: Binding<CodexMenuBarMode> {
        Binding(
            get: { model.settings.codexMenuBarMode },
            set: { mode in
                model.settings.codexMenuBarMode = mode
                model.persistSettings()
            }
        )
    }

    private var menuBarMetricBinding: Binding<MenuBarMetric> {
        Binding(
            get: { model.settings.menuBarMetric },
            set: { metric in
                model.settings.menuBarMetric = metric
                model.persistSettings()
            }
        )
    }

    private var refreshBinding: Binding<Int> {
        Binding(
            get: { Int(refreshIntervalSeconds) ?? model.settings.codexRefreshIntervalSeconds },
            set: { refreshIntervalSeconds = String($0) }
        )
    }

    private var databaseLocationText: String {
        "~/Library/Application Support/AgentBar/agentbar.db"
    }

    private var githubRepositoryURL: URL {
        URL(string: "https://github.com/varenyzc1/agentbar")!
    }

    private var contributorGitHubURL: URL {
        URL(string: "https://github.com/ZengWenJian123")!
    }

    private var appVersionText: String {
        AppVersion.current.displayText
    }

    private var updateStatusText: String {
        copy.updateStatus(model.updateState, installMethod: model.installMethod)
    }

    private var updateStatusColor: Color {
        switch model.updateState {
        case .available:
            return AgentBarStyle.green
        case .failed:
            return AgentBarStyle.red
        default:
            return .secondary
        }
    }

    @ViewBuilder
    private var updateActionButton: some View {
        if case let .available(_, url) = model.updateState {
            if model.installMethod == .homebrew {
                Button {
                    model.updateWithHomebrew()
                } label: {
                    Label(copy.update, systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(AgentBarCommandButtonStyle())
            } else {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(copy.open, systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(AgentBarCommandButtonStyle())
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.settings.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }

    private var showQuotaLabelsBinding: Binding<Bool> {
        Binding(
            get: { model.settings.codexMenuBarShowsQuotaLabels },
            set: { showsLabels in
                model.settings.codexMenuBarShowsQuotaLabels = showsLabels
                model.persistSettings()
            }
        )
    }

    private var menuBarControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingRow(copy.display, labelWidth: 82) {
                AgentBarSegmentedPicker(
                    options: CodexMenuBarMode.allCases,
                    selection: menuBarModeBinding,
                    title: copy.menuModeTitle
                )
                .frame(width: 260, alignment: .leading)
            }

            if model.settings.codexMenuBarMode == .iconOnly {
                settingRow(copy.metric, labelWidth: 82) {
                    AgentBarSegmentedPicker(
                        options: MenuBarMetric.allCases,
                        selection: menuBarMetricBinding,
                        title: copy.metricTitle
                    )
                    .frame(width: 260, alignment: .leading)
                }
            }

            if model.settings.codexMenuBarMode == .plan {
                settingRow(copy.labels, labelWidth: 82) {
                    Button {
                        showQuotaLabelsBinding.wrappedValue.toggle()
                    } label: {
                        AgentBarCheckbox(isOn: showQuotaLabelsBinding.wrappedValue)
                    }
                    .fixedSize()
                    .buttonStyle(.plain)
                    Text(language == .simplifiedChinese ? "显示 5h / 7d" : "Show 5h / 7d")
                        .agentBarSecondaryText()
                }

                ForEach(CodexMenuBarQuotaItem.supportedKeys) { key in
                    settingRow(copy.quotaLabel(key), labelWidth: 82) {
                        Button {
                            enabledBinding(for: key).wrappedValue.toggle()
                        } label: {
                            AgentBarCheckbox(isOn: enabledBinding(for: key).wrappedValue)
                        }
                        .fixedSize()
                        .buttonStyle(.plain)

                        AgentBarSegmentedPicker(
                            options: CodexQuotaPercentBasis.allCases,
                            selection: basisBinding(for: key),
                            title: copy.quotaBasisTitle
                        )
                        .frame(width: 154, alignment: .leading)
                        .disabled(!quotaItem(for: key).isEnabled)
                    }
                }

                settingRow(copy.languageLabel, labelWidth: 82) {
                    AgentBarSegmentedPicker(
                        options: AppLanguage.allCases,
                        selection: languageBinding,
                        title: copy.languageTitle
                    )
                    .frame(width: 154, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(copy.byline)
                    .font(.caption2.weight(.medium))
                    .agentBarSecondaryText()

                Button {
                    NSWorkspace.shared.open(githubRepositoryURL)
                } label: {
                    Label("github.com/varenyzc1/agentbar", systemImage: "link")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.plain)
                .agentBarSecondaryText()
                .help(copy.openGitHubRepository)
            }

            HStack(spacing: 8) {
                Text(copy.contributorByline)
                    .font(.caption2.weight(.medium))
                    .agentBarSecondaryText()

                Button {
                    NSWorkspace.shared.open(contributorGitHubURL)
                } label: {
                    Label("github.com/ZengWenJian123", systemImage: "link")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.plain)
                .agentBarSecondaryText()
                .help(copy.openGitHubRepository)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text(copy.statusMessage(model.statusMessage))
                    .font(.caption2)
                    .agentBarSecondaryText()
            }
        }
        .padding(.horizontal, 2)
    }

    private func compactSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .agentBarSecondaryText()
                .padding(.leading, 2)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .agentBarCard(padding: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingRow<Content: View>(
        _ title: String,
        labelWidth: CGFloat = 96,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .agentBarSecondaryText()
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)

            HStack(alignment: .center, spacing: 8) {
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quotaItem(for key: CodexQuotaKey) -> CodexMenuBarQuotaItem {
        model.settings.codexMenuBarQuotaItems.first { $0.key == key } ?? CodexMenuBarQuotaItem(key: key)
    }

    private func enabledBinding(for key: CodexQuotaKey) -> Binding<Bool> {
        Binding(
            get: { quotaItem(for: key).isEnabled },
            set: { isEnabled in
                updateQuotaItem(for: key) { item in
                    item.isEnabled = isEnabled
                }
            }
        )
    }

    private func basisBinding(for key: CodexQuotaKey) -> Binding<CodexQuotaPercentBasis> {
        Binding(
            get: { quotaItem(for: key).basis },
            set: { basis in
                updateQuotaItem(for: key) { item in
                    item.basis = basis
                }
            }
        )
    }

    private func loadFields() {
        refreshIntervalSeconds = String(model.settings.codexRefreshIntervalSeconds)
        monthlyTokenBudget = model.settings.monthlyTokenBudget.map(String.init) ?? ""
        monthlyCostBudget = model.settings.monthlyCostBudgetUSD.map { String(format: "%.2f", $0) } ?? ""
    }

    private func saveSettingsFromFields() {
        autosaveTask?.cancel()
        saveSettingsFromFields(reloadFields: true)
    }

    private func saveSettingsFromFields(reloadFields: Bool) {
        let refreshText = refreshIntervalSeconds.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenText = monthlyTokenBudget.trimmingCharacters(in: .whitespacesAndNewlines)
        let costText = monthlyCostBudget.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let refreshInterval = Int(refreshText),
              tokenText.isEmpty || Int(tokenText) != nil,
              costText.isEmpty || Double(costText) != nil else {
            model.statusMessage = "Invalid settings"
            return
        }

        model.settings.codexRefreshIntervalSeconds = refreshInterval
        model.settings.monthlyTokenBudget = tokenText.isEmpty ? nil : Int(tokenText)
        model.settings.monthlyCostBudgetUSD = costText.isEmpty ? nil : Double(costText)
        model.persistSettings()
        if reloadFields {
            loadFields()
        }
    }

    private func scheduleSettingsAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveSettingsFromFields(reloadFields: false)
            }
        }
    }

    private func updateQuotaItem(
        for key: CodexQuotaKey,
        update: (inout CodexMenuBarQuotaItem) -> Void
    ) {
        var items = CodexMenuBarQuotaItem.normalized(model.settings.codexMenuBarQuotaItems)
        guard let index = items.firstIndex(where: { $0.key == key }) else { return }
        update(&items[index])
        model.settings.codexMenuBarQuotaItems = items
        model.persistSettings()
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { model.settings.language },
            set: { language in
                model.settings.language = language
                model.persistSettings()
            }
        )
    }
}
