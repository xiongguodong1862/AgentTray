import Charts
import SwiftUI

enum AgentAnalyticsLayout {
    static func preferredPanelHeight(
        agent: AgentKind,
        tab: AgentAnalyticsTab,
        analyticsRange: AnalyticsRange,
        activityRange: HeatmapRange
    ) -> CGFloat {
        guard tab == .activity else {
            return compactPanelHeight(agent: agent, tab: tab)
        }

        switch agent {
        case .codex:
            return 728
        case .claude:
            return 688
        case .gemini:
            return 736
        case .all:
            if tab == .activity {
                let activityHeight = ScreenLayout.panelHeight(for: activityRange, agent: agent)
                return max(activityHeight + 64, activityHeight)
            }
            let base: CGFloat = analyticsRange == .month ? 688 : 676
            return base
        }
    }

    static func compactPanelHeight(agent: AgentKind, tab: AgentAnalyticsTab) -> CGFloat {
        switch (agent, tab) {
        case (.claude, .tokens):
            return 610
        case (.claude, _):
            return 548
        case (.codex, .tokens), (.codex, .changes):
            return 618
        case (.codex, .limits):
            return 522
        case (.codex, _):
            return 560
        case (.gemini, .tokens), (.gemini, .models), (.gemini, .projects):
            return 618
        case (.gemini, _):
            return 560
        case (.all, _):
            return analyticsFallbackHeight
        }
    }

    private static let analyticsFallbackHeight: CGFloat = 676
}

struct AgentAnalyticsSectionView: View {
    let agent: AgentKind
    let snapshot: AgentSnapshot
    let heatmapColorPreset: HeatmapColorPreset
    @Binding var selectedTab: AgentAnalyticsTab
    @Binding var selectedRange: AnalyticsRange
    @Binding var activityRange: HeatmapRange

    private var analytics: AgentAnalyticsSnapshot {
        snapshot.analytics ?? .empty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                AgentAnalyticsTabBar(agent: agent, selectedTab: $selectedTab)
                Spacer(minLength: 12)
                if selectedTab == .activity {
                    ActivityHeatmapRangeMenu(selectedRange: $activityRange)
                } else {
                    AnalyticsRangeSwitcher(selectedRange: $selectedRange)
                }
            }

            Group {
                switch selectedTab {
                case .activity:
                    ActivityTrendPageView(
                        agent: agent,
                        snapshot: snapshot,
                        colorPreset: heatmapColorPreset,
                        range: activityRange
                    )
                case .sessions:
                    SessionTrendPageView(analytics: analytics, range: selectedRange)
                case .tokens:
                    TokenTrendPageView(agent: agent, analytics: analytics, range: selectedRange)
                case .tools:
                    ToolRankingPageView(agent: agent, analytics: analytics, range: selectedRange)
                case .changes:
                    CodeChangeTrendPageView(analytics: analytics, range: selectedRange)
                case .limits:
                    LimitTrendPageView(analytics: analytics, range: selectedRange)
                case .models:
                    ModelDistributionPageView(analytics: analytics, range: selectedRange)
                case .projects:
                    ProjectTokenTrendPageView(analytics: analytics, range: selectedRange)
                }
            }
        }
    }
}

struct AgentAnalyticsTabBar: View {
    let agent: AgentKind
    @Binding var selectedTab: AgentAnalyticsTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AgentAnalyticsTab.tabs(for: agent)) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.66))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(selectedTab == tab ? .white.opacity(0.14) : .white.opacity(0.06))
                        )
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(selectedTab == tab ? 0.16 : 0.06), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AnalyticsRangeSwitcher: View {
    @Binding var selectedRange: AnalyticsRange

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AnalyticsRange.allCases) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedRange == range ? .white : .white.opacity(0.62))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(selectedRange == range ? .white.opacity(0.14) : .white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ActivityHeatmapRangeMenu: View {
    @Binding var selectedRange: HeatmapRange

    var body: some View {
        Picker("活跃范围", selection: $selectedRange) {
            ForEach([HeatmapRange.week, .month, .year]) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(.white.opacity(0.82))
    }
}

struct AnalyticsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
    }
}

