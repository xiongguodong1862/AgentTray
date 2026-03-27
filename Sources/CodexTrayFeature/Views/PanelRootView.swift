import Combine
import SwiftUI

struct PanelRootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settingsStore: AppSettingsStore
    let onQuit: () -> Void
    var onPreferredPanelHeightChange: (CGFloat, AgentKind) -> Void
    @State private var heatmapRange: HeatmapRange
    @State private var analyticsTabSelection: [AgentKind: AgentAnalyticsTab] = [
        .codex: .activity,
        .claude: .activity,
        .gemini: .activity,
    ]
    @State private var analyticsRangeSelection: [AgentKind: AnalyticsRange] = [
        .codex: .today,
        .claude: .today,
        .gemini: .today,
    ]
    @State private var analyticsActivityRangeSelection: [AgentKind: HeatmapRange] = [
        .codex: .month,
        .claude: .month,
        .gemini: .month,
    ]
    @State private var isPetGuideHovered = false
    @State private var isSettingsPresented = false
    @State private var panelPointerLocation: CGPoint?
    @State private var petAvatarFrameInPanel: CGRect = .zero
    @State private var petPreviewProgress: PetProgress?
    @State private var petPreviewMilestones: [PetMilestoneAnimation] = []
    @State private var petPreviewSequence = 0
    @State private var petDialogueTick = 0

    init(
        store: UsageStore,
        settingsStore: AppSettingsStore,
        onQuit: @escaping () -> Void,
        onPreferredPanelHeightChange: @escaping (CGFloat, AgentKind) -> Void
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.onQuit = onQuit
        self.onPreferredPanelHeightChange = onPreferredPanelHeightChange
        _heatmapRange = State(initialValue: settingsStore.settings.defaultHeatmapRange)
    }

    private var islandHeight: CGFloat { ScreenLayout.collapsedIslandSize.height }
    private var panelWidth: CGFloat { ScreenLayout.panelWidth }
    private var selectedAgent: AgentKind { store.selectedAgent }
    private var availableAgents: [AgentKind] {
        store.multiAgentSnapshot.agents
            .filter(\.isAvailable)
            .map(\.agent)
    }
    private var availableTabs: [AgentKind] {
        [.all] + availableAgents
    }

    var body: some View {
        ZStack(alignment: .top) {
            ExpandedIslandContainer()
                .fill(expandedBackground)

            VStack(spacing: 0) {
                IslandHeaderBar(
                    store: store,
                    width: panelWidth,
                    height: islandHeight,
                    standalone: false
                )
                .frame(width: panelWidth, height: islandHeight)

                VStack(alignment: .leading, spacing: 18) {
                    tabBar

                    switch selectedAgent {
                    case .all:
                        allTabContent
                    case .codex, .claude, .gemini:
                        agentTabContent(for: selectedAgent)
                    }

                    HorizontalSectionDivider()

                    footerRow
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if isSettingsPresented {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isSettingsPresented = false
                        }

                    settingsOverlay
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .zIndex(30)
            }
        }
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity)
        .coordinateSpace(name: "panel-root")
        .clipShape(ExpandedIslandContainer())
        .clipped()
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                panelPointerLocation = location
            case .ended:
                panelPointerLocation = nil
            }
        }
        .onAppear {
            if availableTabs.contains(selectedAgent) == false {
                store.selectAgent(.all)
            }
            updatePreferredPanelHeight(for: selectedAgent)
        }
        .onChange(of: heatmapRange) { _, newValue in
            if selectedAgent == .all {
                onPreferredPanelHeightChange(ScreenLayout.panelHeight(for: newValue, agent: .all), .all)
            }
        }
        .onChange(of: selectedAgent) { _, newValue in
            updatePreferredPanelHeight(for: newValue)
        }
        .onReceive(settingsStore.$panelPresentationSequence.dropFirst()) { _ in
            heatmapRange = settingsStore.settings.defaultHeatmapRange
            isSettingsPresented = false
            updatePreferredPanelHeight(for: selectedAgent)
        }
        .onReceive(Timer.publish(every: 5.6, on: .main, in: .common).autoconnect()) { _ in
            petDialogueTick += 1
        }
        .animation(.easeOut(duration: 0.18), value: isSettingsPresented)
        .animation(.easeInOut(duration: 0.35), value: settingsStore.settings.themeTint)
        .animation(.easeInOut(duration: 0.35), value: settingsStore.settings.heatmapColor)
    }

    private var tabBar: some View {
        HStack(spacing: 10) {
            ForEach(availableTabs) { agent in
                Button {
                    store.selectAgent(agent)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: agent.iconSymbolName)
                            .font(.system(size: 10, weight: .semibold))
                        Text(agent.displayName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(agent == selectedAgent ? .white : .white.opacity(0.62))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(agent == selectedAgent ? .white.opacity(0.14) : .white.opacity(0.06))
                    )
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(agent == selectedAgent ? 0.12 : 0.04), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var allTabContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                petColumn(progress: store.multiAgentSnapshot.pet, xpBreakdown: store.multiAgentSnapshot.xpBreakdown)
                    .frame(width: 270)

                VerticalSectionDivider()
                    .frame(height: 170)

                allSummaryBlock
            }

            HorizontalSectionDivider()

            yearHeatmapArea(days: heatmapDays(for: .all), title: "跨 Agent 活跃趋势")
        }
    }

    private func agentTabContent(for agent: AgentKind) -> some View {
        let snapshot = snapshot(for: agent)
        return VStack(alignment: .leading, spacing: 18) {
            compactOverviewBlock(for: snapshot)

            HorizontalSectionDivider()

            AgentAnalyticsSectionView(
                agent: agent,
                snapshot: snapshot,
                heatmapColorPreset: settingsStore.settings.heatmapColor,
                selectedTab: analyticsTabBinding(for: agent),
                selectedRange: analyticsRangeBinding(for: agent),
                activityRange: analyticsActivityRangeBinding(for: agent)
            )
        }
    }

    private func petColumn(progress: PetProgress, xpBreakdown: [AgentXPBreakdown]) -> some View {
        let displayedProgress = petPreviewProgress ?? progress
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayedProgress.stage.displayName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
                    .padding(4)
                    .contentShape(Rectangle())
                    .onHover { isHovered in
                        isPetGuideHovered = isHovered
                    }

                Spacer()

                Text("Lv.\(displayedProgress.level)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
            }

            HStack(spacing: 14) {
                PetAvatarView(
                    progress: displayedProgress,
                    panelPointerLocation: panelPointerLocation,
                    avatarFrameInPanel: petAvatarFrameInPanel,
                    presentationSequence: settingsStore.panelPresentationSequence,
                    previewMilestones: petPreviewMilestones,
                    previewSequence: petPreviewSequence
                )
                .frame(width: 58, height: 58)
                .background(
                    GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: PetAvatarFramePreferenceKey.self,
                                    value: geometry.frame(in: .named("panel-root"))
                        )
                    }
                )
                .modifier(PetDeveloperPreviewMenu(
                    progress: progress,
                    petPreviewProgress: $petPreviewProgress,
                    petPreviewMilestones: $petPreviewMilestones,
                    petPreviewSequence: $petPreviewSequence,
                    petDialogueTick: $petDialogueTick
                ))

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(displayedProgress.currentXP)/\(displayedProgress.nextLevelXP)（今日经验：\(displayedProgress.todayXP)）")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    ProgressView(value: Double(displayedProgress.currentXP), total: Double(max(1, displayedProgress.nextLevelXP)))
                        .tint(Color(hex: displayedProgress.stage.accentHex))
                        .scaleEffect(x: 1, y: 0.8, anchor: .center)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: PetStatusFormatter.indicatorHex(for: displayedProgress)))
                            .frame(width: 6, height: 6)
                        Text(PetDialogueLibrary.message(for: displayedProgress, tick: petDialogueTick))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .id("pet-dialogue-\(displayedProgress.level)-\(petDialogueTick)")
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("经验来源")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.42))

                Text(xpBreakdownText(from: xpBreakdown))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.top, 8)
        .onPreferenceChange(PetAvatarFramePreferenceKey.self) { newFrame in
            petAvatarFrameInPanel = newFrame
        }
        .overlay(alignment: .topLeading) {
            if isPetGuideHovered {
                HeatmapTooltip(
                    text: PetProgressExplanationFormatter.tooltipText(from: xpBreakdown),
                    width: 300,
                    multilineAlignment: .leading
                )
                .offset(x: 108, y: -8)
                .allowsHitTesting(false)
                .zIndex(20)
            }
        }
        .zIndex(isPetGuideHovered ? 20 : 0)
    }

    private var allSummaryBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            summaryMetricRow(label: "最近活跃", value: recentAgentLabel, valueColor: .white)
            summaryMetricRow(label: "总活跃时长", value: DurationFormatter.string(for: store.multiAgentSnapshot.todaySummary.totalActiveMinutes), valueColor: .white)
            summaryMetricRow(label: "总会话数", value: "\(store.multiAgentSnapshot.todaySummary.totalSessions)", valueColor: .white)
            summaryMetricRow(label: "总 Token", value: UsageNumberFormatter.compactCount(store.multiAgentSnapshot.todaySummary.totalTokenUsage), valueColor: .white)
        }
    }

    private func statusBlock(for snapshot: AgentSnapshot) -> some View {
        let rows = statusRows(for: snapshot)
        return VStack(alignment: .leading, spacing: 12) {
            Text(AgentPanelLayoutPolicy.statusTitle(for: snapshot.agent))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.42))

            if rows.count == 2 {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(rows) { row in
                        usageRow(
                            label: row.label,
                            value: row.value,
                            remainingPercent: row.remainingPercent,
                            resetHint: row.resetHint,
                            showsProgressBar: row.showsProgressBar
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                ForEach(rows) { row in
                    usageRow(
                        label: row.label,
                        value: row.value,
                        remainingPercent: row.remainingPercent,
                        resetHint: row.resetHint,
                        showsProgressBar: row.showsProgressBar
                    )
                }
            }
        }
    }

    private func compactOverviewBlock(for snapshot: AgentSnapshot) -> some View {
        statusBlock(for: snapshot)
    }

    private func yearHeatmapArea(days: [UsageMetricsDay], title: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.42))

                Spacer()

                Picker("时间范围", selection: $heatmapRange) {
                    ForEach(HeatmapRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                    .tint(.white.opacity(0.82))
            }

            heatmapContent(days: days)
                .frame(maxWidth: .infinity, alignment: .leading)

            HeatmapLegend(colorPreset: settingsStore.settings.heatmapColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, heatmapRange == .month ? 12 : 0)
        }
        .padding(.top, 4)
    }

    private var footerRow: some View {
        let environment = environmentSummary(for: selectedAgent)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "#FF9C8A"))
                        .lineLimit(2)
                }

                Text(environmentSummaryLine(environment))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    isSettingsPresented.toggle()
                } label: {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .buttonStyle(ChromeButtonStyle(tint: .white.opacity(0.12)))

                Button("退出", action: onQuit)
                    .buttonStyle(ChromeButtonStyle(tint: .white.opacity(0.12)))
            }
        }
    }

    private func usageRow(
        label: String,
        value: String,
        remainingPercent: Double?,
        resetHint: String?,
        showsProgressBar: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: resetHint == nil ? 8 : 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))

                Spacer()

                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            if let resetHint {
                Text(resetHint)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(1)
                    .minimumScaleFactor(0.92)
            }

            if showsProgressBar {
                ProgressView(
                    value: UsageLimitProgressStyle.progressValue(for: remainingPercent),
                    total: 1
                )
                .tint(Color(hex: UsageLimitProgressStyle.tintHex(for: remainingPercent)))
                .scaleEffect(x: 1, y: 0.72, anchor: .center)
                .padding(.top, resetHint == nil ? 0 : 1)
            }
        }
    }

    private func metricRowView(_ row: MetricRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))

            Spacer()

            Text(row.value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(row.valueColor)
        }
    }

    private var expandedBackground: LinearGradient {
        let gradientHexes = settingsStore.settings.themeTint.gradientHexes
        return LinearGradient(
            stops: [
                .init(color: Color(hex: gradientHexes[0]), location: 0.0),
                .init(color: Color(hex: gradientHexes[1]), location: 0.14),
                .init(color: Color(hex: gradientHexes[2]), location: 0.38),
                .init(color: Color(hex: gradientHexes[3]), location: 0.7),
                .init(color: Color(hex: gradientHexes[4]), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func statusRows(for snapshot: AgentSnapshot) -> [StatusRow] {
        switch snapshot.agent {
        case .codex:
            var rows = [
                StatusRow(
                    label: snapshot.status.primaryLabel,
                    value: snapshot.status.primaryValue,
                    remainingPercent: snapshot.status.primaryProgress.map { $0 * 100 },
                    resetHint: UsageDisplayFormatter.resetDetail(
                        for: snapshot.status.primaryResetAt,
                        relativeTo: snapshot.generatedAt
                    ),
                    showsProgressBar: true
                )
            ]
            if let secondaryLabel = snapshot.status.secondaryLabel,
               let secondaryValue = snapshot.status.secondaryValue {
                rows.append(
                    StatusRow(
                        label: secondaryLabel,
                        value: secondaryValue,
                        remainingPercent: snapshot.status.secondaryProgress.map { $0 * 100 },
                        resetHint: UsageDisplayFormatter.resetDetail(
                            for: snapshot.status.secondaryResetAt,
                            relativeTo: snapshot.generatedAt
                        ),
                        showsProgressBar: true
                    )
                )
            }
            return rows
        case .claude, .gemini:
            var rows = [
                StatusRow(
                    label: "近7天平均会话 Token",
                    value: AgentPanelLayoutPolicy.recentAverageTokensPerSessionText(for: snapshot),
                    remainingPercent: nil,
                    resetHint: nil,
                    showsProgressBar: false
                )
            ]
            if let secondaryLabel = snapshot.status.secondaryLabel,
               let secondaryValue = snapshot.status.secondaryValue {
                rows.append(
                    StatusRow(
                        label: secondaryLabel,
                        value: secondaryValue,
                        remainingPercent: nil,
                        resetHint: nil,
                        showsProgressBar: false
                    )
                )
            }
            return rows
        case .all:
            return [
                StatusRow(
                    label: snapshot.status.primaryLabel,
                    value: snapshot.status.primaryValue,
                    remainingPercent: nil,
                    resetHint: nil,
                    showsProgressBar: false
                )
            ]
        }
    }

    @ViewBuilder
    private func heatmapContent(days: [UsageMetricsDay]) -> some View {
        switch heatmapRange {
        case .year:
            YearContributionHeatmap(days: days, colorPreset: settingsStore.settings.heatmapColor)
        case .month:
            MonthCalendarHeatmap(days: days, colorPreset: settingsStore.settings.heatmapColor)
        case .week:
            WeekStripHeatmap(days: Array(days.suffix(7)), colorPreset: settingsStore.settings.heatmapColor)
        }
    }

    private var settingsOverlay: some View {
        SettingsCardView(
            store: store,
            settingsStore: settingsStore,
            onClose: { isSettingsPresented = false }
        )
    }

    private func snapshot(for agent: AgentKind) -> AgentSnapshot {
        store.multiAgentSnapshot.snapshot(for: agent)
            ?? AgentSnapshot.empty(agent: agent, generatedAt: .now, runtimeLabel: agent.displayName, dataSourceLabel: "--")
    }

    private func analyticsTabBinding(for agent: AgentKind) -> Binding<AgentAnalyticsTab> {
        Binding(
            get: { analyticsTabSelection[agent] ?? .activity },
            set: { newValue in
                analyticsTabSelection[agent] = newValue
                updatePreferredPanelHeight(for: agent)
            }
        )
    }

    private func analyticsRangeBinding(for agent: AgentKind) -> Binding<AnalyticsRange> {
        Binding(
            get: { analyticsRangeSelection[agent] ?? .today },
            set: { newValue in
                analyticsRangeSelection[agent] = newValue
                updatePreferredPanelHeight(for: agent)
            }
        )
    }

    private func analyticsActivityRangeBinding(for agent: AgentKind) -> Binding<HeatmapRange> {
        Binding(
            get: { analyticsActivityRangeSelection[agent] ?? .month },
            set: { newValue in
                analyticsActivityRangeSelection[agent] = newValue
                updatePreferredPanelHeight(for: agent)
            }
        )
    }

    private func updatePreferredPanelHeight(for agent: AgentKind) {
        if agent == .all {
            onPreferredPanelHeightChange(ScreenLayout.panelHeight(for: heatmapRange, agent: .all), .all)
            return
        }
        let tab = analyticsTabSelection[agent] ?? .activity
        let range = analyticsRangeSelection[agent] ?? .today
        let activityRange = analyticsActivityRangeSelection[agent] ?? .month
        onPreferredPanelHeightChange(
            AgentAnalyticsLayout.preferredPanelHeight(
                agent: agent,
                tab: tab,
                analyticsRange: range,
                activityRange: activityRange
            ),
            agent
        )
    }

    private func heatmapDays(for agent: AgentKind) -> [UsageMetricsDay] {
        switch agent {
        case .all:
            return switch heatmapRange {
            case .year: store.multiAgentSnapshot.lastYearDays
            case .month: store.multiAgentSnapshot.lastMonthDays
            case .week: store.multiAgentSnapshot.lastSevenDays
            }
        case .codex, .claude, .gemini:
            let snapshot = snapshot(for: agent)
            return switch heatmapRange {
            case .year: snapshot.lastYearDays
            case .month: Array(snapshot.lastYearDays.suffix(30))
            case .week: snapshot.lastSevenDays
            }
        }
    }

    private var recentAgentLabel: String {
        guard let agent = store.multiAgentSnapshot.mostRecentlyActiveAgent else {
            return "暂无"
        }
        return agent.displayName
    }

    private func xpBreakdownText(from entries: [AgentXPBreakdown]) -> String {
        if entries.isEmpty {
            return "暂无经验变动"
        }
        return entries
            .map { "\($0.agent.displayName) +\($0.todayXP)" }
            .joined(separator: "  ·  ")
    }

    private func environmentSummary(for agent: AgentKind) -> AgentEnvironmentSummary {
        switch agent {
        case .all:
            return AgentEnvironmentSummary(
                runtimeLabel: "Multi-Agent",
                authLabel: nil,
                currentModel: nil,
                dataSourceLabel: "已接入 \(store.multiAgentSnapshot.agents.filter(\.isAvailable).count) 个 Agent",
                updatedAt: store.multiAgentSnapshot.generatedAt
            )
        case .codex, .claude, .gemini:
            return snapshot(for: agent).environment
        }
    }

    private func environmentSummaryLine(_ environment: AgentEnvironmentSummary) -> String {
        var parts = ["当前环境：\(environment.runtimeLabel)"]
        if let currentModel = environment.currentModel, !currentModel.isEmpty {
            parts.append("当前模型：\(currentModel)")
        }
        if let authLabel = environment.authLabel, !authLabel.isEmpty {
            parts.append("认证方式：\(authLabel)")
        }
        parts.append("数据源：\(environment.dataSourceLabel)")
        return parts.joined(separator: "  ·  ")
    }

    private func summaryMetricRow(label: String, value: String, valueColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))

            Spacer()

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
        }
    }
}

