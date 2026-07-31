import XCTest
@testable import StatsApp

/// Запуск ccusage-процесса. Регрессия на дедлок: пайпы читались после
/// `waitUntilExit()`, и на выводе больше буфера пайпа (16 КБ) ccusage навсегда
/// блокировался в write(), а приложение — в ожидании его выхода. Синк вставал
/// намертво, без единой ошибки в логе: расходы просто замирали на месте.
final class CcusageProcessTests: XCTestCase {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    private func emitBytes(_ count: Int, toStderr: Bool = false) -> [String] {
        let redirect = toStderr ? " 1>&2" : ""
        return ["-c", "yes AAAAAAAAAAAAAAAA | head -c \(count)\(redirect)"]
    }

    func test_runProcess_returnsFullStdout_whenOutputExceedsPipeBuffer() throws {
        let size = 200_000  // много больше 16 КБ буфера пайпа

        let output = try CcusageFetcher.runProcess(
            executable: shell,
            arguments: emitBytes(size),
            environment: [:],
            timeout: 30
        )

        XCTAssertEqual(output.stdout.count, size)
        XCTAssertEqual(output.exitCode, 0)
    }

    func test_runProcess_returnsFullStderr_whenOutputExceedsPipeBuffer() throws {
        let size = 200_000

        let output = try CcusageFetcher.runProcess(
            executable: shell,
            arguments: emitBytes(size, toStderr: true),
            environment: [:],
            timeout: 30
        )

        XCTAssertEqual(output.stderr.count, size)
        XCTAssertEqual(output.exitCode, 0)
    }

    func test_runProcess_returnsSmallOutput() throws {
        let output = try CcusageFetcher.runProcess(
            executable: shell,
            arguments: ["-c", "printf hello; printf oops 1>&2"],
            environment: [:],
            timeout: 30
        )

        XCTAssertEqual(String(data: output.stdout, encoding: .utf8), "hello")
        XCTAssertEqual(String(data: output.stderr, encoding: .utf8), "oops")
    }

    func test_runProcess_propagatesExitCode() throws {
        let output = try CcusageFetcher.runProcess(
            executable: shell,
            arguments: ["-c", "exit 17"],
            environment: [:],
            timeout: 30
        )

        XCTAssertEqual(output.exitCode, 17)
    }

    func test_runProcess_throwsTimedOut_andKillsHangingProcess() throws {
        let started = Date()

        XCTAssertThrowsError(
            try CcusageFetcher.runProcess(
                executable: shell,
                arguments: ["-c", "sleep 120"],
                environment: [:],
                timeout: 1
            )
        ) { error in
            guard case CcusageError.timedOut = error else {
                return XCTFail("ожидали CcusageError.timedOut, получили \(error)")
            }
        }

        // Возврат по таймауту, а не по завершению `sleep 120`.
        XCTAssertLessThan(Date().timeIntervalSince(started), 30)
    }

    func test_runProcess_doesNotHangOnStdinReadingChild() throws {
        // Ребёнку закрывают stdin: `cat` без данных должен получить EOF и выйти,
        // а не ждать ввода вечно (npm умеет спрашивать подтверждение).
        let output = try CcusageFetcher.runProcess(
            executable: shell,
            arguments: ["-c", "cat"],
            environment: [:],
            timeout: 10
        )

        XCTAssertEqual(output.exitCode, 0)
        XCTAssertTrue(output.stdout.isEmpty)
    }
}