struct AnalyticsSummaryStrip: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.0)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.44))
                    Text(item.1)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.04))
                )
            }
        }
    }
}

struct AnalyticsMetricList: View {
    let items: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.0)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.44))
                    Spacer()
                    Text(item.1)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.04))
        )
    }
}

struct AnalyticsLegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
        }
    }
}

struct AnalyticsLegendRow: View {
    let items: [(Color, String)]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                AnalyticsLegendItem(color: item.0, title: item.1)
            }
            Spacer()
        }
    }
}

struct AnalyticsChartTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 180, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }
}

enum AnalyticsBucketLabelStyle {
    case timeOfDay
    case date
    case dateWithWeekday
}

struct DistributionDonutChartView: View {
    let items: [NamedCountItem]
    private let chartSize: CGFloat = 156

    var body: some View {
        if items.isEmpty {
            AnalyticsEmptyStateCard(title: "暂无分布数据", description: "当前范围内还没有可展示的分布结果。")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                AnalyticsLegendRow(items: items.prefix(4).map { (AnalyticsChartPalette.color(for: $0.name), "\($0.name) \(Int($0.ratio * 100))%") })
                Chart(items) { item in
                    SectorMark(
                        angle: .value("Count", item.count),
                        innerRadius: .ratio(0.74),
                        angularInset: 2
                    )
                    .foregroundStyle(AnalyticsChartPalette.color(for: item.name))
                }
                .frame(width: chartSize, height: chartSize)
                .frame(maxWidth: .infinity)
                .clipped()
            }
        }
    }
}

struct TimeBarChartView: View {
    let series: [CountSeriesPoint]
    let valueLabel: String
    let color: Color
    var valueFormatter: (Int) -> String = { "\($0)" }
    @State private var hoveredPoint: CountSeriesPoint?
    private var bucketLabelStyle: AnalyticsBucketLabelStyle {
        AnalyticsDateFormatter.labelStyle(for: series.map(\.bucketStart))
    }

    var body: some View {
        if series.allSatisfy({ $0.value == 0 }) {
            AnalyticsEmptyStateCard(title: "暂无趋势数据", description: "当前范围内还没有可展示的趋势变化。")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                AnalyticsLegendRow(items: [(color, valueLabel)])
                Chart(series) { point in
                    BarMark(
                        x: .value("Time", point.bucketStart),
                        y: .value(valueLabel, point.value)
                    )
                    .foregroundStyle(color)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(series.count, 6)))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    hoveredPoint = nearestPoint(at: location, proxy: proxy, geometry: geometry)
                                case .ended:
                                    hoveredPoint = nil
                                }
                            }

                        if let hoveredPoint,
                           let positionX = proxy.position(forX: hoveredPoint.bucketStart),
                           let positionY = proxy.position(forY: hoveredPoint.value) {
                            AnalyticsChartTooltip(text: "\(AnalyticsDateFormatter.bucketLabel(for: hoveredPoint.bucketStart, style: bucketLabelStyle))\n\(valueLabel) \(valueFormatter(hoveredPoint.value))")
                                .position(x: min(max(positionX, 92), geometry.size.width - 92), y: max(positionY - 26, 20))
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: 210)
            }
        }
    }

    private func nearestPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> CountSeriesPoint? {
        let frame = geometry[proxy.plotAreaFrame]
        let relativeX = location.x - frame.origin.x
        guard relativeX >= 0, relativeX <= frame.width else { return nil }
        let candidates = series.compactMap { point -> (CountSeriesPoint, CGFloat)? in
            guard let x = proxy.position(forX: point.bucketStart) else { return nil }
            return (point, abs(x - relativeX))
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }
}

struct ComboTrendChartView: View {
    let bars: [CountSeriesPoint]
    let line: [CountSeriesPoint]
    let barLabel: String
    let lineLabel: String
    let barColor: Color
    let lineColor: Color
    var valueFormatter: (Int) -> String = { "\($0)" }
    @State private var hoveredPoint: CountSeriesPoint?
    private var bucketLabelStyle: AnalyticsBucketLabelStyle {
        AnalyticsDateFormatter.labelStyle(for: bars.map(\.bucketStart))
    }