struct HotspotBadgeView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        IslandHeaderBar(
            store: store,
            width: ScreenLayout.collapsedIslandSize.width,
            height: ScreenLayout.collapsedIslandSize.height,
            standalone: true
        )
    }
}

struct IslandHeaderBar: View {
    @ObservedObject var store: UsageStore
    let width: CGFloat
    let height: CGFloat
    let standalone: Bool

    var body: some View {
        ZStack {
            if standalone {
                TopAttachedRoundedRect(cornerRadius: 16)
                    .fill(.black)
            } else {
                Rectangle()
                    .fill(.black.opacity(0.98))
            }

            HStack {
                Text(store.focusedAgent.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                Text(headerStatusText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.leading, standalone ? 8 : 24)
            .padding(.trailing, standalone ? 8 : 24)
            .padding(.top, standalone ? 0 : 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width, height: height)
    }

    private var headerStatusText: String {
        let agent = store.focusedAgent
        guard let snapshot = store.multiAgentSnapshot.snapshot(for: agent) else {
            return "--"
        }
        return AgentPanelLayoutPolicy.headerStatusText(for: snapshot)
    }
}

struct ExpandedIslandContainer: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 22
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

struct TopAttachedRoundedRect: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

struct HorizontalSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

struct VerticalSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 4)
    }
}

