import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var snapshot: UsageSnapshot
    @Published public private(set) var multiAgentSnapshot: MultiAgentSnapshot
    @Published public private(set) var environmentInfo: CodexEnvironmentInfo
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var selectedAgent: AgentKind
    @Published public private(set) var focusedAgent: AgentKind

    private let builder: CodexUsageSnapshotBuilder
    private let multiAgentBuilder: MultiAgentSnapshotBuilder
    private let codexCacheStore: SnapshotCacheStore
    private let multiAgentCacheStore: MultiAgentSnapshotCacheStore
    private let agentCacheStore: AgentSnapshotCacheStore

    public init(
        builder: CodexUsageSnapshotBuilder = CodexUsageSnapshotBuilder(),
        multiAgentBuilder: MultiAgentSnapshotBuilder? = nil,
        cacheStore: SnapshotCacheStore = SnapshotCacheStore(),
        multiAgentCacheStore: MultiAgentSnapshotCacheStore = MultiAgentSnapshotCacheStore(),
        agentCacheStore: AgentSnapshotCacheStore = AgentSnapshotCacheStore()
    ) {
        let initialSnapshot = cacheStore.load() ?? .placeholder
        let initialFocusedAgent: AgentKind = .codex
        self.builder = builder
        self.multiAgentBuilder = multiAgentBuilder ?? MultiAgentSnapshotBuilder()
        self.codexCacheStore = cacheStore
        self.multiAgentCacheStore = multiAgentCacheStore
        self.agentCacheStore = agentCacheStore
        self.snapshot = initialSnapshot
        self.environmentInfo = builder.environmentInfo
        let cachedMultiAgent = multiAgentCacheStore.load()
            ?? Self.rebuildMultiAgentCache(
                codexSnapshot: initialSnapshot,
                codexEnvironment: builder.environmentInfo,
                focusedAgent: initialFocusedAgent,
                agentCacheStore: agentCacheStore
            )
        self.selectedAgent = .all
        self.focusedAgent = cachedMultiAgent?.focusedAgent ?? initialFocusedAgent
        self.multiAgentSnapshot = cachedMultiAgent ?? self.multiAgentBuilder.placeholder(
            codexSnapshot: initialSnapshot,
            codexEnvironment: builder.environmentInfo,
            focusedAgent: cachedMultiAgent?.focusedAgent ?? initialFocusedAgent
        )
        reconcileSelection()
    }

    public func start() {
        Task {
            if multiAgentSnapshot.agents.contains(where: \.isAvailable) {
                multiAgentSnapshot = multiAgentBuilder.refreshRecentActivity(in: multiAgentSnapshot)
                reconcileSelection()
            } else {
                await refresh()
                return
            }
            await refresh()
        }
    }

    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let builder = self.builder
            let latestSnapshot = try await Task.detached(priority: .utility) {
                try builder.buildSnapshot(now: Date())
            }.value
            snapshot = latestSnapshot
            multiAgentSnapshot = multiAgentBuilder.build(
                codexSnapshot: latestSnapshot,
                codexEnvironment: environmentInfo,
                focusedAgent: focusedAgent,
                now: latestSnapshot.generatedAt
            )
            reconcileSelection()
            try? codexCacheStore.save(latestSnapshot)
            try? multiAgentCacheStore.save(multiAgentSnapshot)
            for snapshot in multiAgentSnapshot.agents where snapshot.agent != .all {
                try? agentCacheStore.save(snapshot)
            }
        } catch {
            errorMessage = "Unable to refresh Codex usage right now."
        }

        isLoading = false
    }

    public func selectAgent(_ agent: AgentKind) {
        selectedAgent = agent
        if agent != .all {
            focusedAgent = agent
        }
        multiAgentSnapshot = MultiAgentSnapshot(
            generatedAt: multiAgentSnapshot.generatedAt,
            agents: multiAgentSnapshot.agents,
            mostRecentlyActiveAgent: multiAgentSnapshot.mostRecentlyActiveAgent,
            focusedAgent: focusedAgent,
            pet: multiAgentSnapshot.pet,
            xpBreakdown: multiAgentSnapshot.xpBreakdown,
            todaySummary: multiAgentSnapshot.todaySummary,
            lastSevenDays: multiAgentSnapshot.lastSevenDays,
            lastMonthDays: multiAgentSnapshot.lastMonthDays,
            lastYearDays: multiAgentSnapshot.lastYearDays
        )
        reconcileSelection()
    }

    private func reconcileSelection() {
        let availableAgents = multiAgentSnapshot.agents.filter(\.isAvailable).map(\.agent)
        if selectedAgent != .all, availableAgents.contains(selectedAgent) == false {
            selectedAgent = .all
        }
        if availableAgents.contains(focusedAgent) == false {
            focusedAgent = availableAgents.first ?? .codex
        }
    }

    private static func rebuildMultiAgentCache(
        codexSnapshot: UsageSnapshot,
        codexEnvironment: CodexEnvironmentInfo,
        focusedAgent: AgentKind,
        agentCacheStore: AgentSnapshotCacheStore
    ) -> MultiAgentSnapshot? {
        let builder = MultiAgentSnapshotBuilder()
        let baseline = builder.placeholder(
            codexSnapshot: codexSnapshot,
            codexEnvironment: codexEnvironment,
            focusedAgent: focusedAgent
        )
        let replacements = Dictionary(
            uniqueKeysWithValues: AgentKind.allCases
                .filter { $0 != .all }
                .compactMap { agent in
                    agentCacheStore.load(agent: agent).map { (agent, $0) }
                }
        )
        guard replacements.isEmpty == false else { return nil }
        let agents = baseline.agents.map { replacements[$0.agent] ?? $0 }
        return MultiAgentSnapshot(
            generatedAt: baseline.generatedAt,
            agents: agents,
            mostRecentlyActiveAgent: agents.filter(\.isAvailable)
                .compactMap { snapshot -> (AgentKind, Date)? in
                    guard let lastActiveAt = snapshot.lastActiveAt else { return nil }
                    return (snapshot.agent, lastActiveAt)
                }
                .max(by: { $0.1 < $1.1 })?
                .0,
            focusedAgent: focusedAgent,
            pet: baseline.pet,
            xpBreakdown: baseline.xpBreakdown,
            todaySummary: baseline.todaySummary,
            lastSevenDays: baseline.lastSevenDays,
            lastMonthDays: baseline.lastMonthDays,
            lastYearDays: baseline.lastYearDays
        )
    }
}

