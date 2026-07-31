import Foundation
import os.log

/// Опрашивает источники лимитов по разным расписаниям и складывает результат в
/// историю. Расписания разные не для красоты: Codex локальный и дешёвый,
/// OpenCode ходит в сеть через Cloudflare, а эндпоинт Claude отдаёт 429 с
/// Retry-After около часа.
actor LimitsCoordinator {

    struct Intervals: Sendable {
        var codex: TimeInterval = 300
        var opencode: TimeInterval = 900
        var claude: TimeInterval = 3600

        func value(for provider: LimitProvider) -> TimeInterval {
            switch provider {
            case .codex:    return codex
            case .opencode: return opencode
            case .claude:   return claude
            }
        }
    }

    private let fetchers: [any LimitsFetching]
    private let repository: LimitsRepository
    private let intervals: Intervals
    private let now: @Sendable () -> Date

    private var lastAttempt: [LimitProvider: Date] = [:]
    private var retryAfter: [LimitProvider: Date] = [:]

    init(fetchers: [any LimitsFetching],
         repository: LimitsRepository,
         intervals: Intervals = Intervals(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetchers = fetchers
        self.repository = repository
        self.intervals = intervals
        self.now = now
    }

    /// Один проход: опрашиваем тех, кому пора. Ошибки не пробрасываем — тик
    /// вызывается из общего цикла синхронизации и не должен его ронять.
    func tick() async {
        let moment = now()
        for fetcher in fetchers where shouldPoll(fetcher.provider, at: moment) {
            lastAttempt[fetcher.provider] = moment
            let limits = await fetcher.fetch()

            if limits.status == .throttled {
                // Пока Retry-After не истёк, провайдера не трогаем вообще.
                let until = limits.retryAfter ?? moment.addingTimeInterval(3600)
                retryAfter[fetcher.provider] = until
                try? await repository.saveState(provider: fetcher.provider, status: .throttled,
                                                error: limits.error, retryAfter: until, now: moment)
                continue
            }
            retryAfter[fetcher.provider] = nil

            do {
                try await repository.record(limits, now: moment)
            } catch {
                AppLogger.sync.error(
                    "limits record failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        try? await repository.pruneOldSnapshots(now: moment)
    }

    private func shouldPoll(_ provider: LimitProvider, at moment: Date) -> Bool {
        if let until = retryAfter[provider], moment < until { return false }
        guard let last = lastAttempt[provider] else { return true }
        return moment.timeIntervalSince(last) >= intervals.value(for: provider)
    }
}
