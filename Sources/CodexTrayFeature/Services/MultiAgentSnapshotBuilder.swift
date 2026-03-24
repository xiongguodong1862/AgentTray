import Foundation

public struct MultiAgentSnapshotBuilder: Sendable {
    private let claudeBuilder: ClaudeUsageSnapshotBuilder
    private let geminiBuilder: GeminiUsageSnapshotBuilder
    private let calendar: Calendar
    private let petBaselineStore: PetProgressBaselineStore
    private let codexSessionsRoot: URL
    private let claudeProjectsRoot: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        calendar: Calendar = .current,
        petBaselineStore: PetProgressBaselineStore = PetProgressBaselineStore()
    ) {
        let installation = CodexInstallationLocator(homeDirectory: homeDirectory).locate()
        self.calendar = calendar
        self.petBaselineStore = petBaselineStore
        self.codexSessionsRoot = installation.sessionsRoot
        self.claudeProjectsRoot = homeDirectory.appending(path: ".claude/projects", directoryHint: .isDirectory)
        self.claudeBuilder = ClaudeUsageSnapshotBuilder(projectsRoot: self.claudeProjectsRoot, calendar: calendar)
        self.geminiBuilder = GeminiUsageSnapshotBuilder(homeDirectory: homeDirectory, calendar: calendar)
    }

    public func placeholder(
        codexSnapshot: UsageSnapshot,
        codexEnvironment: CodexEnvironmentInfo,
        focusedAgent: AgentKind = .codex
    ) -> MultiAgentSnapshot {
        let now = codexSnapshot.generatedAt
        let codexAgent = AgentSnapshot(
            agent: .codex,
            generatedAt: now,
            status: AgentStatusSummary(
                primaryLabel: "5小时余量",
                primaryValue: codexSnapshot.primaryLimit?.shortLabel ?? "--",
                primaryProgress: codexSnapshot.primaryLimit.map { $0.remainingPercent / 100 },
                secondaryLabel: "本周余量",
                secondaryValue: codexSnapshot.secondaryLimit?.shortLabel ?? "--",
                secondaryProgress: codexSnapshot.secondaryLimit.map { $0.remainingPercent / 100 }
            ),
            today: codexSnapshot.today,
            lastSevenDays: codexSnapshot.lastSevenDays.map { withSourceAgent($0, agent: .codex) },
            lastYearDays: codexSnapshot.lastYearDays.map { withSourceAgent($0, agent: .codex) },
            currentModel: nil,
            lastActiveAt: codexSnapshot.lastSevenDays.last(where: { $0.activityScore > 0 })?.date,
            environment: AgentEnvironmentSummary(
                runtimeLabel: codexEnvironment.environmentLabel,
                authLabel: codexEnvironment.authMethodLabel,
                currentModel: nil,
                dataSourceLabel: codexEnvironment.codexHomePath,
                updatedAt: now
            ),
            isAvailable: codexSnapshot.hasSourceData
        )

        let claudeAgent = AgentSnapshot.empty(agent: .claude, generatedAt: now, runtimeLabel: "Claude Code", dataSourceLabel: "~/.claude/projects")
        let geminiAgent = AgentSnapshot.empty(agent: .gemini, generatedAt: now, runtimeLabel: "Gemini CLI", dataSourceLabel: "~/.gemini")
        return aggregate(now: now, agents: [codexAgent, claudeAgent, geminiAgent], focusedAgent: focusedAgent)
    }

    public func build(
        codexSnapshot: UsageSnapshot,
        codexEnvironment: CodexEnvironmentInfo,
        focusedAgent: AgentKind,
        now: Date = .now
    ) -> MultiAgentSnapshot {
        let codexAgent = AgentSnapshot(
            agent: .codex,
            generatedAt: now,
            status: AgentStatusSummary(
                primaryLabel: "5小时余量",
                primaryValue: codexSnapshot.primaryLimit?.shortLabel ?? "--",
                primaryProgress: codexSnapshot.primaryLimit.map { $0.remainingPercent / 100 },
                secondaryLabel: "本周余量",
                secondaryValue: codexSnapshot.secondaryLimit?.shortLabel ?? "--",
                secondaryProgress: codexSnapshot.secondaryLimit.map { $0.remainingPercent / 100 }
            ),
            today: codexSnapshot.today,
            lastSevenDays: codexSnapshot.lastSevenDays.map { withSourceAgent($0, agent: .codex) },
            lastYearDays: codexSnapshot.lastYearDays.map { withSourceAgent($0, agent: .codex) },
            currentModel: nil,
            lastActiveAt: lastActiveDate(in: codexSnapshot.lastYearDays),
            environment: AgentEnvironmentSummary(
                runtimeLabel: codexEnvironment.environmentLabel,
                authLabel: codexEnvironment.authMethodLabel,
                currentModel: nil,
                dataSourceLabel: codexEnvironment.codexHomePath,
                updatedAt: now
            ),
            isAvailable: codexSnapshot.hasSourceData
        )

        let claudeAgent = (try? claudeBuilder.build(now: now))
            ?? AgentSnapshot.empty(agent: .claude, generatedAt: now, runtimeLabel: "Claude Code", dataSourceLabel: "~/.claude/projects")
        let geminiAgent = (try? geminiBuilder.build(now: now))
            ?? AgentSnapshot.empty(agent: .gemini, generatedAt: now, runtimeLabel: "Gemini CLI", dataSourceLabel: "~/.gemini")

        return aggregate(now: now, agents: [codexAgent, claudeAgent, geminiAgent], focusedAgent: focusedAgent)
    }

    public func refreshRecentActivity(
        in snapshot: MultiAgentSnapshot,
        now: Date = .now
    ) -> MultiAgentSnapshot {
        let codexRecent = latestTimestampInLatestJSONL(under: codexSessionsRoot) ?? snapshot.snapshot(for: .codex)?.lastActiveAt
        let claudeRecent = latestTimestampInLatestJSONL(under: claudeProjectsRoot) ?? snapshot.snapshot(for: .claude)?.lastActiveAt
        let geminiRecent = snapshot.snapshot(for: .gemini)?.lastActiveAt

        let latest = [
            codexRecent.map { (AgentKind.codex, $0) },
            claudeRecent.map { (AgentKind.claude, $0) },
            geminiRecent.map { (AgentKind.gemini, $0) },
        ]
        .compactMap { $0 }
        .max(by: { $0.1 < $1.1 })

        guard let latest else {
            return snapshot
        }

        return MultiAgentSnapshot(
            generatedAt: snapshot.generatedAt,
            agents: snapshot.agents,
            mostRecentlyActiveAgent: latest.0,
            focusedAgent: latest.0,
            pet: snapshot.pet,
            xpBreakdown: snapshot.xpBreakdown,
            todaySummary: snapshot.todaySummary,
            lastSevenDays: snapshot.lastSevenDays,
            lastMonthDays: snapshot.lastMonthDays,
            lastYearDays: snapshot.lastYearDays
        )
    }

    private func aggregate(now: Date, agents: [AgentSnapshot], focusedAgent: AgentKind) -> MultiAgentSnapshot {
        let allAgents = agents.filter { $0.agent != .all }
        let availableAgents = allAgents.filter(\.isAvailable)
        let lastYearDays = merge(dailySeries: availableAgents.map(\.lastYearDays), now: now, dayCount: 365)
        let lastMonthDays = Array(lastYearDays.suffix(30))
        let lastSevenDays = Array(lastYearDays.suffix(7))
        let today = lastYearDays.last ?? .empty(for: calendar.startOfDay(for: now))
        let todaySummary = MultiAgentTodaySummary(
            totalSessions: today.dialogs,
            totalActiveMinutes: today.activeMinutes,
            totalTokenUsage: today.tokenUsage,
            totalToolCalls: today.toolCalls
        )
        let xpBreakdown = availableAgents.map { agent in
            AgentXPBreakdown(
                agent: agent.agent,
                todayXP: Int(agent.today.activityScore.rounded()),
                totalXP: agent.lastYearDays.reduce(0) { $0 + Int($1.activityScore.rounded()) }
            )
        }
        let totalXP = xpBreakdown.reduce(0) { $0 + $1.totalXP }
        let todayXP = xpBreakdown.reduce(0) { $0 + $1.todayXP }
        let baselineDay = calendar.startOfDay(for: now)
        let baseline = resolvePetBaseline(totalXP: totalXP, todayXP: todayXP, day: baselineDay)
        let adjustedTodayXP: Int
        if calendar.isDate(baseline.day, inSameDayAs: baselineDay) {
            adjustedTodayXP = max(0, todayXP - baseline.todayXP)
        } else {
            adjustedTodayXP = todayXP
        }
        let pet = PetProgressCalculator.progress(
            totalXP: max(0, totalXP - baseline.totalXP),
            todayXP: adjustedTodayXP
        )
        let mostRecentlyActiveAgent = availableAgents
            .compactMap { snapshot -> (AgentKind, Date)? in
                guard let date = snapshot.lastActiveAt else { return nil }
                return (snapshot.agent, date)
            }
            .max(by: { $0.1 < $1.1 })?
            .0

        return MultiAgentSnapshot(
            generatedAt: now,
            agents: allAgents,
            mostRecentlyActiveAgent: mostRecentlyActiveAgent,
            focusedAgent: focusedAgent,
            pet: pet,
            xpBreakdown: xpBreakdown,
            todaySummary: todaySummary,
            lastSevenDays: lastSevenDays,
            lastMonthDays: lastMonthDays,
            lastYearDays: lastYearDays
        )
    }

    private func resolvePetBaseline(totalXP: Int, todayXP: Int, day: Date) -> PetProgressBaseline {
        if let baseline = petBaselineStore.load() {
            return baseline
        }

        let baseline = PetProgressBaseline(totalXP: totalXP, todayXP: todayXP, day: day)
        try? petBaselineStore.save(baseline)
        return baseline
    }

    private func merge(dailySeries: [[UsageMetricsDay]], now: Date, dayCount: Int) -> [UsageMetricsDay] {
        let startOfToday = calendar.startOfDay(for: now)
        let allDays = (0..<dayCount).map { offset in
            calendar.date(byAdding: .day, value: offset - (dayCount - 1), to: startOfToday) ?? startOfToday
        }
        let lookups = dailySeries.map { Dictionary(uniqueKeysWithValues: $0.map { (calendar.startOfDay(for: $0.date), $0) }) }

        return allDays.map { date in
            let matching = lookups.compactMap { $0[date] }
            let dialogs = matching.reduce(0) { $0 + $1.dialogs }
            let activeMinutes = matching.reduce(0) { $0 + $1.activeMinutes }
            let modifiedFiles = matching.reduce(0) { $0 + $1.modifiedFiles }
            let addedLines = matching.reduce(0) { $0 + $1.addedLines }
            let deletedLines = matching.reduce(0) { $0 + $1.deletedLines }
            let tokenUsage = matching.reduce(0) { $0 + $1.tokenUsage }
            let toolCalls = matching.reduce(0) { $0 + $1.toolCalls }
            let activityScore = matching.reduce(0) { $0 + $1.activityScore }
            let sourceAgents = Array(Set(matching.flatMap(\.sourceAgents))).sorted()

            return UsageMetricsDay(
                date: date,
                dialogs: dialogs,
                activeMinutes: activeMinutes,
                modifiedFiles: modifiedFiles,
                addedLines: addedLines,
                deletedLines: deletedLines,
                tokenUsage: tokenUsage,
                toolCalls: toolCalls,
                customActivityScore: activityScore,
                interactionLabel: "会话",
                sourceAgents: sourceAgents
            )
        }
    }

    private func lastActiveDate(in days: [UsageMetricsDay]) -> Date? {
        days.reversed().first(where: { $0.activityScore > 0 })?.date
    }

    private func latestTimestampInLatestJSONL(under root: URL) -> Date? {
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var latestFile: URL?
        var latestModifiedAt: Date?

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            if latestModifiedAt == nil || modifiedAt > latestModifiedAt! {
                latestModifiedAt = modifiedAt
                latestFile = fileURL
            }
        }

        guard let latestFile, let content = try? String(contentsOf: latestFile, encoding: .utf8) else {
            return nil
        }

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            guard
                let data = String(rawLine).data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let timestampString = json["timestamp"] as? String,
                let timestamp = ISO8601DateParser.parse(timestampString)
            else {
                continue
            }
            return timestamp
        }

        return nil
    }
}

