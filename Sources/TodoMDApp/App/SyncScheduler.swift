import Foundation

// MARK: - SyncScheduler
//
// Adaptive sync scheduler that adjusts its polling interval based on whether
// the last sync succeeded or failed.
//
// Fast-path (after local mutations)
//   triggerFastSync() → schedules a sync in 5 seconds
//
// Base rate (after success)
//   30 seconds
//
// Exponential backoff (on failure)
//   failure 1  →  60 s
//   failure 2  → 120 s
//   failure 3+ → 300 s  (5-minute cap)
//
// Usage:
//   let scheduler = SyncScheduler()
//   scheduler.start { await myContainer.performSync() }
//   // …later…
//   scheduler.stop()
//   // After a local write:
//   scheduler.triggerFastSync()

@MainActor
public final class SyncScheduler {

    // MARK: - Constants

    public static let fastSyncDelay: Duration = .seconds(5)
    public static let baseInterval: Duration = .seconds(30)
    private static let backoffTable: [Duration] = [
        .seconds(60),   // 1 failure
        .seconds(120),  // 2 failures
        .seconds(300)   // 3+ failures (cap)
    ]

    // MARK: - State

    /// Number of consecutive sync failures since the last success.
    private(set) public var consecutiveFailureCount: Int = 0

    /// The wall-clock time at which the most recent sync completed (success or failure).
    private(set) public var lastSyncTime: Date?

    /// Whether the scheduler is currently running.
    private(set) public var isRunning: Bool = false

    // MARK: - Private

    private var scheduledTask: Task<Void, Never>?
    private var syncAction: (() async -> Bool)?

    // MARK: - Lifecycle

    public init() {}

    deinit {
        scheduledTask?.cancel()
    }

    // MARK: - Public API

    /// Starts the scheduling loop.
    ///
    /// - Parameter syncAction: An async closure that performs the sync.
    ///   It must return `true` on success and `false` on failure.
    /// - Note: Calling `start` when already running replaces the previous
    ///   loop with a fresh one using the new action.
    public func start(syncAction: @escaping () async -> Bool) {
        stop()
        self.syncAction = syncAction
        isRunning = true
        scheduleNext(delay: Self.baseInterval)
    }

    /// Stops the scheduling loop. Any in-flight sync is not cancelled; only
    /// the next scheduled wake-up is cancelled.
    public func stop() {
        scheduledTask?.cancel()
        scheduledTask = nil
        isRunning = false
    }

    /// Schedules an expedited sync to fire in `fastSyncDelay` seconds.
    ///
    /// Call this immediately after any local mutation (create, update, delete)
    /// so that the local change is synced to the backing store quickly.
    ///
    /// If the scheduler is not running this is a no-op.
    public func triggerFastSync() {
        guard isRunning else { return }
        // Cancel the currently pending wake-up and replace it with a fast one.
        scheduledTask?.cancel()
        scheduledTask = nil
        scheduleNext(delay: Self.fastSyncDelay)
    }

    // MARK: - Private scheduling helpers

    /// Computes the next delay from the current failure count.
    private func nextInterval() -> Duration {
        guard consecutiveFailureCount > 0 else { return Self.baseInterval }
        let index = min(consecutiveFailureCount - 1, Self.backoffTable.count - 1)
        return Self.backoffTable[index]
    }

    /// Schedules a single fire of the sync action after `delay`.
    private func scheduleNext(delay: Duration) {
        guard isRunning, let action = syncAction else { return }

        scheduledTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                // Task was cancelled — exit without syncing.
                return
            }

            guard let self, self.isRunning else { return }

            let succeeded = await action()
            self.lastSyncTime = Date()

            if succeeded {
                self.consecutiveFailureCount = 0
            } else {
                self.consecutiveFailureCount += 1
            }

            // Schedule the next iteration unless we were stopped during the sync.
            if self.isRunning {
                self.scheduleNext(delay: self.nextInterval())
            }
        }
    }
}