struct MetricRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let valueColor: Color
}

struct StatusRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let remainingPercent: Double?
    let resetHint: String?
    let showsProgressBar: Bool
}

enum AgentPanelLayoutPolicy {
    static func statusTitle(for agent: AgentKind) -> String {
        agent == .codex ? "配额 / 状态" : "使用情况"
    }

    static func headerStatusText(for snapshot: AgentSnapshot) -> String {
        if snapshot.agent == .codex,
           let secondaryValue = snapshot.status.secondaryValue {
            return "\(snapshot.status.primaryValue) / \(secondaryValue)"
        }
        if snapshot.agent == .claude || snapshot.agent == .gemini {
            return "Token \(UsageNumberFormatter.compactCount(snapshot.today.tokenUsage))"
        }
        return "\(snapshot.status.primaryLabel) \(snapshot.status.primaryValue)"
    }

    static func recentAverageTokensPerSessionText(for snapshot: AgentSnapshot) -> String {
        let totalDialogs = snapshot.lastSevenDays.reduce(0) { $0 + $1.dialogs }
        guard totalDialogs > 0 else { return "--" }
        let totalTokens = snapshot.lastSevenDays.reduce(0) { $0 + $1.tokenUsage }
        return UsageNumberFormatter.compactCount(totalTokens / totalDialogs)
    }
}

enum UsageNumberFormatter {
    static func compactCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    static func tokenCompactCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fm", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.2fk", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

enum UsageDisplayFormatter {
    static func heatmapTooltipText(
        for day: UsageMetricsDay,
        dateFormatter: DateFormatter,
        durationFormatter: (Int) -> String = DurationFormatter.string
    ) -> String {
        var lines = [
            dateFormatter.string(from: day.date),
            "\(day.dialogs) 次\(day.interactionLabel)",
            "活跃 \(durationFormatter(day.activeMinutes))",
        ]
        if day.tokenUsage > 0 {
            lines.append("Token \(day.tokenUsage)")
        }
        if day.toolCalls > 0 {
            lines.append("工具 \(day.toolCalls)")
        }
        if day.sourceAgents.isEmpty == false {
            lines.append("来源 \(day.sourceAgents.joined(separator: " + "))")
        }
        return lines.joined(separator: "\n")
    }

    static func resetHint(for date: Date?, timeZone: TimeZone = .current) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d HH:mm"
        return "\(formatter.string(from: date)) 重置"
    }

    static func resetDetail(
        for date: Date?,
        relativeTo now: Date,
        timeZone: TimeZone = .current
    ) -> String? {
        guard let date, let reset = resetHint(for: date, timeZone: timeZone) else { return nil }
        let remainingMinutes = max(0, Int(date.timeIntervalSince(now) / 60))
        return "\(reset) | 剩余 \(DurationFormatter.string(for: remainingMinutes))"
    }
}

enum UsageLimitProgressStyle {
    static func progressValue(for remainingPercent: Double?) -> Double {
        guard let remainingPercent else { return 0 }
        return max(0, min(1, remainingPercent / 100))
    }

    static func tintHex(for remainingPercent: Double?) -> String {
        guard let remainingPercent else { return "#556579" }
        switch remainingPercent {
        case 70...:
            return "#5FE38C"
        case 35..<70:
            return "#F5C46B"
        default:
            return "#FF7A6A"
        }
    }
}

enum HeatmapLabelFormatter {
    static func yearMonthLabel(for week: [Date], previousWeek: [Date]?, calendar: Calendar) -> String {
        guard
            let monthStart = week.first(where: { calendar.component(.day, from: $0) <= 7 }),
            previousWeekContainsSameMonth(previousWeek, as: monthStart, calendar: calendar) == false
        else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter.string(from: monthStart)
    }

    private static func previousWeekContainsSameMonth(
        _ previousWeek: [Date]?,
        as date: Date,
        calendar: Calendar
    ) -> Bool {
        guard let previousWeek else { return false }
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        return previousWeek.contains {
            calendar.component(.month, from: $0) == month && calendar.component(.year, from: $0) == year
        }
    }
}

struct PetAvatarView: View {
    let progress: PetProgress
    let panelPointerLocation: CGPoint?
    let avatarFrameInPanel: CGRect
    let presentationSequence: Int
    let previewMilestones: [PetMilestoneAnimation]
    let previewSequence: Int
    private let playbackStore = PetAnimationPlaybackStore()

    @State private var isFloating = false
    @State private var isBlinking = false
    @State private var isAccessoryGlowing = false
    @State private var isTailSwingingLeft = false
    @State private var isPouncing = false
    @State private var activeReaction: PetTapReaction?
    @State private var activeEasterEgg: PetEasterEgg?
    @State private var activeMilestone: PetMilestoneAnimation?
    @State private var recentTapDates: [Date] = []
    @State private var hoverTask: Task<Void, Never>?
    @State private var milestoneTask: Task<Void, Never>?

    private var palette: PetStagePalette { PetStagePalette(stage: progress.stage) }
    private var motionProfile: PetMotionProfile { PetMotionProfile.profile(for: progress.stage) }

    var body: some View {
        ZStack {
            if let activeMilestone {
                powerBurst(for: activeMilestone)
            }

            if progress.stage == .cursorEgg {
                CatEggFace(
                    palette: palette,
                    lookOffset: eyeLookOffset,
                    isBlinking: isBlinking,
                    reaction: activeReaction,
                    isPouncing: isPouncing
                )
                .frame(width: 44, height: 46)
                .rotationEffect(.degrees(headRotationDegrees))
                .offset(x: headLookOffset.width, y: faceYOffset + headLookOffset.height * 0.7)
                .scaleEffect(baseAvatarScale)
            } else {
                TailShape()
                    .stroke(palette.tail, style: StrokeStyle(lineWidth: progress.stage == .notchGuardian ? 5.8 : 5.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 24)
                    .offset(x: 17 + bodyLookOffset.width * 0.7, y: 8 + bodyLookOffset.height * 0.42)
                    .rotationEffect(.degrees(tailRotationDegrees), anchor: .bottomLeading)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .opacity(0.96)

                CatFace(
                    stage: progress.stage,
                    palette: palette,
                    isBlinking: isBlinking,
                    isAccessoryGlowing: isAccessoryGlowing,
                    lookOffset: eyeLookOffset,
                    isPouncing: isPouncing,
                    activeReaction: activeReaction
                )
                .frame(width: 46, height: 46)
                .rotationEffect(.degrees(headRotationDegrees))
                .offset(x: headLookOffset.width, y: faceYOffset + headLookOffset.height * 0.82)
                .scaleEffect(baseAvatarScale)
            }

            if let activeMilestone {
                MilestoneTextBanner(text: activeMilestone.bannerText)
                    .offset(y: -58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .offset(
            x: isPanelHovered ? bodyLookOffset.width * 1.28 : 0,
            y: (isFloating ? -2.3 : 2.1) + bodyLookOffset.height * 0.78
        )
        .animation(.easeInOut(duration: motionProfile.floatDuration).repeatForever(autoreverses: true), value: isFloating)
        .animation(.easeInOut(duration: motionProfile.tailWagDuration).repeatForever(autoreverses: true), value: isTailSwingingLeft)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isPanelHovered)
        .animation(.spring(response: 0.24, dampingFraction: 0.48), value: isPouncing)
        .animation(.spring(response: 0.28, dampingFraction: 0.62), value: activeReaction)
        .animation(.spring(response: 0.32, dampingFraction: 0.64), value: activeEasterEgg)
        .animation(.spring(response: 0.46, dampingFraction: 0.72), value: activeMilestone)
        .onAppear {
            isFloating = true
            isTailSwingingLeft = true
            scheduleBlink()
            resolveMilestonePresentation()
        }
        .onChange(of: progress.level) { _, _ in
            resolveMilestonePresentation()
        }
        .onChange(of: progress.stage) { _, _ in
            resolveMilestonePresentation()
        }
        .onChange(of: presentationSequence) { _, _ in
            resolveMilestonePresentation()
        }
        .onChange(of: previewSequence) { _, _ in
            guard previewMilestones.isEmpty == false else { return }
            playMilestones(previewMilestones, shouldPersist: false)
        }
        .onChange(of: isPanelHovered) { _, newValue in
            if newValue {
                scheduleLongHoverEasterEgg()
            } else {
                hoverTask?.cancel()
                hoverTask = nil
            }
        }
        .onTapGesture {
            triggerTapInteraction()
        }
    }

    private func scheduleBlink() {
        guard progress.stage != .cursorEgg else { return }
        Task {
            while !Task.isCancelled {
                let pause = UInt64(PetStatusFormatter.blinkInterval(for: progress) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: pause)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isBlinking = true
                    }
                }
                try? await Task.sleep(nanoseconds: 160_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isBlinking = false
                    }
                }
            }
        }
    }

