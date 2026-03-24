import Combine
import SwiftUI

struct PanelRootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settingsStore: AppSettingsStore
    let onQuit: () -> Void
    var onHeatmapRangeChange: (HeatmapRange, AgentKind) -> Void
    @State private var heatmapRange: HeatmapRange
    @State private var isPetGuideHovered = false
    @State private var isSettingsPresented = false

    init(
        store: UsageStore,
        settingsStore: AppSettingsStore,
        onQuit: @escaping () -> Void,
        onHeatmapRangeChange: @escaping (HeatmapRange, AgentKind) -> Void
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.onQuit = onQuit
        self.onHeatmapRangeChange = onHeatmapRangeChange
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
                settingsOverlay
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(30)
            }
        }
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity)
        .clipShape(ExpandedIslandContainer())
        .clipped()
        .onAppear {
            if availableTabs.contains(selectedAgent) == false {
                store.selectAgent(.all)
            }
            onHeatmapRangeChange(heatmapRange, selectedAgent)
        }
        .onChange(of: heatmapRange) { _, newValue in
            onHeatmapRangeChange(newValue, selectedAgent)
        }
        .onChange(of: selectedAgent) { _, newValue in
            onHeatmapRangeChange(heatmapRange, newValue)
        }
        .onReceive(settingsStore.$panelPresentationSequence.dropFirst()) { _ in
            heatmapRange = settingsStore.settings.defaultHeatmapRange
            isSettingsPresented = false
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
            HStack(alignment: .top, spacing: 18) {
                statusBlock(for: snapshot)
                    .frame(width: 220)

                VerticalSectionDivider()
                    .frame(height: 150)

                todayBlock(for: snapshot)
                    .frame(maxWidth: .infinity)
            }

            HorizontalSectionDivider()

            yearHeatmapArea(days: heatmapDays(for: agent), title: "\(agent.displayName) 活跃趋势")
        }
    }

    private func petColumn(progress: PetProgress, xpBreakdown: [AgentXPBreakdown]) -> some View {
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.stage.displayName)
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

                Text("Lv.\(progress.level)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
            }

            HStack(spacing: 14) {
                PetAvatarView(progress: progress)
                    .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(progress.currentXP)/\(progress.nextLevelXP)（今日经验：\(progress.todayXP)）")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    ProgressView(value: Double(progress.currentXP), total: Double(max(1, progress.nextLevelXP)))
                        .tint(Color(hex: progress.stage.accentHex))
                        .scaleEffect(x: 1, y: 0.8, anchor: .center)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("XP 来源")
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
            summaryMetricRow(label: "总 Token", value: compactCount(store.multiAgentSnapshot.todaySummary.totalTokenUsage), valueColor: .white)
        }
    }

    private func statusBlock(for snapshot: AgentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("配额 / 状态")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.42))

            usageRow(
                label: snapshot.status.primaryLabel,
                value: snapshot.status.primaryValue,
                remainingPercent: snapshot.status.primaryProgress.map { $0 * 100 },
                resetHint: nil
            )

            if let secondaryLabel = snapshot.status.secondaryLabel,
               let secondaryValue = snapshot.status.secondaryValue {
                usageRow(
                    label: secondaryLabel,
                    value: secondaryValue,
                    remainingPercent: snapshot.status.secondaryProgress.map { $0 * 100 },
                    resetHint: nil
                )
            }
        }
    }

    private func todayBlock(for snapshot: AgentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.42))

            ForEach(todayRows(for: snapshot)) { row in
                metricRowView(row)
            }
        }
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

    private func usageRow(label: String, value: String, remainingPercent: Double?, resetHint: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.46))

                    if let resetHint {
                        Text(resetHint)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.34))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer()

                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            ProgressView(
                value: UsageLimitProgressStyle.progressValue(for: remainingPercent),
                total: 1
            )
            .tint(Color(hex: UsageLimitProgressStyle.tintHex(for: remainingPercent)))
            .scaleEffect(x: 1, y: 0.72, anchor: .center)
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

    private func todayRows(for snapshot: AgentSnapshot) -> [MetricRow] {
        switch snapshot.agent {
        case .codex:
            [
                MetricRow(label: "对话数", value: "\(snapshot.today.dialogs)", valueColor: .white),
                MetricRow(label: "活跃时长", value: DurationFormatter.string(for: snapshot.today.activeMinutes), valueColor: .white),
                MetricRow(label: "净变更", value: UsageDisplayFormatter.netChangeLabel(for: snapshot.today.netLines), valueColor: .white),
            ]
        case .claude:
            [
                MetricRow(label: "今日会话", value: "\(snapshot.today.dialogs)", valueColor: .white),
                MetricRow(label: "活跃时长", value: DurationFormatter.string(for: snapshot.today.activeMinutes), valueColor: .white),
                MetricRow(label: "今日 Token", value: compactCount(snapshot.today.tokenUsage), valueColor: .white),
            ]
        case .gemini:
            [
                MetricRow(label: "今日会话", value: "\(snapshot.today.dialogs)", valueColor: .white),
                MetricRow(label: "今日 Token", value: compactCount(snapshot.today.tokenUsage), valueColor: .white),
                MetricRow(label: "工具调用", value: "\(snapshot.today.toolCalls)", valueColor: .white),
            ]
        case .all:
            [
                MetricRow(label: "总会话数", value: "\(store.multiAgentSnapshot.todaySummary.totalSessions)", valueColor: .white),
                MetricRow(label: "总活跃时长", value: DurationFormatter.string(for: store.multiAgentSnapshot.todaySummary.totalActiveMinutes), valueColor: .white),
                MetricRow(label: "总 Token", value: compactCount(store.multiAgentSnapshot.todaySummary.totalTokenUsage), valueColor: .white),
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

    private func compactCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
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
        if let _ = snapshot.status.secondaryLabel,
           let secondaryValue = snapshot.status.secondaryValue,
           agent == .codex {
            return "\(snapshot.status.primaryValue) / \(secondaryValue)"
        }
        return "\(snapshot.status.primaryLabel) \(snapshot.status.primaryValue)"
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

enum UsageDisplayFormatter {
    static func netChangeLabel(for netLines: Int) -> String {
        if netLines > 0 {
            return "+\(netLines)"
        }
        return "\(netLines)"
    }

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

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: progress.stage.accentHex).opacity(0.95),
                            Color(hex: "#0A1320"),
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 40
                    )
                )
                .frame(width: 58, height: 58)

            if progress.stage == .cursorEgg {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.92))
                    .frame(width: 26, height: 34)
            } else {
                CatFace(stage: progress.stage)
                    .frame(width: 46, height: 46)
            }
        }
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