public struct SnapshotCacheStore {
    private let cacheURL: URL

    public init(
        cacheURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let cacheURL {
            self.cacheURL = cacheURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheURL = appSupport
                .appending(path: "CodexTray", directoryHint: .isDirectory)
                .appending(path: "usage-snapshot.json")
        }
    }

    public func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    public func save(_ snapshot: UsageSnapshot) throws {
        let directoryURL = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: cacheURL, options: .atomic)
    }
}

public struct MultiAgentSnapshotCacheStore {
    private let cacheURL: URL

    public init(
        cacheURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let cacheURL {
            self.cacheURL = cacheURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheURL = appSupport
                .appending(path: "CodexTray", directoryHint: .isDirectory)
                .appending(path: "multi-agent-snapshot.json")
        }
    }

    public func load() -> MultiAgentSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(MultiAgentSnapshot.self, from: data)
    }

    public func save(_ snapshot: MultiAgentSnapshot) throws {
        let directoryURL = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: cacheURL, options: .atomic)
    }
}

public struct AgentSnapshotCacheStore {
    private let directoryURL: URL

    public init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directoryURL = appSupport
                .appending(path: "CodexTray", directoryHint: .isDirectory)
                .appending(path: "agent-snapshots", directoryHint: .isDirectory)
        }
    }

    public func load(agent: AgentKind) -> AgentSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: agent)) else { return nil }
        return try? JSONDecoder().decode(AgentSnapshot.self, from: data)
    }

    public func save(_ snapshot: AgentSnapshot) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL(for: snapshot.agent), options: .atomic)
    }

    private func fileURL(for agent: AgentKind) -> URL {
        directoryURL.appending(path: "\(agent.rawValue)-snapshot.json")
    }
}

public struct PetProgressBaselineStore: Sendable {
    private let cacheURL: URL

    public init(
        cacheURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let cacheURL {
            self.cacheURL = cacheURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheURL = appSupport
                .appending(path: "CodexTray", directoryHint: .isDirectory)
                .appending(path: "pet-progress-baseline.json")
        }
    }

    public func load() -> PetProgressBaseline? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(PetProgressBaseline.self, from: data)
    }

    public func save(_ baseline: PetProgressBaseline) throws {
        let directoryURL = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(baseline)
        try data.write(to: cacheURL, options: .atomic)
    }
}