    private func resolveMilestonePresentation() {
        guard previewMilestones.isEmpty else { return }
        let stored = playbackStore.load()
        guard let stored else {
            playbackStore.save(PetAnimationPlaybackState(progress: progress))
            return
        }

        let pending = PetAnimationPlaybackCoordinator.pendingAnimations(current: progress, stored: stored)
        guard pending.isEmpty == false else {
            if stored.presentedLevel != progress.level || stored.presentedStage != progress.stage {
                playbackStore.save(PetAnimationPlaybackState(progress: progress))
            }
            return
        }
        playMilestones(pending, shouldPersist: true)
    }

    private func playMilestones(_ milestones: [PetMilestoneAnimation], shouldPersist: Bool) {
        milestoneTask?.cancel()
        milestoneTask = Task {
            for milestone in milestones {
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        activeMilestone = milestone
                    }
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.28)) {
                        activeMilestone = nil
                    }
                }
                try? await Task.sleep(nanoseconds: 180_000_000)
            }

            if shouldPersist {
                await MainActor.run {
                    playbackStore.save(PetAnimationPlaybackState(progress: progress))
                }
            }
        }
    }

    private var lookOffset: CGSize {
        PetInteractionStyle.lookOffset(
            panelLocation: panelPointerLocation,
            avatarFrame: avatarFrameInPanel
        )
    }

    private var headLookOffset: CGSize {
        CGSize(width: lookOffset.width * 1.8, height: lookOffset.height * 1.15)
    }

    private var eyeLookOffset: CGSize {
        CGSize(width: lookOffset.width * 1.45, height: lookOffset.height * 1.2)
    }

    private var bodyLookOffset: CGSize {
        CGSize(width: lookOffset.width * 1.15, height: lookOffset.height * 0.72)
    }

    private var headRotationDegrees: Double {
        let base = isFloating ? motionProfile.idleTilt : -motionProfile.idleTilt * 0.72
        let hoverTilt = Double(lookOffset.width) * (motionProfile.hoverTilt * 2.4)
        let pounceTilt = isPouncing ? motionProfile.pounceTilt : 0
        let reactionTilt = activeReaction == .headTilt ? motionProfile.reactionTilt : 0
        let milestoneTilt = activeMilestone != nil ? 8.0 : 0
        return base + hoverTilt + pounceTilt + reactionTilt + milestoneTilt
    }

    private var tailRotationDegrees: Double {
        let base = isFloating ? motionProfile.tailBaseAngle : -motionProfile.tailBaseAngle * 0.6
        let wag = isTailSwingingLeft ? motionProfile.tailWagAmplitude : -motionProfile.tailWagAmplitude
        let hoverWave = isPanelHovered ? Double(lookOffset.width) * (motionProfile.hoverTailBias * 1.2) : 0
        let pounceWave = isPouncing ? motionProfile.pounceTailBoost : 0
        let reactionWave = activeReaction == .tailFlick ? (isTailSwingingLeft ? motionProfile.reactionTailBoost : -motionProfile.reactionTailBoost) : 0
        let milestoneWave: Double = activeMilestone != nil ? (isTailSwingingLeft ? 10 : -10) : 0
        let easterEggWave: Double = activeEasterEgg == .tapOverload ? (isTailSwingingLeft ? 24 : -24) : 0
        return base + wag + hoverWave + pounceWave + reactionWave + milestoneWave + easterEggWave
    }

    private var faceYOffset: CGFloat {
        let floatingOffset = isFloating ? -motionProfile.floatOffset : motionProfile.floatOffset * 0.82
        let hoverOffset = isPanelHovered ? headLookOffset.height * 0.54 : 0
        let pounceOffset = isPouncing ? -motionProfile.pounceLift : 0
        let milestoneOffset: CGFloat = activeMilestone != nil ? -2.4 : 0
        return floatingOffset + hoverOffset + pounceOffset + milestoneOffset
    }

    private var isPanelHovered: Bool {
        panelPointerLocation != nil
    }

    private var baseAvatarScale: CGFloat {
        if activeMilestone != nil {
            return 1.12
        }
        if activeEasterEgg == .tapOverload {
            return 1.1
        }
        if isPouncing {
            return motionProfile.pounceScale
        }
        return isFloating ? motionProfile.idleScale : 0.98
    }

    private func triggerTapInteraction() {
        let reaction = PetTapReaction.allCases.randomElement() ?? .squint
        registerTap()

        Task {
            await MainActor.run {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.42)) {
                    isPouncing = true
                    isBlinking = false
                    activeReaction = reaction
                }
            }
            try? await Task.sleep(nanoseconds: 260_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.68)) {
                    isPouncing = false
                }
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.24)) {
                    activeReaction = nil
                }
            }
        }
    }

    private func registerTap() {
        let now = Date()
        recentTapDates = PetInteractionStyle.prunedTapDates(recentTapDates + [now], now: now)
        if PetInteractionStyle.shouldTriggerTapEasterEgg(tapDates: recentTapDates, now: now) {
            triggerEasterEgg(.tapOverload)
        }
    }

    private func scheduleLongHoverEasterEgg() {
        hoverTask?.cancel()
        hoverTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard Task.isCancelled == false, isPanelHovered else { return }
            await MainActor.run {
                triggerEasterEgg(.hoverNuzzle)
            }
        }
    }

    private func triggerEasterEgg(_ easterEgg: PetEasterEgg) {
        activeEasterEgg = easterEgg
        Task {
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                    activeEasterEgg = nil
                }
            }
        }
    }

    @ViewBuilder
    private func powerBurst(for milestone: PetMilestoneAnimation) -> some View {
        ZStack {
            BurstAuraShape(points: milestone.isEvolution ? 18 : 14, innerRatio: milestone.isEvolution ? 0.44 : 0.58)
                .fill(
                    RadialGradient(
                        colors: [
                            palette.accent.opacity(0.88),
                            palette.accent.opacity(0.32),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 3,
                        endRadius: milestone.isEvolution ? 56 : 46
                    )
                )
                    .frame(width: milestone.isEvolution ? 108 : 88, height: milestone.isEvolution ? 108 : 88)
                .scaleEffect(1.02)
                .blur(radius: milestone.isEvolution ? 2.6 : 1.8)

            BurstAuraShape(points: milestone.isEvolution ? 12 : 10, innerRatio: 0.55)
                .stroke(.white.opacity(0.34), lineWidth: 1.4)
                .frame(width: milestone.isEvolution ? 96 : 74, height: milestone.isEvolution ? 96 : 74)
                .scaleEffect(0.98)
                .blur(radius: 0.6)
        }
        .overlay(alignment: .top) {
            if milestone.isLevelUp {
                RisingMilestoneText(text: "LEVEL UP")
                    .offset(y: -16)
            }
        }
    }
}

enum PetStatusFormatter {
    static func statusLine(for progress: PetProgress) -> String {
        if progress.level >= 15 {
            return "守护模式在线，正在盯着你的进度"
        }
        if progress.todayXP >= 40 {
            return "兴奋摇尾巴，今天练级很顺"
        }
        if progress.todayXP >= 15 {
            return "踩着节奏巡逻中，陪你继续写"
        }
        if progress.todayXP > 0 {
            return "已经醒啦，正在等下一次加经验"
        }
        return "打个小盹，等你开始今天的冒险"
    }

    static func indicatorHex(for progress: PetProgress) -> String {
        progress.todayXP == 0 ? "#A0AEC0" : progress.stage.accentHex
    }

    static func blinkInterval(for progress: PetProgress) -> Double {
        switch progress.stage {
        case .cursorEgg:
            100
        case .pixelKitten:
            3.2
        case .terminalCat:
            2.8
        case .mechPatchCat:
            2.4
        case .notchGuardian:
            2.1
        }
    }
}

struct PetStagePalette {
    let accent: Color
    let backdrop: Color
    let fur: Color
    let innerEar: Color
    let muzzle: Color
    let nose: Color
    let tail: Color
    let accessory: Color

    init(stage: PetStage) {
        switch stage {
        case .cursorEgg:
            accent = Color(hex: "#79D0FF")
            backdrop = Color(hex: "#19344F")
            fur = Color(hex: "#F7FBFF")
            innerEar = Color(hex: "#B9E5FF")
            muzzle = Color(hex: "#FFFFFF")
            nose = Color(hex: "#FFB7C8")
            tail = Color(hex: "#EAF7FF")
            accessory = Color(hex: "#7DD8FF")
        case .pixelKitten:
            accent = Color(hex: "#75E59A")
            backdrop = Color(hex: "#173628")
            fur = Color(hex: "#FFF6EC")
            innerEar = Color(hex: "#FFBFC7")
            muzzle = Color(hex: "#FFFDF6")
            nose = Color(hex: "#FF9DAF")
            tail = Color(hex: "#FFF0D8")
            accessory = Color(hex: "#7EF0A5")
        case .terminalCat:
            accent = Color(hex: "#F5C46B")
            backdrop = Color(hex: "#3A2611")
            fur = Color(hex: "#FFE7B8")
            innerEar = Color(hex: "#FFD7A1")
            muzzle = Color(hex: "#FFF3D9")
            nose = Color(hex: "#E99A83")
            tail = Color(hex: "#F5D289")
            accessory = Color(hex: "#8CF4B1")
        case .mechPatchCat:
            accent = Color(hex: "#FF8B6A")
            backdrop = Color(hex: "#411C18")
            fur = Color(hex: "#FFE0D8")
            innerEar = Color(hex: "#FFB7A5")
            muzzle = Color(hex: "#FFF0E9")
            nose = Color(hex: "#F58F87")
            tail = Color(hex: "#FFD0C3")
            accessory = Color(hex: "#FF956C")
        case .notchGuardian:
            accent = Color(hex: "#A4A7FF")
            backdrop = Color(hex: "#1D2248")
            fur = Color(hex: "#EEF0FF")
            innerEar = Color(hex: "#C8CBFF")
            muzzle = Color(hex: "#FFFFFF")
            nose = Color(hex: "#C9B8FF")
            tail = Color(hex: "#E4E6FF")
            accessory = Color(hex: "#B6BAFF")
        }
    }
}

