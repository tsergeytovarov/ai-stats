import Foundation
import ServiceManagement
import os.log

/// Тонкая обёртка над `SMAppService.mainApp` — нативный API macOS 13+ для регистрации
/// app'а в Login Items. Юзер дальше может управлять им через System Settings →
/// General → Login Items, или прямо из нашего Settings UI.
///
/// Зачем wrapper'ом: SMAppService.status — enum с четырьмя кейсами, нам в UI нужен
/// просто Bool. Плюс централизованный error-handling, плюс mockability для тестов.
@MainActor
final class LaunchAtLoginService {
    /// Текущее состояние. Возвращает true только если status = .enabled.
    /// Все остальные кейсы (.notRegistered / .notFound / .requiresApproval) — false.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Включает / выключает регистрацию в Login Items. Идемпотентна:
    /// register() на уже зарегистрированном — no-op (без re-prompt'а юзеру).
    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
            AppLogger.sync.info("Launch at login: registered")
        } else {
            guard service.status == .enabled else { return }
            try service.unregister()
            AppLogger.sync.info("Launch at login: unregistered")
        }
    }
}