private struct ClaudeSessionDayAccumulator {
    var sessionIDs: Set<String> = []
    var timestamps: [Date] = []
    var tokenUsage = 0
    var toolCalls = 0
    var lastModel: String?
}

private struct GeminiSessionDayAccumulator {
    var sessionIDs: Set<String> = []
    var timestamps: [Date] = []
    var tokenUsage = 0
    var toolCalls = 0
    var lastModel: String?
}

struct ClaudeUsageSnapshotBuilder: Sendable {
    private let projectsRoot: URL
    private let calendar: Calendar

    init(homeDirectory: URL, calendar: Calendar) {
        self.projectsRoot = homeDirectory.appending(path: ".claude/projects", directoryHint: .isDirectory)
        self.calendar = calendar
    }

    init(projectsRoot: URL, calendar: Calendar) {
        self.projectsRoot = projectsRoot
        self.calendar = calendar
    }

    func build(now: Date = .now) throws -> AgentSnapshot {
        guard FileManager.default.fileExists(atPath: projectsRoot.path) else {
            return AgentSnapshot.empty(agent: .claude, generatedAt: now, runtimeLabel: "Claude Code", dataSourceLabel: "~/.claude/projects")
        }

        var accumulators: [Date: ClaudeSessionDayAccumulator] = [:]
        var currentModel: String?
        var lastActiveAt: Date?

        let enumerator = FileManager.default.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
                guard
                    let data = String(rawLine).data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let timestampString = json["timestamp"] as? String,
                    let timestamp = ISO8601DateParser.parse(timestampString)
                else {
                    continue
                }

                let day = calendar.startOfDay(for: timestamp)
                var accumulator = accumulators[day] ?? ClaudeSessionDayAccumulator()
                accumulator.timestamps.append(timestamp)
                lastActiveAt = max(lastActiveAt ?? timestamp, timestamp)

                if let sessionID = json["sessionId"] as? String, !sessionID.isEmpty {
                    accumulator.sessionIDs.insert(sessionID)
                }

                if let type = json["type"] as? String, type == "assistant",
                   let message = json["message"] as? [String: Any] {
                    if let model = message["model"] as? String, !model.isEmpty {
                        accumulator.lastModel = model
                        currentModel = model
                    }
                    if let usage = message["usage"] as? [String: Any] {
                        let inputTokens = usage["input_tokens"] as? Int ?? 0
                        let outputTokens = usage["output_tokens"] as? Int ?? 0
                        accumulator.tokenUsage += inputTokens + outputTokens
                    }
                    if let contentItems = message["content"] as? [[String: Any]] {
                        accumulator.toolCalls += contentItems.filter { ($0["type"] as? String) == "tool_use" }.count
                    }
                }

                accumulators[day] = accumulator
            }
        }

        let daily = buildDailyMetrics(from: accumulators, now: now)
        let today = daily.last ?? .empty(for: calendar.startOfDay(for: now))
        let status = AgentStatusSummary(
            primaryLabel: "今日 Token",
            primaryValue: CompactNumberFormatter.string(for: today.tokenUsage)
        )

        return AgentSnapshot(
            agent: .claude,
            generatedAt: now,
            status: status,
            today: today,
            lastSevenDays: Array(daily.suffix(7)),
            lastYearDays: daily,
            currentModel: currentModel,
            lastActiveAt: lastActiveAt,
            environment: AgentEnvironmentSummary(
                runtimeLabel: "Claude Code",
                authLabel: nil,
                currentModel: currentModel,
                dataSourceLabel: "~/.claude/projects",
                updatedAt: now
            ),
            isAvailable: accumulators.isEmpty == false
        )
    }

    private func buildDailyMetrics(from accumulators: [Date: ClaudeSessionDayAccumulator], now: Date) -> [UsageMetricsDay] {
        let startOfToday = calendar.startOfDay(for: now)
        return (0..<365).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - 364, to: startOfToday) ?? startOfToday
            let accumulator = accumulators[date] ?? ClaudeSessionDayAccumulator()
            let sessionCount = accumulator.sessionIDs.count
            let activeMinutes = ActivityTimelineCalculator.activeMinutes(for: accumulator.timestamps)
            let score = ClaudeActivityScoreCalculator.score(
                sessions: sessionCount,
                activeMinutes: activeMinutes,
                tokenUsage: accumulator.tokenUsage,
                toolCalls: accumulator.toolCalls
            )
            return UsageMetricsDay(
                date: date,
                dialogs: sessionCount,
                activeMinutes: activeMinutes,
                modifiedFiles: 0,
                addedLines: 0,
                deletedLines: 0,
                tokenUsage: accumulator.tokenUsage,
                toolCalls: accumulator.toolCalls,
                customActivityScore: score,
                interactionLabel: "会话",
                sourceAgents: score > 0 ? [AgentKind.claude.displayName] : []
            )
        }
    }
}