struct PetMotionProfile {
    let idleTilt: Double
    let hoverTilt: Double
    let pounceTilt: Double
    let reactionTilt: Double
    let tailBaseAngle: Double
    let tailWagAmplitude: Double
    let reactionTailBoost: Double
    let pounceTailBoost: Double
    let hoverTailBias: Double
    let pounceLift: CGFloat
    let pounceScale: CGFloat
    let idleScale: CGFloat
    let floatDuration: Double
    let tailWagDuration: Double
    let floatOffset: CGFloat

    static func profile(for stage: PetStage) -> PetMotionProfile {
        switch stage {
        case .cursorEgg:
            PetMotionProfile(idleTilt: 4.4, hoverTilt: 1.1, pounceTilt: 7, reactionTilt: 5, tailBaseAngle: 0, tailWagAmplitude: 0, reactionTailBoost: 0, pounceTailBoost: 0, hoverTailBias: 0, pounceLift: 3.8, pounceScale: 1.07, idleScale: 1.03, floatDuration: 2.35, tailWagDuration: 0.7, floatOffset: 2.2)
        case .pixelKitten:
            PetMotionProfile(idleTilt: 2.8, hoverTilt: 0.95, pounceTilt: 6, reactionTilt: 12, tailBaseAngle: 8, tailWagAmplitude: 19, reactionTailBoost: 26, pounceTailBoost: 10, hoverTailBias: 1.6, pounceLift: 4.2, pounceScale: 1.09, idleScale: 1.04, floatDuration: 2.1, tailWagDuration: 0.55, floatOffset: 2.1)
        case .terminalCat:
            PetMotionProfile(idleTilt: 2.2, hoverTilt: 0.82, pounceTilt: 5.6, reactionTilt: 10, tailBaseAngle: 7, tailWagAmplitude: 16, reactionTailBoost: 22, pounceTailBoost: 9, hoverTailBias: 1.4, pounceLift: 4, pounceScale: 1.08, idleScale: 1.03, floatDuration: 2.2, tailWagDuration: 0.62, floatOffset: 2.0)
        case .mechPatchCat:
            PetMotionProfile(idleTilt: 1.8, hoverTilt: 0.74, pounceTilt: 4.8, reactionTilt: 8, tailBaseAngle: 6, tailWagAmplitude: 14, reactionTailBoost: 20, pounceTailBoost: 8, hoverTailBias: 1.2, pounceLift: 3.6, pounceScale: 1.07, idleScale: 1.02, floatDuration: 2.35, tailWagDuration: 0.68, floatOffset: 1.8)
        case .notchGuardian:
            PetMotionProfile(idleTilt: 1.3, hoverTilt: 0.62, pounceTilt: 4.2, reactionTilt: 7, tailBaseAngle: 5, tailWagAmplitude: 12, reactionTailBoost: 16, pounceTailBoost: 7, hoverTailBias: 1.0, pounceLift: 3.2, pounceScale: 1.06, idleScale: 1.01, floatDuration: 2.5, tailWagDuration: 0.74, floatOffset: 1.6)
        }
    }
}

struct PetAnimationPlaybackState: Codable, Equatable, Sendable {
    let presentedLevel: Int
    let presentedStage: PetStage

    init(presentedLevel: Int, presentedStage: PetStage) {
        self.presentedLevel = presentedLevel
        self.presentedStage = presentedStage
    }

    init(progress: PetProgress) {
        presentedLevel = progress.level
        presentedStage = progress.stage
    }
}

struct PetAnimationPlaybackStore {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "CodexTray.pet-animation-playback"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() -> PetAnimationPlaybackState? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(PetAnimationPlaybackState.self, from: data)
    }

    func save(_ state: PetAnimationPlaybackState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}

enum PetMilestoneAnimation: Equatable {
    case levelUp(level: Int)
    case evolution(from: PetStage, to: PetStage)

    var label: String {
        switch self {
        case .levelUp(let level):
            "升级到 Lv.\(level)"
        case .evolution(_, let to):
            "进化成\(to.displayName)"
        }
    }

    var bannerText: String {
        switch self {
        case .levelUp(let level):
            "Lv.\(level)"
        case .evolution(_, let to):
            to.displayName
        }
    }

    var isEvolution: Bool {
        if case .evolution = self {
            return true
        }
        return false
    }

    var isLevelUp: Bool {
        if case .levelUp = self {
            return true
        }
        return false
    }
}

enum PetAnimationPlaybackCoordinator {
    static func pendingAnimations(current: PetProgress, stored: PetAnimationPlaybackState?) -> [PetMilestoneAnimation] {
        guard let stored else { return [] }
        guard current.level >= stored.presentedLevel else { return [] }

        var animations: [PetMilestoneAnimation] = []
        if current.stage != stored.presentedStage {
            animations.append(.evolution(from: stored.presentedStage, to: current.stage))
        }
        if current.level > stored.presentedLevel {
            animations.append(.levelUp(level: current.level))
        }
        return animations
    }
}

enum PetInteractionStyle {
    static func lookOffset(panelLocation: CGPoint?, avatarFrame: CGRect) -> CGSize {
        guard let panelLocation, avatarFrame.equalTo(.zero) == false else { return .zero }
        let localX = panelLocation.x - avatarFrame.midX
        let localY = panelLocation.y - avatarFrame.midY
        // Use a larger influence radius than the avatar itself so motion reads across the whole panel.
        let normalizedX = (localX / 220).clamped(to: -1...1)
        let normalizedY = (localY / 140).clamped(to: -1...1)
        return CGSize(width: normalizedX * 7.4, height: normalizedY * 5.2)
    }

    static func prunedTapDates(_ tapDates: [Date], now: Date) -> [Date] {
        tapDates.filter { now.timeIntervalSince($0) <= 2.4 }
    }

    static func shouldTriggerTapEasterEgg(tapDates: [Date], now: Date) -> Bool {
        prunedTapDates(tapDates, now: now).count >= 4
    }
}

enum PetTapReaction: CaseIterable {
    case squint
    case headTilt
    case tailFlick

    func label(for stage: PetStage) -> String {
        switch self {
        case .squint:
            return stage == .cursorEgg ? "蛋壳眨眨" : "眯眼!"
        case .headTilt:
            return stage == .notchGuardian ? "侧首注视" : "歪头?"
        case .tailFlick:
            return stage == .terminalCat ? "终端甩尾" : "甩尾!"
        }
    }
}

enum PetEasterEgg: Equatable {
    case hoverNuzzle
    case tapOverload

    func label(for stage: PetStage) -> String {
        switch self {
        case .hoverNuzzle:
            return stage == .cursorEgg ? "轻轻蹭壳" : "蹭蹭你"
        case .tapOverload:
            return stage == .mechPatchCat ? "动力过载!" : "开心过载!"
        }
    }
}

enum PetPreviewFactory {
    static let previewLevels: [Int] = [0, 3, 6, 10, 15]

    static func progress(for level: Int, todayXP: Int) -> PetProgress {
        let totalXP = (0..<max(0, level)).reduce(0) { $0 + PetProgressCalculator.xpNeeded(for: $1) }
        let levelXP = max(12, PetProgressCalculator.xpNeeded(for: level) / 6)
        return PetProgressCalculator.progress(totalXP: totalXP + levelXP, todayXP: todayXP)
    }

    static func previewMilestones(from previous: PetProgress, to next: PetProgress) -> [PetMilestoneAnimation] {
        guard previous != next else { return [] }
        var milestones: [PetMilestoneAnimation] = []
        if previous.stage != next.stage {
            milestones.append(.evolution(from: previous.stage, to: next.stage))
        }
        if previous.level != next.level {
            milestones.append(.levelUp(level: next.level))
        }
        return milestones
    }
}

enum PetDialogueLibrary {
    static func messages(for progress: PetProgress) -> [String] {
        let common = [
            "你写代码，我在旁边给你加油。",
            "今天也一起把 bug 赶跑吧。",
            "慢一点没关系，我们稳稳推进。",
            "这段写完就算一次漂亮升级。",
            "我在盯着进度，你别怕。",
            "辛苦啦，先把这一小段做好。",
            "你负责输出，我负责可爱。",
            "再来一点点，经验条会动的。",
            "我觉得你马上就要写顺了。",
            "别急，我陪你一起磨过去。",
            "这一行改得不错，继续。",
            "看起来今天状态很能打。",
            "遇到难题时，先深呼吸一下。",
            "小猫判断：你完全可以。",
            "再提交一次，我们就更强了。",
            "今天也要把灵感攒满。",
            "先搞定一个点，就是胜利。",
            "你动手的时候，我就在认真看着。",
            "把今天的经验都赚回来。",
            "别担心，我感觉这题有戏。",
        ]

        let stageSpecific: [String]
        switch progress.stage {
        case .cursorEgg:
            stageSpecific = [
                "蛋壳里暖暖的，我在等你带我孵化。",
                "再多一点经验，我就要破壳看看世界了。",
                "轻轻敲一敲，今天也能长大一点。",
                "壳里听见键盘声，就会很安心。",
            ]
        case .pixelKitten:
            stageSpecific = [
                "像素小爪已经准备好陪跑了。",
                "今天的 commit 闻起来像成长。",
                "有我在，你可以再大胆试一次。",
                "再赚点 XP，我就想冲向下一形态。",
            ]
        case .terminalCat:
            stageSpecific = [
                "终端窗口亮起来，我也跟着精神了。",
                "这次输出看起来很专业，喵。",
                "给我一段漂亮日志，我能高兴半天。",
                "继续敲，我来帮你镇场子。",
            ]
        case .mechPatchCat:
            stageSpecific = [
                "补丁装填完毕，准备冲刺。",
                "动力核心已经预热，继续推进。",
                "今天这股执行力，很机甲。",
                "修完这个点，我们一起闪闪发光。",
            ]
        case .notchGuardian:
            stageSpecific = [
                "守护模式已启动，你只管往前写。",
                "这局面我罩着，你大胆一点。",
                "现在的你，很像能独当一面的开发者。",
                "进化到这里了，我们就更不能怂。",
            ]
        }

        if progress.todayXP == 0 {
            return [
                "我刚醒，等你带我开工。",
                "今天第一点经验，要不要现在就拿下？",
                "还没开张呢，我先趴一会儿。",
            ] + stageSpecific + common
        }
        return stageSpecific + common
    }

