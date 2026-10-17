import AgentBarCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AgentBarModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var refreshIntervalSeconds = "300"
    @State private var monthlyTokenBudget = ""
    @State private var monthlyCostBudget = ""
    @State private var claudeProxyMode: NetworkProxyMode = .system
    @State private var claudeProxyAddress = ""
    @State private var autosaveTask: Task<Void, Never>?
    @State private var draggedPanelModule: PanelModule?
    @State private var draggedPanelModuleStartIndex: Int?
    @State private var draggedPanelModuleTargetIndex: Int?
    @State private var panelModuleDragTranslation: CGFloat = 0

    private let panelModuleRowStride: CGFloat = 38
    private let panelModuleDragHysteresis: CGFloat = 0.65

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                compactSection(copy.menuBar) {
                    menuBarControls
                }

                compactSection(copy.panelModules) {
                    panelModuleControls
                }

                compactSection(copy.claudeQuota) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(copy.claudeLocalCollection).font(.caption.weight(.medium)).agentBarSecondaryText()
                            Text(model.claudeStatuslineInstalled ? (language == .simplifiedChinese ? "已启用" : "Enabled") : (language == .simplifiedChinese ? "未启用" : "Not enabled"))
                                .font(.caption2).agentBarSecondaryText()
                            Spacer()
                            Button(model.claudeStatuslineInstalled ? (language == .simplifiedChinese ? "停用采集" : "Disable") : (language == .simplifiedChinese ? "启用采集" : "Enable")) {
                                model.setClaudeLocalCollection(enabled: !model.claudeStatuslineInstalled)
                            }
                            .buttonStyle(AgentBarCommandButtonStyle())
                            Button(language == .simplifiedChinese ? "网络补查" : "Query online") {
                                Task { await model.queryClaudeQuotaOnline() }
                            }
                            .buttonStyle(AgentBarCommandButtonStyle())
                            .disabled(model.isRefreshingClaudeQuota)
                        }
                        Text(copy.claudeLocalMode).font(.caption2).agentBarSecondaryText()
                        if let message = model.claudeStatuslineSetupError {
                            Text(copy.claudeMessage(message)).font(.caption2).foregroundStyle(AgentBarStyle.red)
                        }
                    }
                }

                compactSection(copy.claudeProxy) {
                    claudeProxyControls
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
            model.clearClaudeEgressIP()
            saveSettingsFromFields()
        }
        .onChange(of: draftClaudeProxy) {
            model.clearClaudeEgressIP()
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

    private var showLocalUsageBinding: Binding<Bool> {
        Binding(
            get: { model.settings.codexMenuBarShowsLocalUsage },
            set: { showsLocalUsage in
                model.settings.codexMenuBarShowsLocalUsage = showsLocalUsage
                model.persistSettings()
            }
        )
    }

    private var showGrokQuotaBinding: Binding<Bool> {
        Binding(
            get: { model.settings.grokMenuBarShowsQuota },
            set: { showsQuota in
                model.settings.grokMenuBarShowsQuota = showsQuota
                model.persistSettings()
            }
        )
    }

    private var grokQuotaBasisBinding: Binding<CodexQuotaPercentBasis> {
        Binding(
            get: { model.settings.grokQuotaPercentBasis },
            set: { basis in
                model.settings.grokQuotaPercentBasis = basis
                model.persistSettings()
            }
        )
    }

    private var grokDisplayStyleBinding: Binding<MenuBarQuotaDisplayStyle> {
        Binding(
            get: { model.settings.grokMenuBarDisplayStyle },
            set: { model.settings.grokMenuBarDisplayStyle = $0; model.persistSettings() }
        )
    }

    private var draftClaudeProxy: NetworkProxySettings {
        claudeProxyMode == .system ? .init() : NetworkProxySettings(
            mode: .manual, address: claudeProxyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var claudeProxyValidationError: String? {
        do {
            try draftClaudeProxy.validate()
            return nil
        } catch { return copy.claudeMessage(error.localizedDescription) }
    }

    private var claudeProxyControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingRow(copy.claudeProxy, labelWidth: 82) {
                AgentBarSegmentedPicker(options: NetworkProxyMode.allCases, selection: $claudeProxyMode, title: copy.proxyModeTitle)
                    .frame(width: 200)
                    .accessibilityLabel(copy.claudeProxy)
            }
            if claudeProxyMode == .manual {
                settingRow(copy.proxyAddress, labelWidth: 82) {
                    TextField("http://127.0.0.1:7890", text: $claudeProxyAddress)
                        .textFieldStyle(AgentBarTextFieldStyle())
                        .accessibilityLabel(copy.proxyAddress)
                }
            }
            HStack {
                if let message = claudeProxyValidationError {
                    Text(message).font(.caption2).foregroundStyle(AgentBarStyle.red)
                } else if draftClaudeProxy != model.settings.claudeProxy {
                    Text(language == .simplifiedChinese ? "尚未应用" : "Not applied").font(.caption2).agentBarSecondaryText()
                }
                Spacer()
                Button(model.claudeEgressIPState == .checking ? copy.detectingClaudeIP : copy.detectClaudeIP) {
                    model.detectClaudeEgressIP(proxy: draftClaudeProxy)
                }
                .buttonStyle(AgentBarCommandButtonStyle())
                .disabled(claudeProxyValidationError != nil || model.claudeEgressIPState == .checking)
                Button(copy.applyAndRefresh) { _ = model.setClaudeProxy(draftClaudeProxy) }
                    .buttonStyle(AgentBarCommandButtonStyle())
                    .disabled(claudeProxyValidationError != nil || model.isRefreshingClaudeQuota)
            }
            switch model.claudeEgressIPState {
            case let .ready(snapshot):
                settingRow(copy.claudeOutboundIP, labelWidth: 82) {
                    Text(snapshot.ipAddress)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(snapshot.checkedAt, style: .time)
                        .font(.caption2)
                        .agentBarSecondaryText()
                }
            case let .error(message):
                Text(copy.claudeMessage(message))
                    .font(.caption2)
                    .foregroundStyle(AgentBarStyle.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .idle, .checking:
                EmptyView()
            }
            Text(copy.claudeIPCheckHint)
                .font(.caption2)
                .agentBarSecondaryText()
        }
    }

    private var menuBarControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingRow(copy.display, labelWidth: 100) {
                AgentBarSegmentedPicker(
                    options: CodexMenuBarMode.allCases,
                    selection: menuBarModeBinding,
                    title: copy.menuModeTitle
                )
                .frame(width: 260, alignment: .leading)
            }

            if model.settings.codexMenuBarMode == .iconOnly {
                settingRow(copy.metric, labelWidth: 100) {
                    AgentBarSegmentedPicker(
                        options: MenuBarMetric.allCases,
                        selection: menuBarMetricBinding,
                        title: copy.metricTitle
                    )
                    .frame(width: 260, alignment: .leading)
                }
            }

            if model.settings.codexMenuBarMode == .plan {
                settingRow(copy.labels, labelWidth: 100) {
                    Button {
                        showQuotaLabelsBinding.wrappedValue.toggle()
                    } label: {
                        AgentBarCheckbox(isOn: showQuotaLabelsBinding.wrappedValue)
                    }
                    .fixedSize()
                    .buttonStyle(.plain)
                    Text(language == .simplifiedChinese ? "显示 Codex 5h / 7d" : "Show Codex 5h / 7d")
                        .agentBarSecondaryText()
                }

                ForEach(CodexMenuBarQuotaItem.supportedKeys) { key in
                    quotaMenuBarSettingRow(
                        copy.quotaLabel(key), isEnabled: enabledBinding(for: key),
                        basis: basisBinding(for: key), displayStyle: displayStyleBinding(for: key)
                    )
                }

                ForEach(ClaudeMenuBarQuotaItem.supportedKeys) { key in
                    quotaMenuBarSettingRow(
                        copy.claudeQuotaLabel(key), isEnabled: claudeEnabledBinding(for: key),
                        basis: claudeBasisBinding(for: key), displayStyle: claudeDisplayStyleBinding(for: key)
                    )
                }

                quotaMenuBarSettingRow(
                    copy.grokQuota, isEnabled: showGrokQuotaBinding,
                    basis: grokQuotaBasisBinding, displayStyle: grokDisplayStyleBinding
                )

                settingRow(copy.usage, labelWidth: 100) {
                    Button {
                        showLocalUsageBinding.wrappedValue.toggle()
                    } label: {
                        AgentBarCheckbox(isOn: showLocalUsageBinding.wrappedValue)
                    }
                    .fixedSize()
                    .buttonStyle(.plain)

                    AgentBarSegmentedPicker(
                        options: MenuBarMetric.allCases,
                        selection: menuBarMetricBinding,
                        title: copy.metricTitle
                    )
                    .frame(width: 260, alignment: .leading)
                    .disabled(!showLocalUsageBinding.wrappedValue)
                }

                settingRow(copy.languageLabel, labelWidth: 100) {
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

    private var panelModuleControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(orderedPanelModules) { module in
                panelModuleOrderRow(for: module)
            }
        }
    }

    private func quotaMenuBarSettingRow(
        _ title: String, isEnabled: Binding<Bool>, basis: Binding<CodexQuotaPercentBasis>,
        displayStyle: Binding<MenuBarQuotaDisplayStyle>
    ) -> some View {
        settingRow(title, labelWidth: 100) {
            Button { isEnabled.wrappedValue.toggle() } label: {
                AgentBarCheckbox(isOn: isEnabled.wrappedValue)
            }
            .fixedSize()
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            AgentBarSegmentedPicker(
                options: CodexQuotaPercentBasis.allCases, selection: basis, title: copy.quotaBasisTitle
            )
            .frame(width: 154)
            .disabled(!isEnabled.wrappedValue)
            .accessibilityLabel(title + " · " + copy.quotaBasisTitle(basis.wrappedValue))
            AgentBarSegmentedPicker(
                options: MenuBarQuotaDisplayStyle.allCases, selection: displayStyle, title: copy.quotaDisplayStyleTitle
            )
            .frame(width: 144)
            .disabled(!isEnabled.wrappedValue)
            .help(copy.quotaDisplayStyleHelp)
            .accessibilityLabel(title + " · " + copy.quotaDisplayStyleTitle(displayStyle.wrappedValue))
        }
    }

    private var orderedPanelModules: [PanelModule] {
        let visible = PanelModule.normalized(model.settings.visiblePanelModules)
        let hidden = PanelModule.allCases.filter { !visible.contains($0) }
        return visible + hidden
    }

    @ViewBuilder
    private func panelModuleOrderRow(for module: PanelModule) -> some View {
        let binding = moduleVisibilityBinding(for: module)
        let visibleModules = PanelModule.normalized(model.settings.visiblePanelModules)
        let visibleIndex = visibleModules.firstIndex(of: module)
        let isVisible = visibleIndex != nil

        if isVisible {
            panelModuleOrderRowBase(for: module, binding: binding, isVisible: isVisible)
                .offset(y: panelModuleDragOffset(for: module))
                .scaleEffect(draggedPanelModule == module ? 1.025 : 1)
                .shadow(
                    color: .black.opacity(draggedPanelModule == module ? 0.16 : 0),
                    radius: draggedPanelModule == module ? 10 : 0,
                    y: draggedPanelModule == module ? 5 : 0
                )
                .zIndex(draggedPanelModule == module ? 5 : 0)
                .gesture(panelModuleDragGesture(for: module))
        } else {
            panelModuleOrderRowBase(for: module, binding: binding, isVisible: isVisible)
        }
    }

    private func panelModuleOrderRowBase(
        for module: PanelModule,
        binding: Binding<Bool>,
        isVisible: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Button {
                binding.wrappedValue.toggle()
            } label: {
                AgentBarCheckbox(isOn: binding.wrappedValue)
            }
            .fixedSize()
            .buttonStyle(.plain)

            moduleDragHandle(isEnabled: isVisible)

            Text(copy.panelModuleTitle(module))
                .font(.caption.weight(.medium))
                .agentBarPrimaryText()
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .circular)
                .fill(AgentBarStyle.fieldBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .circular)
                .stroke(AgentBarStyle.stroke(colorScheme), lineWidth: 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .circular))
        .opacity(isVisible ? 1 : 0.68)
    }

    private func moduleDragHandle(isEnabled: Bool) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AgentBarStyle.secondaryText(colorScheme))
            .frame(width: 22, height: 24)
            .opacity(isEnabled ? 1 : 0.35)
            .help(copy.dragToReorder)
    }

    private func panelModuleDragGesture(for module: PanelModule) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let modules = PanelModule.normalized(model.settings.visiblePanelModules)
                guard let currentIndex = modules.firstIndex(of: module) else { return }

                if draggedPanelModule != module {
                    draggedPanelModule = module
                    draggedPanelModuleStartIndex = currentIndex
                    draggedPanelModuleTargetIndex = currentIndex
                }

                let translation = value.translation.height
                panelModuleDragTranslation = translation
                guard let startIndex = draggedPanelModuleStartIndex,
                      let currentTargetIndex = draggedPanelModuleTargetIndex else { return }

                let targetIndex = panelModuleDragTargetIndex(
                    startIndex: startIndex,
                    currentTargetIndex: currentTargetIndex,
                    translation: translation,
                    itemCount: modules.count
                )
                guard targetIndex != draggedPanelModuleTargetIndex else { return }

                withAnimation(.easeInOut(duration: 0.16)) {
                    draggedPanelModuleTargetIndex = targetIndex
                }
            }
            .onEnded { _ in
                if let draggedPanelModule,
                   let draggedPanelModuleTargetIndex {
                    movePanelModule(draggedPanelModule, to: draggedPanelModuleTargetIndex)
                    model.persistSettings()
                }
                withAnimation(.easeOut(duration: 0.14)) {
                    draggedPanelModule = nil
                    draggedPanelModuleStartIndex = nil
                    draggedPanelModuleTargetIndex = nil
                    panelModuleDragTranslation = 0
                }
            }
    }

    private func panelModuleDragOffset(for module: PanelModule) -> CGFloat {
        let visibleModules = PanelModule.normalized(model.settings.visiblePanelModules)
        guard let draggedPanelModule,
              let startIndex = draggedPanelModuleStartIndex,
              let targetIndex = draggedPanelModuleTargetIndex,
              let currentIndex = visibleModules.firstIndex(of: module) else {
            return 0
        }

        if module == draggedPanelModule {
            return panelModuleDragTranslation
        }

        if targetIndex > startIndex,
           currentIndex > startIndex,
           currentIndex <= targetIndex {
            return -panelModuleRowStride
        }

        if targetIndex < startIndex,
           currentIndex >= targetIndex,
           currentIndex < startIndex {
            return panelModuleRowStride
        }

        return 0
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

    private func displayStyleBinding(for key: CodexQuotaKey) -> Binding<MenuBarQuotaDisplayStyle> {
        Binding(
            get: { quotaItem(for: key).displayStyle },
            set: { style in updateQuotaItem(for: key) { $0.displayStyle = style } }
        )
    }

    private func claudeQuotaItem(for key: ClaudeQuotaKey) -> ClaudeMenuBarQuotaItem {
        model.settings.claudeMenuBarQuotaItems.first { $0.key == key } ?? ClaudeMenuBarQuotaItem(key: key)
    }

    private func claudeEnabledBinding(for key: ClaudeQuotaKey) -> Binding<Bool> {
        Binding(
            get: { claudeQuotaItem(for: key).isEnabled },
            set: { enabled in updateClaudeQuotaItem(for: key) { $0.isEnabled = enabled } }
        )
    }

    private func claudeBasisBinding(for key: ClaudeQuotaKey) -> Binding<CodexQuotaPercentBasis> {
        Binding(
            get: { claudeQuotaItem(for: key).basis },
            set: { basis in updateClaudeQuotaItem(for: key) { $0.basis = basis } }
        )
    }

    private func claudeDisplayStyleBinding(for key: ClaudeQuotaKey) -> Binding<MenuBarQuotaDisplayStyle> {
        Binding(
            get: { claudeQuotaItem(for: key).displayStyle },
            set: { style in updateClaudeQuotaItem(for: key) { $0.displayStyle = style } }
        )
    }

    private func moduleVisibilityBinding(for module: PanelModule) -> Binding<Bool> {
        Binding(
            get: { model.settings.visiblePanelModules.contains(module) },
            set: { isVisible in
                var modules = PanelModule.normalized(model.settings.visiblePanelModules)
                if isVisible {
                    if !modules.contains(module) {
                        modules.append(module)
                    }
                } else {
                    modules.removeAll { $0 == module }
                }
                model.settings.visiblePanelModules = PanelModule.normalized(modules)
                model.persistSettings()
            }
        )
    }

    private func panelModuleDragTargetIndex(
        startIndex: Int,
        currentTargetIndex: Int,
        translation: CGFloat,
        itemCount: Int
    ) -> Int {
        guard itemCount > 0 else { return currentTargetIndex }

        var targetIndex = min(max(currentTargetIndex, 0), itemCount - 1)
        let forwardThreshold = panelModuleDragHysteresis
        let dragDistance = translation / panelModuleRowStride

        while targetIndex < itemCount - 1,
              dragDistance > CGFloat(targetIndex - startIndex) + forwardThreshold {
            targetIndex += 1
        }

        while targetIndex > 0,
              dragDistance < CGFloat(targetIndex - startIndex) - forwardThreshold {
            targetIndex -= 1
        }

        return min(max(targetIndex, 0), itemCount - 1)
    }

    private func movePanelModule(_ module: PanelModule, to targetIndex: Int) {
        var modules = PanelModule.normalized(model.settings.visiblePanelModules)
        guard let sourceIndex = modules.firstIndex(of: module),
              modules.indices.contains(targetIndex),
              sourceIndex != targetIndex else {
            return
        }
        let moved = modules.remove(at: sourceIndex)
        modules.insert(moved, at: min(targetIndex, modules.endIndex))
        model.settings.visiblePanelModules = modules
    }

    private func loadFields() {
        refreshIntervalSeconds = String(model.settings.codexRefreshIntervalSeconds)
        monthlyTokenBudget = model.settings.monthlyTokenBudget.map(String.init) ?? ""
        monthlyCostBudget = model.settings.monthlyCostBudgetUSD.map { String(format: "%.2f", $0) } ?? ""
        claudeProxyMode = model.settings.claudeProxy.mode
        claudeProxyAddress = model.settings.claudeProxy.address
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

    private func updateClaudeQuotaItem(
        for key: ClaudeQuotaKey,
        update: (inout ClaudeMenuBarQuotaItem) -> Void
    ) {
        var items = ClaudeMenuBarQuotaItem.normalized(model.settings.claudeMenuBarQuotaItems)
        guard let index = items.firstIndex(where: { $0.key == key }) else { return }
        update(&items[index])
        model.settings.claudeMenuBarQuotaItems = items
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
