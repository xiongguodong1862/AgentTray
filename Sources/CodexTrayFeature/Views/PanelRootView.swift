import SwiftUI

struct PanelRootView: View {
    @ObservedObject var store: UsageStore
    let onQuit: () -> Void
    var onHeatmapRangeChange: (HeatmapRange) -> Void
    @State private var heatmapRange: HeatmapRange = .year

    private var islandHeight: CGFloat { ScreenLayout.collapsedIslandSize.height }
    private var panelWidth: CGFloat { ScreenLayout.panelWidth }

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
                    HStack(alignment: .top, spacing: 18) {
                        petColumn
                            .frame(width: 220)

                        VerticalSectionDivider()

                        usageBlock
                            .frame(width: 190)

                        VerticalSectionDivider()

                        todayBlock
                            .frame(maxWidth: .infinity)
                    }

                    HorizontalSectionDivider()

                    yearHeatmapArea

                    HorizontalSectionDivider()

                    footerRow
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity)
        .clipShape(ExpandedIslandContainer())
        .clipped()
        .onAppear {
            onHeatmapRangeChange(heatmapRange)
        }
        .onChange(of: heatmapRange) { _, newValue in
            onHeatmapRangeChange(newValue)
        }
    }

    private var petColumn: some View {
        let pet = store.snapshot.pet
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(pet.stage.displayName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                Text("等级\(pet.level)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
            }

            HStack(spacing: 14) {
                PetAvatarView(progress: pet)
                    .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(pet.currentXP)/\(pet.nextLevelXP)（今日经验：\(pet.todayXP)）")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    ProgressView(value: Double(pet.currentXP), total: Double(max(1, pet.nextLevelXP)))
                        .tint(Color(hex: pet.stage.accentHex))
                        .scaleEffect(x: 1, y: 0.8, anchor: .center)
                }
            }
        }
        .padding(.top, 8)
    }

    private var usageBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            usageRow(
                label: "5小时余量",
                value: store.snapshot.primaryLimit?.shortLabel ?? "--",
                remainingPercent: store.snapshot.primaryLimit?.remainingPercent,
                resetHint: UsageDisplayFormatter.resetHint(for: store.snapshot.primaryLimit?.resetsAt)
            )
            usageRow(
                label: "本周余量",
                value: store.snapshot.secondaryLimit?.shortLabel ?? "--",
                remainingPercent: store.snapshot.secondaryLimit?.remainingPercent,
                resetHint: UsageDisplayFormatter.resetHint(for: store.snapshot.secondaryLimit?.resetsAt)
            )
        }
    }

    private var todayBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.42))

            ForEach(todayRows) { row in
                metricRowView(row)
            }
        }
    }

    private var yearHeatmapArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("活跃趋势")
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

            heatmapContent
                .frame(maxWidth: .infinity, alignment: .leading)

            HeatmapLegend()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, heatmapRange == .month ? 12 : 0)
        }
        .padding(.top, 4)
    }

    private var footerRow: some View {
        HStack(spacing: 12) {
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: "#FF9C8A"))
                    .lineLimit(2)
            }

            Spacer()

            Button("退出", action: onQuit)
                .buttonStyle(ChromeButtonStyle(tint: .white.opacity(0.12)))
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
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.14),
                .init(color: Color(hex: "#071321"), location: 0.38),
                .init(color: Color(hex: "#0b1d31"), location: 0.7),
                .init(color: Color(hex: "#102942"), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var todayRows: [MetricRow] {
        [
            MetricRow(label: "对话数", value: "\(store.snapshot.today.dialogs)", valueColor: .white),
            MetricRow(label: "活跃时长", value: DurationFormatter.string(for: store.snapshot.today.activeMinutes), valueColor: .white),
            MetricRow(label: "净变更", value: UsageDisplayFormatter.netChangeLabel(for: store.snapshot.today.netLines), valueColor: .white),
        ]
    }

    @ViewBuilder
    private var heatmapContent: some View {
        switch heatmapRange {
        case .year:
            YearContributionHeatmap(days: store.snapshot.lastYearDays)
        case .month:
            MonthCalendarHeatmap(days: store.snapshot.lastYearDays)
        case .week:
            WeekStripHeatmap(days: store.snapshot.lastSevenDays)
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
                HStack(spacing: standalone ? 6 : 8) {
                    Text(store.snapshot.primaryLimit.map { "5小时 \($0.shortLabel)" } ?? "5小时 --")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer()

                Text(store.snapshot.secondaryLimit.map { "本周 \($0.shortLabel)" } ?? "本周 --")
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

    init(days: [UsageMetricsDay]) {
        self.days = days
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
                            Text(monthLabel(for: index))
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.34))
                                .frame(height: 12)

                            ForEach(week, id: \.self) { date in
                                let day = lookup[calendar.startOfDay(for: date)] ?? .empty(for: date)
                                GeometryReader { cellGeometry in
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(HeatmapPalette.color(for: day.heatmapLevel))
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
        let date = weeks[index].first ?? startDate
        let day = calendar.component(.day, from: date)
        guard day <= 7 else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter.string(from: date)
    }

    private func tooltipText(for day: UsageMetricsDay) -> String {
        "\(Self.tooltipDateFormatter.string(from: day.date))\n\(day.dialogs) 次对话"
    }
}

struct MonthCalendarHeatmap: View {
    let days: [UsageMetricsDay]
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
        "\(Self.tooltipDateFormatter.string(from: day.date))\n\(day.dialogs) 次对话"
    }
}

struct WeekStripHeatmap: View {
    let days: [UsageMetricsDay]
    @State private var hoveredCell: HoveredHeatmapCell?
    private let calendar: Calendar
    private let sortedDays: [UsageMetricsDay]

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    init(days: [UsageMetricsDay]) {
        self.days = days
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
        "\(Self.tooltipDateFormatter.string(from: day.date))\n\(day.dialogs) 次对话"
    }
}

enum HeatmapRange: String, CaseIterable, Identifiable {
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

}

private struct HoveredHeatmapCell: Equatable {
    let day: UsageMetricsDay
    let frame: CGRect
}

private struct HeatmapCalendarCell: View {
    let day: UsageMetricsDay
    let isCurrentMonth: Bool
    let cornerRadius: CGFloat
    let dayFontSize: CGFloat
    let coordinateSpaceName: String
    let onHoverChanged: (CGRect, Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(HeatmapPalette.color(for: day.heatmapLevel).opacity(isCurrentMonth ? 1 : 0.52))

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

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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

struct HeatmapLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.34))
            ForEach(0..<5, id: \.self) { level in
                Circle()
                    .fill(HeatmapPalette.color(for: level))
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
    static func color(for level: Int) -> Color {
        switch level {
        case 0:
            Color(hex: "#324858")
        case 1:
            Color(hex: "#2f7f6d")
        case 2:
            Color(hex: "#369b7f")
        case 3:
            Color(hex: "#39ad89")
        default:
            Color(hex: "#3cc796")
        }
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