    static func message(for progress: PetProgress, tick: Int) -> String {
        let lines = messages(for: progress)
        guard lines.isEmpty == false else { return "" }
        let safeTick = max(0, tick)
        let index = (safeTick + progress.level + max(0, progress.todayXP / 5)) % lines.count
        return lines[index]
    }
}

struct YearContributionHeatmap: View {
    let days: [UsageMetricsDay]
    let colorPreset: HeatmapColorPreset
    @State private var hoveredCell: HoveredHeatmapCell?
    private let calendar: Calendar
    private let lookup: [Date: UsageMetricsDay]
    private let startDate: Date
    private let weeks: [[Date]]

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    init(days: [UsageMetricsDay], colorPreset: HeatmapColorPreset) {
        self.days = days
        self.colorPreset = colorPreset
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        self.calendar = calendar
        self.lookup = Dictionary(uniqueKeysWithValues: days.map { (calendar.startOfDay(for: $0.date), $0) })

        let sortedDays = days.sorted { $0.date < $1.date }
        let firstDate = sortedDays.first?.date ?? calendar.startOfDay(for: .now)
        let lastDate = sortedDays.last?.date ?? calendar.startOfDay(for: .now)
        let firstDay = calendar.startOfDay(for: firstDate)
        let startDate = calendar.dateInterval(of: .weekOfYear, for: firstDay)?.start ?? firstDay
        self.startDate = startDate
        let endDate = calendar.startOfDay(for: lastDate)
        let rawDayCount = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        let totalDays = max(7, rawDayCount + 1)
        let weekCount = max(1, Int(ceil(Double(totalDays) / 7.0)))
        self.weeks = (0..<weekCount).map { weekIndex in
            (0..<7).map { dayIndex in
                calendar.date(byAdding: .day, value: weekIndex * 7 + dayIndex, to: startDate) ?? startDate
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let labelWidth: CGFloat = 28
            let columns = CGFloat(weeks.count)
            let spacing: CGFloat = 4
            let availableWidth = max(240, geometry.size.width - labelWidth - 8)
            let availableHeight = max(84, geometry.size.height - 12)
            let cellWidth = max(8, (availableWidth - ((columns - 1) * spacing)) / columns)
            let cellHeight = max(10, (availableHeight - (spacing * 6)) / 7)

            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: spacing) {
                    Color.clear.frame(height: 12)
                    ForEach(0..<7, id: \.self) { row in
                        Text(weekdayLabel(for: row))
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.34))
                            .frame(width: labelWidth, height: cellHeight, alignment: .leading)
                    }
                }