struct GeminiUsageSnapshotBuilder: Sendable {
    private let logsRoot: URL
    private let settingsURL: URL
    private let calendar: Calendar

    init(homeDirectory: URL, calendar: Calendar) {
        self.logsRoot = homeDirectory.appending(path: ".gemini/tmp", directoryHint: .isDirectory)
        self.settingsURL = homeDirectory.appending(path: ".gemini/settings.json")
        self.calendar = calendar
    }

    init(logsRoot: URL, settingsURL: URL, calendar: Calendar) {
        self.logsRoot = logsRoot
        self.settingsURL = settingsURL
        self.calendar = calendar
    }

    func build(now: Date = .now) throws -> AgentSnapshot {
        let dataSourceLabel = logsRoot.path
        guard FileManager.default.fileExists(atPath: logsRoot.path) else {
            return AgentSnapshot.empty(agent: .gemini, generatedAt: now, runtimeLabel: "Gemini CLI", dataSourceLabel: dataSourceLabel)
        }

        var accumulators: [Date: GeminiSessionDayAccumulator] = [:]
        var currentModel: String?
        var lastActiveAt: Date?

        let enumerator = FileManager.default.enumerator(
            at: logsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathComponents.contains("chats"), fileURL.pathExtension == "json" {
                guard let content = try? Data(contentsOf: fileURL) else { continue }
                guard let chat = try? JSONSerialization.jsonObject(with: content) as? [String: Any] else { continue }
                ingestChatSession(
                    chat,
                    into: &accumulators,
                    currentModel: &currentModel,
                    lastActiveAt: &lastActiveAt
                )
                continue
            }
        }

        if accumulators.isEmpty {
            let fallbackEnumerator = FileManager.default.enumerator(
                at: logsRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            while let fileURL = fallbackEnumerator?.nextObject() as? URL {
                guard fileURL.lastPathComponent == "logs.json" else { continue }
                guard let content = try? Data(contentsOf: fileURL) else { continue }
                guard let items = try? JSONSerialization.jsonObject(with: content) as? [[String: Any]] else { continue }

                for item in items {
                    ingestLogItem(
                        item,
                        into: &accumulators,
                        currentModel: &currentModel,
                        lastActiveAt: &lastActiveAt
                    )
                }
            }
        }

        let daily = buildDailyMetrics(from: accumulators, now: now)
        let today = daily.last ?? .empty(for: calendar.startOfDay(for: now))
        let status = AgentStatusSummary(
            primaryLabel: "今日 Token",
            primaryValue: CompactNumberFormatter.string(for: today.tokenUsage)
        )

        return AgentSnapshot(
            agent: .gemini,
            generatedAt: now,
            status: status,
            today: today,
            lastSevenDays: Array(daily.suffix(7)),
            lastYearDays: daily,
            currentModel: currentModel,
            lastActiveAt: lastActiveAt,
            environment: AgentEnvironmentSummary(
                runtimeLabel: "Gemini CLI",
                authLabel: geminiAuthLabel(),
                currentModel: currentModel,
                dataSourceLabel: dataSourceLabel,
                updatedAt: now
            ),
            isAvailable: accumulators.isEmpty == false
        )
    }

    private func ingestChatSession(
        _ chat: [String: Any],
        into accumulators: inout [Date: GeminiSessionDayAccumulator],
        currentModel: inout String?,
        lastActiveAt: inout Date?
    ) {
        guard let sessionID = chat["sessionId"] as? String, !sessionID.isEmpty else { return }
        guard let messages = chat["messages"] as? [[String: Any]] else { return }

        for message in messages {
            guard
                let timestampString = message["timestamp"] as? String,
                let timestamp = ISO8601DateParser.parse(timestampString)
            else {
                continue
            }

            let day = calendar.startOfDay(for: timestamp)
            var accumulator = accumulators[day] ?? GeminiSessionDayAccumulator()
            accumulator.timestamps.append(timestamp)
            accumulator.sessionIDs.insert(sessionID)
            lastActiveAt = max(lastActiveAt ?? timestamp, timestamp)

            if let model = extractModel(from: message), !model.isEmpty {
                accumulator.lastModel = model
                currentModel = model
            }

            accumulator.tokenUsage += extractTokenUsage(from: message)
            accumulator.toolCalls += extractToolCalls(from: message)
            accumulators[day] = accumulator
        }
    }

    private func ingestLogItem(
        _ item: [String: Any],
        into accumulators: inout [Date: GeminiSessionDayAccumulator],
        currentModel: inout String?,
        lastActiveAt: inout Date?
    ) {
        guard
            let timestampString = item["timestamp"] as? String,
            let timestamp = ISO8601DateParser.parse(timestampString)
        else {
            return
        }

        let day = calendar.startOfDay(for: timestamp)
        var accumulator = accumulators[day] ?? GeminiSessionDayAccumulator()
        accumulator.timestamps.append(timestamp)
        lastActiveAt = max(lastActiveAt ?? timestamp, timestamp)

        if let sessionID = item["sessionId"] as? String, !sessionID.isEmpty {
            accumulator.sessionIDs.insert(sessionID)
        }

        if let model = extractModel(from: item), !model.isEmpty {
            accumulator.lastModel = model
            currentModel = model
        }

        accumulator.tokenUsage += extractTokenUsage(from: item)
        accumulator.toolCalls += extractToolCalls(from: item)
        accumulators[day] = accumulator
    }

    private func buildDailyMetrics(from accumulators: [Date: GeminiSessionDayAccumulator], now: Date) -> [UsageMetricsDay] {
        let startOfToday = calendar.startOfDay(for: now)
        return (0..<365).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - 364, to: startOfToday) ?? startOfToday
            let accumulator = accumulators[date] ?? GeminiSessionDayAccumulator()
            let sessionCount = accumulator.sessionIDs.count
            let activeMinutes = ActivityTimelineCalculator.activeMinutes(for: accumulator.timestamps)
            let score = ClaudeActivityScoreCalculator.score(
                sessions: sessionCount,
                activeMinutes: activeMinutes,
                tokenUsage: accumulator.tokenUsage,
                toolCalls: accumulator.toolCalls
            )
            return UsageMetricsDay(
                date: date,
                dialogs: sessionCount,
                activeMinutes: activeMinutes,
                modifiedFiles: 0,
                addedLines: 0,
                deletedLines: 0,
                tokenUsage: accumulator.tokenUsage,
                toolCalls: accumulator.toolCalls,
                customActivityScore: score,
                interactionLabel: "会话",
                sourceAgents: score > 0 ? [AgentKind.gemini.displayName] : []
            )
        }
    }

    private func geminiAuthLabel() -> String? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard
            let security = json["security"] as? [String: Any],
            let auth = security["auth"] as? [String: Any],
            let selectedType = auth["selectedType"] as? String,
            !selectedType.isEmpty
        else {
            return nil
        }
        return selectedType
    }

    private func extractModel(from item: [String: Any]) -> String? {
        if let model = item["model"] as? String {
            return model
        }
        if let message = item["message"] as? [String: Any],
           let model = message["model"] as? String {
            return model
        }
        return nil
    }

    private func extractTokenUsage(from item: [String: Any]) -> Int {
        if let tokens = item["tokens"] as? [String: Any] {
            let totalTokens = intValue(in: tokens, keys: ["total"])
            if totalTokens > 0 { return totalTokens }
            let inputTokens = intValue(in: tokens, keys: ["input"])
            let outputTokens = intValue(in: tokens, keys: ["output"])
            let thoughtTokens = intValue(in: tokens, keys: ["thoughts"])
            let toolTokens = intValue(in: tokens, keys: ["tool"])
            let cachedTokens = intValue(in: tokens, keys: ["cached"])
            let sum = inputTokens + outputTokens + thoughtTokens + toolTokens + cachedTokens
            if sum > 0 { return sum }
        }
        let sources = [item["usage"], (item["message"] as? [String: Any])?["usage"]]
        for source in sources {
            guard let usage = source as? [String: Any] else { continue }
            let inputTokens = intValue(in: usage, keys: ["input_tokens", "inputTokens", "prompt_tokens", "promptTokenCount"])
            let outputTokens = intValue(in: usage, keys: ["output_tokens", "outputTokens", "completion_tokens", "candidatesTokenCount"])
            let totalTokens = intValue(in: usage, keys: ["total_tokens", "totalTokens", "totalTokenCount"])
            let sum = inputTokens + outputTokens
            if sum > 0 { return sum }
            if totalTokens > 0 { return totalTokens }
        }
        return 0
    }

    private func extractToolCalls(from item: [String: Any]) -> Int {
        if let type = item["type"] as? String,
           type == "tool" || type == "tool_use" || type == "function_call" {
            return 1
        }
        if let type = item["type"] as? String,
           type == "gemini" || type == "assistant",
           let tools = item["tools"] as? [[String: Any]] {
            return tools.count
        }
        if let message = item["message"] as? [String: Any] {
            if let content = message["content"] as? [[String: Any]] {
                return content.filter {
                    guard let type = $0["type"] as? String else { return false }
                    return type == "tool_use" || type == "tool" || type == "function_call"
                }.count
            }
            if message["toolCalls"] != nil || message["tool_calls"] != nil {
                return max(
                    intValue(in: message, keys: ["toolCalls"]),
                    intValue(in: message, keys: ["tool_calls"])
                )
            }
        }
        return 0
    }

    private func intValue(in dictionary: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? Double {
                return Int(value)
            }
            if let value = dictionary[key] as? String, let int = Int(value) {
                return int
            }
        }
        return 0
    }
}