struct CatFace: View {
    let stage: PetStage

    var body: some View {
        ZStack {
            Color.clear
            ear(offsetX: -10)
            ear(offsetX: 10)
            Circle()
                .fill(.white.opacity(0.94))
                .frame(width: 34, height: 30)
                .offset(y: 6)
            HStack(spacing: 9) {
                Circle().fill(.black.opacity(0.78)).frame(width: 4, height: 4)
                Circle().fill(.black.opacity(0.78)).frame(width: 4, height: 4)
            }
            .offset(y: 4)

            RoundedRectangle(cornerRadius: 3)
                .fill(.pink.opacity(0.84))
                .frame(width: 7, height: 4)
                .offset(y: 10)

            accessory
        }
    }

    private func ear(offsetX: CGFloat) -> some View {
        Triangle()
            .fill(.white.opacity(0.94))
            .frame(width: 10, height: 10)
            .offset(x: offsetX, y: -5)
    }

    @ViewBuilder
    private var accessory: some View {
        switch stage {
        case .pixelKitten:
            Image(systemName: "sparkles")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color(hex: "#75E59A"))
                .offset(x: 12, y: -10)
        case .terminalCat:
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "#0E2233"))
                .frame(width: 16, height: 10)
                .overlay {
                    Text(">")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#75E59A"))
                }
                .offset(y: -7)
        case .mechPatchCat:
            Image(systemName: "gearshape.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(hex: "#FF8B6A"))
                .offset(x: 12, y: -10)
        case .notchGuardian:
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(hex: "#A4A7FF"))
                .offset(x: 12, y: -10)
        case .cursorEgg:
            EmptyView()
        }
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