                HStack(spacing: spacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                        VStack(spacing: spacing) {
                            Color.clear
                                .frame(width: cellWidth, height: 12)
                                .overlay(alignment: .leading) {
                                    let label = monthLabel(for: index)
                                    if !label.isEmpty {
                                        Text(label)
                                            .font(.system(size: 8, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.34))
                                            .frame(width: 22, alignment: .leading)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .allowsHitTesting(false)
                                    }
                                }

                            ForEach(week, id: \.self) { date in
                                let day = lookup[calendar.startOfDay(for: date)] ?? .empty(for: date)
                                GeometryReader { cellGeometry in
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(HeatmapPalette.color(for: day.heatmapLevel, preset: colorPreset))
                                        .frame(width: cellWidth, height: cellHeight)
                                        .contentShape(Rectangle())
                                        .onHover { isHovered in
                                            if isHovered {
                                                hoveredCell = HoveredHeatmapCell(
                                                    day: day,
                                                    frame: cellGeometry.frame(in: .named("heatmap-grid"))
                                                )
                                            } else if hoveredCell?.day.id == day.id {
                                                hoveredCell = nil
                                            }
                                        }
                                }
                                .frame(width: cellWidth, height: cellHeight)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: "heatmap-grid")
            .overlay(alignment: .topLeading) {
                if let hoveredCell {
                    HeatmapTooltip(text: tooltipText(for: hoveredCell.day))
                        .position(
                            x: min(max(hoveredCell.frame.midX, 72), max(72, geometry.size.width - 72)),
                            y: max(14, hoveredCell.frame.minY - 22)
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: HeatmapRange.year.heatmapHeight)
    }

    private func weekdayLabel(for row: Int) -> String {
        ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][row]
    }

    private func monthLabel(for index: Int) -> String {
        HeatmapLabelFormatter.yearMonthLabel(
            for: weeks[index],
            previousWeek: index > 0 ? weeks[index - 1] : nil,
            calendar: calendar
        )
    }

    private func tooltipText(for day: UsageMetricsDay) -> String {
        UsageDisplayFormatter.heatmapTooltipText(for: day, dateFormatter: Self.tooltipDateFormatter)
    }
}

struct MonthCalendarHeatmap: View {
    let days: [UsageMetricsDay]
    let colorPreset: HeatmapColorPreset
    @State private var hoveredCell: HoveredHeatmapCell?

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    private var sortedDays: [UsageMetricsDay] {
        days.sorted { $0.date < $1.date }
    }

    private var displayedMonth: Date {
        let reference = sortedDays.last?.date ?? .now
        return calendar.dateInterval(of: .month, for: reference)?.start ?? reference
    }

    private var monthGridDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let startWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingDays = (startWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthInterval.start) ?? monthInterval.start
        let endWeekday = calendar.component(.weekday, from: monthInterval.end.addingTimeInterval(-1))
        let trailingDays = (calendar.firstWeekday + 6 - endWeekday + 7) % 7
        let gridEnd = calendar.date(byAdding: .day, value: trailingDays, to: monthInterval.end.addingTimeInterval(-1)) ?? monthInterval.end
        let dayCount = (calendar.dateComponents([.day], from: gridStart, to: gridEnd).day ?? 0) + 1
        return (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var weeks: [[Date]] {
        stride(from: 0, to: monthGridDays.count, by: 7).map { index in
            Array(monthGridDays[index..<min(index + 7, monthGridDays.count)])
        }
    }

    private var lookup: [Date: UsageMetricsDay] {
        Dictionary(uniqueKeysWithValues: days.map { (calendar.startOfDay(for: $0.date), $0) })
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 8
            let cellWidth = max(36, (geometry.size.width - (spacing * 6)) / 7)
            let cellHeight = max(34, (geometry.size.height - 36 - (spacing * CGFloat(max(weeks.count - 1, 0)))) / CGFloat(max(weeks.count, 1)))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    Text(monthTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.54))
                    Spacer()
                }

                HStack(spacing: spacing) {
                    ForEach(calendar.shortWeekdaySymbolsShifted, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity)
                    }
                }

                VStack(spacing: spacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        HStack(spacing: spacing) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                                let day = lookup[calendar.startOfDay(for: date)] ?? .empty(for: date)
                                HeatmapCalendarCell(
                                    day: day,
                                    colorPreset: colorPreset,
                                    isCurrentMonth: calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month),
                                    cornerRadius: 10,
                                    dayFontSize: 12,
                                    coordinateSpaceName: "month-heatmap-grid"
                                ) { frame, isHovered in
                                    updateHover(for: day, frame: frame, isHovered: isHovered)
                                }
                                .frame(width: cellWidth, height: cellHeight)
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: "month-heatmap-grid")
            .overlay(alignment: .topLeading) {
                if let hoveredCell {
                    HeatmapTooltip(text: tooltipText(for: hoveredCell.day))
                        .position(
                            x: min(max(hoveredCell.frame.midX, 72), max(72, geometry.size.width - 72)),
                            y: max(14, hoveredCell.frame.minY - 18)
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: HeatmapRange.month.heatmapHeight - 12)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter.string(from: displayedMonth)
    }

    private func updateHover(for day: UsageMetricsDay, frame: CGRect, isHovered: Bool) {
        if isHovered {
            hoveredCell = HoveredHeatmapCell(day: day, frame: frame)
        } else if hoveredCell?.day.id == day.id {
            hoveredCell = nil
        }
    }

    private func tooltipText(for day: UsageMetricsDay) -> String {
        UsageDisplayFormatter.heatmapTooltipText(for: day, dateFormatter: Self.tooltipDateFormatter)
    }
}

struct WeekStripHeatmap: View {
    let days: [UsageMetricsDay]
    let colorPreset: HeatmapColorPreset
    @State private var hoveredCell: HoveredHeatmapCell?
    private let calendar: Calendar
    private let sortedDays: [UsageMetricsDay]

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    init(days: [UsageMetricsDay], colorPreset: HeatmapColorPreset) {
        self.days = days
        self.colorPreset = colorPreset
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        self.calendar = calendar
        self.sortedDays = days.sorted { $0.date < $1.date }
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 12
            let cellWidth = max(72, (geometry.size.width - (spacing * 6)) / 7)
            let cellHeight = max(64, geometry.size.height - 22)

            HStack(alignment: .top, spacing: spacing) {
                ForEach(sortedDays) { day in
                    VStack(spacing: 10) {
                        Text(weekdayHeader(for: day.date))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))

                        HeatmapCalendarCell(
                            day: day,
                            colorPreset: colorPreset,
                            isCurrentMonth: true,
                            cornerRadius: 12,
                            dayFontSize: 22,
                            coordinateSpaceName: "week-heatmap-grid"
                        ) { frame, isHovered in
                            updateHover(for: day, frame: frame, isHovered: isHovered)
                        }
                        .frame(width: cellWidth, height: cellHeight)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .coordinateSpace(name: "week-heatmap-grid")
            .overlay(alignment: .topLeading) {
                if let hoveredCell {
                    HeatmapTooltip(text: tooltipText(for: hoveredCell.day))
                        .position(
                            x: min(max(hoveredCell.frame.midX, 72), max(72, geometry.size.width - 72)),
                            y: max(14, hoveredCell.frame.minY - 18)
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: HeatmapRange.week.heatmapHeight)
    }

    private func weekdayHeader(for date: Date) -> String {
        let weekdayIndex = calendar.component(.weekday, from: date)
        let weekday = calendar.shortStandaloneWeekdaySymbols[(weekdayIndex - 1) % calendar.shortStandaloneWeekdaySymbols.count]
        let day = calendar.component(.day, from: date)
        return "\(day)日 \(weekday)"
    }

    private func updateHover(for day: UsageMetricsDay, frame: CGRect, isHovered: Bool) {
        if isHovered {
            hoveredCell = HoveredHeatmapCell(day: day, frame: frame)
        } else if hoveredCell?.day.id == day.id {
            hoveredCell = nil
        }
    }

    private func tooltipText(for day: UsageMetricsDay) -> String {
        UsageDisplayFormatter.heatmapTooltipText(for: day, dateFormatter: Self.tooltipDateFormatter)
    }
}

enum HeatmapRange: String, CaseIterable, Identifiable, Codable, CustomStringConvertible {
    case year
    case month
    case week

    var id: String { rawValue }

    var heatmapHeight: CGFloat {
        switch self {
        case .year:
            146
        case .month:
            310
        case .week:
            142
        }
    }

    var title: String {
        switch self {
        case .year:
            "最近一年"
        case .month:
            "最近一月"
        case .week:
            "最近一周"
        }
    }

    var description: String { title }
}

private struct HoveredHeatmapCell: Equatable {
    let day: UsageMetricsDay
    let frame: CGRect
}

private struct HeatmapCalendarCell: View {
    let day: UsageMetricsDay
    let colorPreset: HeatmapColorPreset
    let isCurrentMonth: Bool
    let cornerRadius: CGFloat
    let dayFontSize: CGFloat
    let coordinateSpaceName: String
    let onHoverChanged: (CGRect, Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(HeatmapPalette.color(for: day.heatmapLevel, preset: colorPreset).opacity(isCurrentMonth ? 1 : 0.52))

                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(.system(size: dayFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(isCurrentMonth ? .white : .white.opacity(0.34))
            }
            .contentShape(Rectangle())
            .onHover { isHovered in
                onHoverChanged(geometry.frame(in: .named(coordinateSpaceName)), isHovered)
            }
        }
    }

}

private struct HeatmapTooltip: View {
    let text: String
    var width: CGFloat? = nil
    var multilineAlignment: TextAlignment = .center

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(multilineAlignment)
            .lineLimit(nil)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: width, alignment: multilineAlignment == .leading ? .leading : .center)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

private extension Calendar {
    var shortWeekdaySymbolsShifted: [String] {
        let symbols = shortStandaloneWeekdaySymbols
        let shift = max(0, firstWeekday - 1)
        return Array(symbols[shift...]) + Array(symbols[..<shift])
    }
}

private struct SettingsCardView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settingsStore: AppSettingsStore
    let onClose: () -> Void

    private var settings: AppSettings { settingsStore.settings }
    private var availableDefaultAgentOptions: [DefaultAgentPreference] {
        DefaultAgentPreference.options(for: store.multiAgentSnapshot.agents.filter(\.isAvailable).map(\.agent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("设置")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            settingPickerRow(
                title: "默认展示 Agent",
                options: availableDefaultAgentOptions,
                selection: Binding(
                    get: { settings.defaultAgent },
                    set: { settingsStore.updateDefaultAgent($0) }
                )
            )

            settingPickerRow(
                title: "默认热力图范围",
                options: HeatmapRange.allCases,
                selection: Binding(
                    get: { settings.defaultHeatmapRange },
                    set: { settingsStore.updateDefaultHeatmapRange($0) }
                )
            )

            settingPickerRow(
                title: "刷新频率",
                options: RefreshIntervalOption.allCases,
                selection: Binding(
                    get: { settings.refreshInterval },
                    set: { settingsStore.updateRefreshInterval($0) }
                )
            )

            Toggle(isOn: Binding(
                get: { settings.showsHotspot },
                set: { settingsStore.updateShowsHotspot($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("显示顶部热点")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("关闭后仅从菜单栏图标展开面板")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("主题色")
                swatchRow(
                    selections: ThemeTintPreset.allCases,
                    currentValue: settings.themeTint,
                    color: { Color(hex: $0.hex) },
                    label: { $0.title }
                ) { settingsStore.updateThemeTint($0) }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("热力图颜色")
                swatchRow(
                    selections: HeatmapColorPreset.allCases,
                    currentValue: settings.heatmapColor,
                    color: { Color(hex: $0.hex) },
                    label: { $0.title }
                ) { settingsStore.updateHeatmapColor($0) }
                HeatmapLegend(colorPreset: settings.heatmapColor)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 16, y: 10)
        .onAppear(perform: sanitizeDefaultAgentPreference)
        .onChange(of: availableDefaultAgentOptions) { _, _ in
            sanitizeDefaultAgentPreference()
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
    }

    private func settingPickerRow<Value: Hashable & Identifiable>(
        title: String,
        options: [Value],
        selection: Binding<Value>
    ) -> some View where Value: CustomStringConvertible {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.description).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.white.opacity(0.88))
        }
    }

    private func sanitizeDefaultAgentPreference() {
        guard availableDefaultAgentOptions.contains(settings.defaultAgent) == false else { return }
        settingsStore.updateDefaultAgent(.all)
    }

    private func swatchRow<Selection: Identifiable & Equatable>(
        selections: [Selection],
        currentValue: Selection,
        color: @escaping (Selection) -> Color,
        label: @escaping (Selection) -> String,
        onSelect: @escaping (Selection) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ForEach(selections) { option in
                Button {
                    onSelect(option)
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(color(option))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(option == currentValue ? 0.95 : 0.18), lineWidth: option == currentValue ? 2 : 1)
                            )
                        Text(label(option))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(option == currentValue ? 0.9 : 0.5))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct HeatmapLegend: View {
    let colorPreset: HeatmapColorPreset

    var body: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.34))
            ForEach(0..<5, id: \.self) { level in
                Circle()
                    .fill(HeatmapPalette.color(for: level, preset: colorPreset))
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.34))
        }
    }
}

struct ChromeButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(configuration.isPressed ? 0.24 : 0.14))
            )
    }
}

enum HeatmapPalette {
    static func color(for level: Int, preset: HeatmapColorPreset) -> Color {
        Color(hex: hex(for: level, preset: preset))
    }

    static func hex(for level: Int, preset: HeatmapColorPreset) -> String {
        let colors = preset.gradientHexes
        let safeIndex = max(0, min(level, colors.count - 1))
        return colors[safeIndex]
    }
}

struct CatEggFace: View {
    let palette: PetStagePalette
    let lookOffset: CGSize
    let isBlinking: Bool
    let reaction: PetTapReaction?
    let isPouncing: Bool

    var body: some View {
        ZStack {
            Triangle()
                .fill(palette.fur)
                .frame(width: 11, height: 11)
                .offset(x: -8.5, y: -12)
            Triangle()
                .fill(palette.fur)
                .frame(width: 11, height: 11)
                .offset(x: 8.5, y: -12)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.fur, palette.fur.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 28, height: 37)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(.white.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .blur(radius: 0.8)
                        .offset(x: 5, y: 5)
                }
                .overlay {
                    EggCrackShape()
                        .stroke(palette.accessory.opacity(0.55), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .frame(width: 16, height: 8)
                        .offset(y: 2)
                }

            HStack(spacing: 8) {
                eggEye
                eggEye
            }
            .offset(x: lookOffset.width * 2.6, y: -1 + lookOffset.height * 1.7)

            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(palette.nose)
                .frame(width: reaction == .headTilt ? 8 : 6, height: 3.5)
                .offset(x: lookOffset.width * 1.35, y: 6 + lookOffset.height * 0.68)
        }
        .scaleEffect(isPouncing ? 1.06 : 1)
    }

    private var eggEye: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.96))
                .frame(width: 7.4, height: isBlinking || reaction == .squint ? 1.6 : 5.8)
            Circle()
                .fill(Color.black.opacity(0.82))
                .frame(width: 2.5, height: 2.5)
                .offset(
                    x: isBlinking || reaction == .squint ? 0 : lookOffset.width * 0.22,
                    y: isBlinking || reaction == .squint ? 0 : lookOffset.height * 0.16
                )
                .opacity(isBlinking || reaction == .squint ? 0 : 1)
        }
    }
}

struct CatFace: View {
    let stage: PetStage
    let palette: PetStagePalette
    let isBlinking: Bool
    let isAccessoryGlowing: Bool
    let lookOffset: CGSize
    let isPouncing: Bool
    let activeReaction: PetTapReaction?