private enum ClaudeActivityScoreCalculator {
    static func score(sessions: Int, activeMinutes: Int, tokenUsage: Int, toolCalls: Int) -> Double {
        (3 * Double(sessions))
            + (0.45 * Double(activeMinutes))
            + (0.14 * sqrt(Double(max(0, tokenUsage))))
            + (1.8 * Double(toolCalls))
    }
}

private enum CompactNumberFormatter {
    static func string(for value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

extension AgentSnapshot {
    static func empty(agent: AgentKind, generatedAt: Date, runtimeLabel: String, dataSourceLabel: String) -> AgentSnapshot {
        let startOfDay = Calendar.current.startOfDay(for: generatedAt)
        let lastYearDays = (0..<365).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset - 364, to: startOfDay) ?? startOfDay
            return UsageMetricsDay(
                date: date,
                dialogs: 0,
                activeMinutes: 0,
                modifiedFiles: 0,
                addedLines: 0,
                deletedLines: 0,
                tokenUsage: 0,
                toolCalls: 0,
                customActivityScore: 0,
                interactionLabel: "会话",
                sourceAgents: []
            )
        }
        return AgentSnapshot(
            agent: agent,
            generatedAt: generatedAt,
            status: AgentStatusSummary(primaryLabel: "状态", primaryValue: "--"),
            today: lastYearDays.last ?? .empty(for: startOfDay),
            lastSevenDays: Array(lastYearDays.suffix(7)),
            lastYearDays: lastYearDays,
            currentModel: nil,
            lastActiveAt: nil,
            environment: AgentEnvironmentSummary(
                runtimeLabel: runtimeLabel,
                authLabel: nil,
                currentModel: nil,
                dataSourceLabel: dataSourceLabel,
                updatedAt: generatedAt
            ),
            isAvailable: false
        )
    }

}

private func withSourceAgent(_ day: UsageMetricsDay, agent: AgentKind) -> UsageMetricsDay {
    UsageMetricsDay(
        date: day.date,
        dialogs: day.dialogs,
        activeMinutes: day.activeMinutes,
        modifiedFiles: day.modifiedFiles,
        addedLines: day.addedLines,
        deletedLines: day.deletedLines,
        tokenUsage: day.tokenUsage,
        toolCalls: day.toolCalls,
        customActivityScore: day.customActivityScore,
        interactionLabel: day.interactionLabel,
        sourceAgents: day.activityScore > 0 ? [agent.displayName] : []
    )
}