    var body: some View {
        if bars.allSatisfy({ $0.value == 0 }) && line.allSatisfy({ $0.value == 0 }) {
            AnalyticsEmptyStateCard(title: "暂无组合趋势", description: "当前范围内还没有可展示的图表数据。")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                AnalyticsLegendRow(items: [(barColor, barLabel), (lineColor, lineLabel)])
                Chart {
                    ForEach(bars) { point in
                        BarMark(
                            x: .value("Time", point.bucketStart),
                            y: .value(barLabel, point.value)
                        )
                        .foregroundStyle(barColor)
                        .cornerRadius(4)
                    }
                    ForEach(line) { point in
                        LineMark(
                            x: .value("Time", point.bucketStart),
                            y: .value(lineLabel, point.value),
                            series: .value("Series", lineLabel)
                        )
                        .foregroundStyle(lineColor)
                        .lineStyle(.init(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("Time", point.bucketStart),
                            y: .value(lineLabel, point.value)
                        )
                        .foregroundStyle(lineColor)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(bars.count, 6)))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    hoveredPoint = nearestPoint(at: location, proxy: proxy, geometry: geometry)
                                case .ended:
                                    hoveredPoint = nil
                                }
                            }

                        if let hoveredPoint,
                           let x = proxy.position(forX: hoveredPoint.bucketStart),
                           let y = proxy.position(forY: hoveredPoint.value) {
                            let cumulative = line.first(where: { $0.bucketStart == hoveredPoint.bucketStart })?.value ?? 0
                            AnalyticsChartTooltip(
                                text: "\(AnalyticsDateFormatter.bucketLabel(for: hoveredPoint.bucketStart, style: bucketLabelStyle))\n\(barLabel) \(valueFormatter(hoveredPoint.value))\n\(lineLabel) \(valueFormatter(cumulative))"
                            )
                            .position(x: min(max(x, 92), geometry.size.width - 92), y: max(y - 26, 20))
                            .allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private func nearestPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> CountSeriesPoint? {
        let frame = geometry[proxy.plotAreaFrame]
        let relativeX = location.x - frame.origin.x
        guard relativeX >= 0, relativeX <= frame.width else { return nil }
        let candidates = bars.compactMap { point -> (CountSeriesPoint, CGFloat)? in
            guard let x = proxy.position(forX: point.bucketStart) else { return nil }
            return (point, abs(x - relativeX))
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }
}

struct VerticalRankingChartView: View {
    let items: [NamedCountItem]
    let valueLabel: String
    let color: Color
    @State private var hoveredItem: NamedCountItem?

    var body: some View {
        if items.isEmpty {
            AnalyticsEmptyStateCard(title: "暂无工具排行", description: "当前范围内还没有工具调用记录。")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                AnalyticsLegendRow(items: [(color, valueLabel)])
                Chart(items) { item in
                    BarMark(
                        x: .value("Name", item.name),
                        y: .value(valueLabel, item.count),
                        width: .fixed(12)
                    )
                    .foregroundStyle(color)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: items.map(\.name)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    hoveredItem = nearestItem(at: location, proxy: proxy, geometry: geometry)
                                case .ended:
                                    hoveredItem = nil
                                }
                            }

                        if let hoveredItem,
                           let x = proxy.position(forX: hoveredItem.name),
                           let y = proxy.position(forY: hoveredItem.count) {
                            AnalyticsChartTooltip(text: "\(hoveredItem.name)\n\(valueLabel) \(hoveredItem.count)\n占比 \(Int(hoveredItem.ratio * 100))%")
                                .position(x: min(max(x, 92), geometry.size.width - 92), y: max(y - 26, 20))
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private func nearestItem(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> NamedCountItem? {
        let frame = geometry[proxy.plotAreaFrame]
        let relativeX = location.x - frame.origin.x
        guard relativeX >= 0, relativeX <= frame.width else { return nil }
        let candidates = items.compactMap { item -> (NamedCountItem, CGFloat)? in
            guard let x = proxy.position(forX: item.name) else { return nil }
            return (item, abs(x - relativeX))
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }
}

struct DualLineChartView: View {
    let primary: [TimedPercentPoint]
    let secondary: [TimedPercentPoint]
    let primaryLabel: String
    let secondaryLabel: String
    let primaryColor: Color
    let secondaryColor: Color
    @State private var hoveredPoint: TimedPercentPoint?

    var body: some View {
        if primary.isEmpty && secondary.isEmpty {
            AnalyticsEmptyStateCard(title: "暂无配额采样", description: "当前范围内还没有配额曲线数据。")
        } else {
            let primarySorted = primary.sorted { $0.timestamp < $1.timestamp }
            let secondarySorted = secondary.sorted { $0.timestamp < $1.timestamp }

            VStack(alignment: .leading, spacing: 8) {
                AnalyticsLegendRow(items: [(primaryColor, primaryLabel), (secondaryColor, secondaryLabel)])
                Chart {
                    ForEach(primarySorted) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value(primaryLabel, point.percent),
                            series: .value("Series", primaryLabel)
                        )
                        .foregroundStyle(primaryColor)
                        .lineStyle(.init(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                    ForEach(secondarySorted) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value(secondaryLabel, point.percent),
                            series: .value("Series", secondaryLabel)
                        )
                        .foregroundStyle(secondaryColor)
                        .lineStyle(.init(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    hoveredPoint = nearestPoint(at: location, proxy: proxy, geometry: geometry, points: primarySorted + secondarySorted)
                                case .ended:
                                    hoveredPoint = nil
                                }
                            }

                        if let hoveredPoint,
                           let x = proxy.position(forX: hoveredPoint.timestamp),
                           let y = proxy.position(forY: hoveredPoint.percent) {
                            let primaryValue = primarySorted.first(where: { $0.timestamp == hoveredPoint.timestamp })?.percent
                            let secondaryValue = secondarySorted.first(where: { $0.timestamp == hoveredPoint.timestamp })?.percent
                            AnalyticsChartTooltip(
                                text: "\(AnalyticsDateFormatter.preciseLabel(for: hoveredPoint.timestamp))\n\(primaryLabel) \(percentLabel(primaryValue))\n\(secondaryLabel) \(percentLabel(secondaryValue))"
                            )
                            .position(x: min(max(x, 92), geometry.size.width - 92), y: max(y - 26, 20))
                            .allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private func nearestPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, points: [TimedPercentPoint]) -> TimedPercentPoint? {
        let frame = geometry[proxy.plotAreaFrame]
        let relativeX = location.x - frame.origin.x
        guard relativeX >= 0, relativeX <= frame.width else { return nil }
        let candidates = points.compactMap { point -> (TimedPercentPoint, CGFloat)? in
            guard let x = proxy.position(forX: point.timestamp) else { return nil }
            return (point, abs(x - relativeX))
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    private func percentLabel(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }
}

struct ActivityTrendPageView: View {
    let agent: AgentKind
    let snapshot: AgentSnapshot
    let colorPreset: HeatmapColorPreset
    let range: HeatmapRange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCard(title: "\(agent.displayName) 活跃趋势", subtitle: range.title) {
                VStack(alignment: .leading, spacing: 14) {
                    heatmapContent
                    HeatmapLegend(colorPreset: colorPreset)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            AnalyticsSummaryStrip(items: [
                ("今日活跃时长", DurationFormatter.string(for: snapshot.today.activeMinutes)),
                ("本周活跃天数", "\(snapshot.lastSevenDays.filter { $0.activityScore > 0 }.count)"),
                ("本月活跃天数", "\(Array(snapshot.lastYearDays.suffix(30)).filter { $0.activityScore > 0 }.count)")
            ])
        }
    }

    @ViewBuilder
    private var heatmapContent: some View {
        switch range {
        case .year:
            YearContributionHeatmap(days: snapshot.lastYearDays, colorPreset: colorPreset)
        case .month:
            MonthCalendarHeatmap(days: Array(snapshot.lastYearDays.suffix(30)), colorPreset: colorPreset)
        case .week:
            WeekStripHeatmap(days: snapshot.lastSevenDays, colorPreset: colorPreset)
        }
    }
}

struct SessionTrendPageView: View {
    let analytics: AgentAnalyticsSnapshot
    let range: AnalyticsRange

    var body: some View {
        let stats = analytics.sessionStats(for: range)
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCard(title: "会话数", subtitle: range.title) {
                TimeBarChartView(
                    series: stats.series,
                    valueLabel: "会话数",
                    color: Color(hex: "#79D0FF")
                )
            }

            AnalyticsSummaryStrip(items: [
                ("会话总数", "\(stats.totalSessions)"),
                ("平均每次会话轮数", AnalyticsTextFormatter.decimal(stats.averageTurnsPerSession)),
                ("活跃天数", "\(stats.activeDays)")
            ])
        }
    }
}

struct TokenTrendPageView: View {
    let agent: AgentKind
    let analytics: AgentAnalyticsSnapshot
    let range: AnalyticsRange

    var body: some View {
        let stats = analytics.tokenStats(for: range)
        let donutItems = tokenDistributionItems(stats: stats)
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCard(title: "Token 趋势", subtitle: range.title) {
                ComboTrendChartView(
                    bars: stats.series,
                    line: stats.cumulativeSeries,
                    barLabel: "时段 Token 用量",
                    lineLabel: "累计 Token 用量",
                    barColor: Color(hex: "#7DE6AA"),
                    lineColor: Color(hex: "#FFD36E"),
                    valueFormatter: UsageNumberFormatter.tokenCompactCount
                )
            }

            HStack(alignment: .top, spacing: 12) {
                AnalyticsCard(title: "Token 分布") {
                    DistributionDonutChartView(items: donutItems)
                }
                .frame(maxWidth: .infinity)

                AnalyticsCard(title: "辅助信息") {
                    AnalyticsMetricList(items: [
                        ("总 Token", UsageNumberFormatter.tokenCompactCount(stats.totalTokens)),
                        ("平均每会话 Token", UsageNumberFormatter.tokenCompactCount(Int(stats.averageTokensPerSession.rounded()))),
                        (agent == .gemini ? "输入/输出占比" : "输入/输出/推理占比", tokenRatioText(stats: stats))
                    ])
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func tokenDistributionItems(stats: TokenStatsSnapshot) -> [NamedCountItem] {
        var items: [NamedCountItem] = []
        let total = max(1, stats.inputTokens + stats.outputTokens + stats.reasoningTokens)
        if stats.inputTokens > 0 {
            items.append(NamedCountItem(name: "输入", count: stats.inputTokens, ratio: Double(stats.inputTokens) / Double(total)))
        }
        if stats.outputTokens > 0 {
            items.append(NamedCountItem(name: "输出", count: stats.outputTokens, ratio: Double(stats.outputTokens) / Double(total)))
        }
        if stats.reasoningTokens > 0 {
            items.append(NamedCountItem(name: "推理", count: stats.reasoningTokens, ratio: Double(stats.reasoningTokens) / Double(total)))
        }
        return items
    }

    private func tokenRatioText(stats: TokenStatsSnapshot) -> String {
        let total = max(1, stats.inputTokens + stats.outputTokens + stats.reasoningTokens)
        let parts = [
            stats.inputTokens > 0 ? "入 \(Int((Double(stats.inputTokens) / Double(total)) * 100))%" : nil,
            stats.outputTokens > 0 ? "出 \(Int((Double(stats.outputTokens) / Double(total)) * 100))%" : nil,
            stats.reasoningTokens > 0 ? "推 \(Int((Double(stats.reasoningTokens) / Double(total)) * 100))%" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "--" : parts.joined(separator: " / ")
    }
}

struct ToolRankingPageView: View {
    let agent: AgentKind
    let analytics: AgentAnalyticsSnapshot
    let range: AnalyticsRange

    var body: some View {
        let stats = analytics.toolStats(for: range) ?? .empty
        let searchTotal = max(1, stats.searchSessionCount + stats.nonSearchSessionCount)
        let donutItems = [
            NamedCountItem(name: "搜索任务", count: stats.searchSessionCount, ratio: Double(stats.searchSessionCount) / Double(searchTotal)),
            NamedCountItem(name: "非搜索任务", count: stats.nonSearchSessionCount, ratio: Double(stats.nonSearchSessionCount) / Double(searchTotal))
        ].filter { $0.count > 0 }

        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCard(title: "高频工具 Top 6", subtitle: range.title) {
                VerticalRankingChartView(
                    items: stats.topTools,
                    valueLabel: "调用次数",
                    color: Color(hex: agent == .claude ? "#8AB5FF" : "#79D0FF")
                )
            }

            HStack(alignment: .top, spacing: 12) {
                AnalyticsCard(title: "搜索占比") {
                    DistributionDonutChartView(items: donutItems)
                }
                .frame(maxWidth: .infinity)

                AnalyticsCard(title: "辅助信息") {
                    AnalyticsMetricList(items: [
                        ("工具调用总次数", "\(stats.totalToolCalls)"),
                        ("工具种类数", "\(stats.distinctToolCount)"),
                        ("搜索任务占比", searchRatioText(stats: stats))
                    ])
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func searchRatioText(stats: ToolStatsSnapshot) -> String {
        let total = stats.searchSessionCount + stats.nonSearchSessionCount
        guard total > 0 else { return "--" }
        return "\(Int((Double(stats.searchSessionCount) / Double(total)) * 100))%"
    }
}

struct CodeChangeTrendPageView: View {
    let analytics: AgentAnalyticsSnapshot
    let range: AnalyticsRange
    @State private var hoveredPoint: CountSeriesPoint?

    var body: some View {
        let stats = analytics.changeStats(for: range) ?? .empty
        let bucketLabelStyle = AnalyticsDateFormatter.labelStyle(for: stats.addedSeries.map(\.bucketStart))
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCard(title: "代码变更", subtitle: range.title) {
                VStack(alignment: .leading, spacing: 8) {
                    AnalyticsLegendRow(items: [
                        (Color(hex: "#7DE6AA"), "新增代码行"),
                        (Color(hex: "#FF9A8A"), "删除代码行"),
                        (Color(hex: "#7AD6FF"), "净增代码行")
                    ])
                    Chart {
                        ForEach(stats.addedSeries) { point in
                            BarMark(x: .value("Time", point.bucketStart), y: .value("新增", point.value))
                                .foregroundStyle(Color(hex: "#7DE6AA"))
                        }
                        ForEach(stats.deletedSeries) { point in
                            BarMark(x: .value("Time", point.bucketStart), y: .value("删除", point.value))
                                .foregroundStyle(Color(hex: "#FF9A8A"))
                        }
                        ForEach(stats.netSeries) { point in
                            LineMark(
                                x: .value("Time", point.bucketStart),
                                y: .value("净增", point.value),
                                series: .value("Series", "净增")
                            )
                                .foregroundStyle(Color(hex: "#7AD6FF"))
                                .lineStyle(.init(lineWidth: 2))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        hoveredPoint = nearestPoint(at: location, proxy: proxy, geometry: geometry, points: stats.addedSeries)
                                    case .ended:
                                        hoveredPoint = nil
                                    }
                                }

                            if let hoveredPoint,
                               let x = proxy.position(forX: hoveredPoint.bucketStart),
                               let y = proxy.position(forY: hoveredPoint.value) {
                                let deleted = stats.deletedSeries.first(where: { $0.bucketStart == hoveredPoint.bucketStart })?.value ?? 0
                                let net = stats.netSeries.first(where: { $0.bucketStart == hoveredPoint.bucketStart })?.value ?? 0
                                AnalyticsChartTooltip(
                                    text: "\(AnalyticsDateFormatter.bucketLabel(for: hoveredPoint.bucketStart, style: bucketLabelStyle))\n新增 \(hoveredPoint.value)\n删除 \(deleted)\n净增 \(net)"
                                )
                                .position(x: min(max(x, 92), geometry.size.width - 92), y: max(y - 26, 20))
                                .allowsHitTesting(false)
                            }
                        }
                    }
                    .frame(height: 220)
                }
            }

            AnalyticsSummaryStrip(items: [
                ("新增总行数", "\(stats.totalAddedLines)"),
                ("删除总行数", "\(stats.totalDeletedLines)"),
                ("净增总行数", "\(stats.totalNetLines)"),
                ("改动文件数", "\(stats.modifiedFiles)")
            ])
        }
    }

    private func nearestPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, points: [CountSeriesPoint]) -> CountSeriesPoint? {
        let frame = geometry[proxy.plotAreaFrame]
        let relativeX = location.x - frame.origin.x
        guard relativeX >= 0, relativeX <= frame.width else { return nil }
        let candidates = points.compactMap { point -> (CountSeriesPoint, CGFloat)? in
            guard let x = proxy.position(forX: point.bucketStart) else { return nil }
            return (point, abs(x - relativeX))
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }
}

struct LimitTrendPageView: View {
    let analytics: AgentAnalyticsSnapshot
    let range: AnalyticsRange

    var body: some View {
        let stats = analytics.limitStats(for: range) ?? .empty
        let primaryRemaining = stats.primarySeries.map {
            TimedPercentPoint(timestamp: $0.timestamp, percent: max(0, 100 - $0.percent))
        }
        let secondaryRemaining = stats.secondarySeries.map {
            TimedPercentPoint(timestamp: $0.timestamp, percent: max(0, 100 - $0.percent))
        }
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCard(title: "配额曲线", subtitle: range.title) {
                DualLineChartView(
                    primary: primaryRemaining,
                    secondary: secondaryRemaining,
                    primaryLabel: "5 小时窗口剩余",
                    secondaryLabel: "周窗口剩余",
                    primaryColor: Color(hex: "#FFB86B"),
                    secondaryColor: Color(hex: "#7AD6FF")
                )
            }
        }
    }
}

struct ModelDistributionPageView: View {
    let analytics: AgentAnalyticsSnapshot
    let range: AnalyticsRange

    var body: some View {
        let stats = analytics.modelStats(for: range) ?? .empty
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCard(title: "模型使用分布", subtitle: range.title) {
                DistributionDonutChartView(items: stats.modelUsageItems)
            }

            AnalyticsCard(title: "辅助信息") {
                AnalyticsSummaryStrip(items: [
                    ("主用模型", stats.dominantModelName ?? "--"),
                    ("模型种类数", "\(stats.modelUsageItems.count)"),
                    ("平均 Token 消耗", modelAverageText(stats.modelAverageTokenItems))
                ])
            }
        }
    }

    private func modelAverageText(_ items: [NamedAverageItem]) -> String {
        guard let first = items.first else { return "--" }
        return "\(first.name) \(UsageNumberFormatter.compactCount(Int(first.averageValue.rounded())))"
    }
}

struct ProjectTokenTrendPageView: View {
    let analytics: AgentAnalyticsSnapshot
    let range: AnalyticsRange
    @State private var hoveredBucket: Date?

    var body: some View {
        let stats = analytics.projectStats(for: range) ?? .empty
        let bucketLabelStyle = AnalyticsDateFormatter.labelStyle(for: stats.topProjects.first?.points.map(\.bucketStart) ?? [])
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCard(title: "项目 Token 趋势", subtitle: range.title) {
                if stats.topProjects.isEmpty {
                    AnalyticsEmptyStateCard(title: "暂无项目趋势", description: "当前范围内还没有项目级 Token 数据。")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        AnalyticsLegendRow(items: stats.topProjects.prefix(3).map { (AnalyticsChartPalette.color(for: $0.projectName), $0.projectName) })
                        Chart {
                            ForEach(stats.topProjects) { project in
                                ForEach(project.points) { point in
                                    LineMark(
                                        x: .value("Time", point.bucketStart),
                                        y: .value(project.projectName, point.value),
                                        series: .value("Series", project.projectName)
                                    )
                                    .foregroundStyle(AnalyticsChartPalette.color(for: project.projectName))
                                    .lineStyle(.init(lineWidth: 2))
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(.clear)
                                    .contentShape(Rectangle())
                                    .onContinuousHover { phase in
                                        switch phase {
                                        case .active(let location):
                                            hoveredBucket = nearestBucket(at: location, proxy: proxy, geometry: geometry, stats: stats)
                                        case .ended:
                                            hoveredBucket = nil
                                        }
                                    }

                                if let hoveredBucket,
                                   let x = proxy.position(forX: hoveredBucket) {
                                    let summary = stats.topProjects.map { project in
                                        let value = project.points.first(where: { $0.bucketStart == hoveredBucket })?.value ?? 0
                                        return "\(project.projectName) \(UsageNumberFormatter.tokenCompactCount(value))"
                                    }
                                    AnalyticsChartTooltip(
                                        text: ([AnalyticsDateFormatter.bucketLabel(for: hoveredBucket, style: bucketLabelStyle)] + summary).joined(separator: "\n")
                                    )
                                    .position(x: min(max(x, 92), geometry.size.width - 92), y: 26)
                                    .allowsHitTesting(false)
                                }
                            }
                        }
                        .frame(height: 240)
                    }
                }
            }

            AnalyticsSummaryStrip(items: [
                ("项目数", "\(stats.projectCount)"),
                ("Token 最高项目", stats.highestTokenProjectName ?? "--"),
                ("最高项目 Token", UsageNumberFormatter.tokenCompactCount(stats.highestTokenProjectValue))
            ])
        }
    }

    private func nearestBucket(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, stats: ProjectStatsSnapshot) -> Date? {
        let points = stats.topProjects.first?.points ?? []
        let frame = geometry[proxy.plotAreaFrame]
        let relativeX = location.x - frame.origin.x
        guard relativeX >= 0, relativeX <= frame.width else { return nil }
        let candidates = points.compactMap { point -> (Date, CGFloat)? in
            guard let x = proxy.position(forX: point.bucketStart) else { return nil }
            return (point.bucketStart, abs(x - relativeX))
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }
}

struct AnalyticsEmptyStateCard: View {
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
            Text(description)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.03))
        )
    }
}

enum AnalyticsTextFormatter {
    static func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        return String(format: value.rounded(.towardZero) == value ? "%.0f" : "%.1f", value)
    }
}

enum AnalyticsDateFormatter {
    static func bucketLabel(for date: Date, style: AnalyticsBucketLabelStyle) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = switch style {
        case .timeOfDay:
            "HH:mm"
        case .date:
            "M/d"
        case .dateWithWeekday:
            "M/d EEE"
        }
        return formatter.string(from: date)
    }

    static func labelStyle(for dates: [Date]) -> AnalyticsBucketLabelStyle {
        let sorted = dates.sorted()
        guard sorted.count >= 2 else {
            return fallbackLabelStyle(for: sorted.first)
        }

        let intervals = zip(sorted, sorted.dropFirst()).map { $1.timeIntervalSince($0) }
        let hasDailyStep = intervals.allSatisfy { $0 >= 12 * 60 * 60 }
        if hasDailyStep {
            return sorted.count <= 7 ? .dateWithWeekday : .date
        }
        return .timeOfDay
    }

    private static func fallbackLabelStyle(for date: Date?) -> AnalyticsBucketLabelStyle {
        guard let date else { return .date }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let isStartOfDay = (components.hour ?? 0) == 0
            && (components.minute ?? 0) == 0
            && (components.second ?? 0) == 0
        return isStartOfDay ? .dateWithWeekday : .timeOfDay
    }

    static func preciseLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

enum AnalyticsChartPalette {
    static func color(for key: String) -> Color {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "输入":
            return Color(hex: "#79D0FF")
        case "输出":
            return Color(hex: "#7DE6AA")
        case "推理":
            return Color(hex: "#FFD36E")
        case "搜索任务":
            return Color(hex: "#B79CFF")
        case "非搜索任务":
            return Color(hex: "#7AD6FF")
        default:
            break
        }
        let palette = ["#79D0FF", "#FFD36E", "#7DE6AA", "#FF9A8A", "#B79CFF", "#8AB5FF"]
        let index = abs(normalized.hashValue) % palette.count
        return Color(hex: palette[index])
    }
}