    var body: some View {
        ZStack {
            Color.clear
            ear(offsetX: -10)
            ear(offsetX: 10)
            headBase
            muzzle
            whiskers
            HStack(spacing: eyeSpacing) {
                eye
                eye
            }
            .offset(x: lookOffset.width * 2.4, y: eyeYOffset + lookOffset.height * 1.35)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(palette.nose)
                .frame(width: activeReaction == .headTilt ? 8 : 6.5, height: 4)
                .offset(x: lookOffset.width * 1.2, y: 9 + lookOffset.height * 0.6)

            accessory
        }
    }

    private var headBase: some View {
        Group {
            switch stage {
            case .pixelKitten:
                Circle()
                    .fill(palette.fur)
                    .frame(width: 34, height: 31)
                    .offset(y: 5)
            case .terminalCat:
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.fur)
                    .frame(width: 36, height: 29)
                    .offset(y: 5)
            case .mechPatchCat:
                AngularCatHead()
                    .fill(palette.fur)
                    .frame(width: 38, height: 31)
                    .offset(y: 5)
            case .notchGuardian:
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(palette.fur)
                    .frame(width: 34, height: 31)
                    .offset(y: 5)
            case .cursorEgg:
                EmptyView()
            }
        }
        .overlay {
            if stage == .mechPatchCat {
                AngularCatHead()
                    .stroke(palette.accessory.opacity(0.55), lineWidth: 1)
                    .frame(width: 38, height: 31)
                    .offset(y: 5)
            }
        }
        .scaleEffect(x: isPouncing ? 1.04 : 1, y: activeReaction == .squint ? 0.94 : (isPouncing ? 0.97 : 1))
    }

    private var muzzle: some View {
        Capsule(style: .continuous)
            .fill(palette.muzzle)
            .frame(width: stage == .terminalCat ? 18 : 16, height: stage == .mechPatchCat ? 10 : 11)
            .offset(y: 11)
    }

    private var whiskers: some View {
        Group {
            if stage != .mechPatchCat {
                whiskerSide(direction: -1)
                whiskerSide(direction: 1)
            }
        }
    }

    private func whiskerSide(direction: CGFloat) -> some View {
        VStack(spacing: 2) {
            Rectangle().fill(Color.black.opacity(0.18)).frame(width: 8, height: 1)
            Rectangle().fill(Color.black.opacity(0.18)).frame(width: 7, height: 1)
        }
        .offset(x: direction * 13, y: 10)
        .rotationEffect(.degrees(direction < 0 ? -8 : 8))
    }

    private func ear(offsetX: CGFloat) -> some View {
        Triangle()
            .fill(palette.fur)
            .frame(width: earSize.width, height: earSize.height)
            .overlay {
                Triangle()
                    .fill(palette.innerEar)
                    .frame(width: earSize.width * 0.52, height: earSize.height * 0.52)
                    .offset(y: 1)
            }
            .offset(x: offsetX, y: earOffsetY)
            .rotationEffect(.degrees(offsetX < 0 ? leftEarRotation : rightEarRotation))
    }

    private var eye: some View {
        CatEye(
            tint: stage == .terminalCat ? palette.accessory : Color.black,
            lookOffset: lookOffset,
            isBlinking: isBlinking || activeReaction == .squint,
            isWide: isPouncing
        )
    }

    private var eyeSpacing: CGFloat {
        stage == .notchGuardian ? 10 : 8.5
    }

    private var eyeYOffset: CGFloat {
        stage == .terminalCat ? 2.5 : 4.2
    }

    private var earSize: CGSize {
        switch stage {
        case .pixelKitten:
            CGSize(width: 11, height: 12)
        case .terminalCat:
            CGSize(width: 10, height: 11)
        case .mechPatchCat:
            CGSize(width: 12, height: 12)
        case .notchGuardian:
            CGSize(width: 10, height: 14)
        case .cursorEgg:
            CGSize(width: 10, height: 10)
        }
    }

    private var earOffsetY: CGFloat {
        switch stage {
        case .notchGuardian:
            -9
        case .mechPatchCat:
            -7
        default:
            -6
        }
    }

    private var leftEarRotation: Double {
        let base = stage == .notchGuardian ? -12.0 : -7.0
        return base + (isAccessoryGlowing ? -3.0 : 2.0)
    }

    private var rightEarRotation: Double {
        let base = stage == .notchGuardian ? 12.0 : 7.0
        return base + (isAccessoryGlowing ? 3.0 : -2.0)
    }

    @ViewBuilder
    private var accessory: some View {
        switch stage {
        case .pixelKitten:
            Circle()
                .fill(palette.accessory.opacity(0.9))
                .frame(width: 5, height: 5)
                .overlay {
                    Circle().stroke(.white.opacity(0.5), lineWidth: 0.8)
                }
                .offset(x: 12, y: -8)
                .scaleEffect(isAccessoryGlowing ? 1.18 : 0.94)
        case .terminalCat:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hex: "#10261A"))
                .frame(width: 18, height: 11)
                .overlay {
                    Text(">")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.accessory)
                }
                .offset(y: -4)
                .scaleEffect(isAccessoryGlowing ? 1.08 : 0.98)
        case .mechPatchCat:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(palette.accessory.opacity(0.9))
                .frame(width: 9, height: 9)
                .overlay {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .offset(x: 12, y: -8)
                .rotationEffect(.degrees(isAccessoryGlowing ? 18 : 2))
        case .notchGuardian:
            GuardianCrest()
                .fill(palette.accessory)
                .frame(width: 12, height: 10)
                .offset(y: -12)
                .scaleEffect(isAccessoryGlowing ? 1.1 : 0.96)
        case .cursorEgg:
            EmptyView()
        }
    }
}

struct TailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 3, y: rect.maxY - 2))
        path.addCurve(
            to: CGPoint(x: rect.midX + 1, y: rect.midY + 1),
            control1: CGPoint(x: rect.minX + 1, y: rect.midY + 5),
            control2: CGPoint(x: rect.midX - 5, y: rect.midY + 5)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - 3, y: rect.minY + 3),
            control1: CGPoint(x: rect.midX + 6, y: rect.midY - 8),
            control2: CGPoint(x: rect.maxX - 1, y: rect.midY - 3)
        )
        return path
    }
}

struct CatEye: View {
    let tint: Color
    let lookOffset: CGSize
    let isBlinking: Bool
    let isWide: Bool

    var body: some View {
        Capsule(style: .continuous)
            .fill(tint.opacity(0.94))
            .frame(
                width: isWide ? 9.8 : 8.8,
                height: isBlinking ? 1.2 : (isWide ? 4.6 : 3.9)
            )
            .offset(
                x: isBlinking ? 0 : lookOffset.width * 0.52,
                y: isBlinking ? 0 : lookOffset.height * 0.34
            )
    }
}

struct EggCrackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.64, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + 1))
        return path
    }
}

struct AngularCatHead: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 2))
        path.addLine(to: CGPoint(x: rect.minX + 2, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + 7, y: rect.minY + 6))
        path.addLine(to: CGPoint(x: rect.midX - 4, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + 4))
        path.addLine(to: CGPoint(x: rect.midX + 4, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 7, y: rect.minY + 6))
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY - 2))
        path.closeSubpath()
        return path
    }
}

struct GuardianCrest: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 2, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct PetSpeechBubble: View {
    let text: String
    let isEasterEgg: Bool

    var body: some View {
        Text(text)
            .font(.system(size: isEasterEgg ? 10 : 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, isEasterEgg ? 10 : 8)
            .padding(.vertical, isEasterEgg ? 6 : 5)
            .background(
                Capsule(style: .continuous)
                    .fill(.black.opacity(isEasterEgg ? 0.72 : 0.56))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(isEasterEgg ? 0.38 : 0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }
}

struct PetAvatarFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct PetDeveloperPreviewMenu: ViewModifier {
    let progress: PetProgress
    @Binding var petPreviewProgress: PetProgress?
    @Binding var petPreviewMilestones: [PetMilestoneAnimation]
    @Binding var petPreviewSequence: Int
    @Binding var petDialogueTick: Int

    func body(content: Content) -> some View {
        content.contextMenu {
            Text("预览宠物形态")
            ForEach(PetPreviewFactory.previewLevels, id: \.self) { level in
                Button("预览 Lv.\(level)") {
                    let next = PetPreviewFactory.progress(for: level, todayXP: progress.todayXP)
                    let previous = petPreviewProgress ?? progress
                    petPreviewProgress = next
                    petPreviewMilestones = PetPreviewFactory.previewMilestones(from: previous, to: next)
                    petPreviewSequence += 1
                    petDialogueTick += 1
                }
            }
            Button("恢复真实进度") {
                petPreviewProgress = nil
                petPreviewMilestones = []
                petPreviewSequence += 1
                petDialogueTick += 1
            }
        }
    }
}

struct BurstAuraShape: Shape {
    let points: Int
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let safePoints = max(4, points)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRatio
        let angleStep = .pi / CGFloat(safePoints)
        var path = Path()

        for index in 0..<(safePoints * 2) {
            let angle = (CGFloat(index) * angleStep) - (.pi / 2)
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct MilestoneTextBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.45))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            )
    }
}

struct RisingMilestoneText: View {
    let text: String
    @State private var isVisible = false

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(hex: "#FFF4A8"), .white],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: Color(hex: "#FFD84D").opacity(0.5), radius: 10, y: 2)
            .offset(y: isVisible ? -18 : 2)
            .opacity(isVisible ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9)) {
                    isVisible = true
                }
            }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var integer: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&integer)
        let red = Double((integer >> 16) & 0xFF) / 255
        let green = Double((integer >> 8) & 0xFF) / 255
        let blue = Double(integer & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
