import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var snapshot: UsageSnapshot
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let builder: CodexUsageSnapshotBuilder
    private let cacheStore: SnapshotCacheStore

    public init(
        builder: CodexUsageSnapshotBuilder = CodexUsageSnapshotBuilder(),
        cacheStore: SnapshotCacheStore = SnapshotCacheStore()
    ) {
        self.builder = builder
        self.cacheStore = cacheStore
        self.snapshot = cacheStore.load() ?? .placeholder
    }

    public func start() {
        Task {
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
            try? cacheStore.save(latestSnapshot)
        } catch {
            errorMessage = "Unable to refresh Codex usage right now."
        }

        isLoading = false
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
