import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var capsuleHosting: NSHostingView<MenuBarCapsuleView>?
    private var popover: NSPopover?
    private let viewModel: DropdownViewModel
    private let onRefresh: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(
        viewModel: DropdownViewModel,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    // Геометрия capsule — должна точно соответствовать MenuBarCapsuleView:
    //   HStack(spacing: 4) { MiniEmberView(size: 12); Text(...) }
    //     .padding(.horizontal, 8)
    // Раньше пытались читать fittingSize у NSHostingView — но SwiftUI на status
    // bar button даёт неверные размеры до полного first-layout. Capsule рос в
    // 3 стадии при кликах. Сейчас считаем ширину сами — детерминированно,
    // никакой зависимости от SwiftUI layout pass'а.
    private static let emberSize: CGFloat = 12
    private static let interItemSpacing: CGFloat = 4
    private static let horizontalPadding: CGFloat = 8 * 2  // лево + право

    /// Считает ширину capsule под priceText. Использует NSString.size(...)
    /// с тем же шрифтом что MenuBarCapsuleView (11pt semibold monospaced digit).
    /// nonisolated — pure-функция, не трогает actor state, тестируется без MainActor.
    nonisolated static func capsuleWidth(for priceText: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let textWidth = (priceText as NSString)
            .size(withAttributes: [.font: font])
            .width
        return ceil(emberSize + interItemSpacing + textWidth + horizontalPadding)
    }

    func install() {
        // Стартуем сразу с правильной шириной — никаких 3-стадийных мерцаний.
        let initialPrice = "$0.00"
        let initialWidth = Self.capsuleWidth(for: initialPrice)
        let item = NSStatusBar.system.statusItem(withLength: initialWidth)
        if let button = item.button {
            button.title = ""
            button.target = self
            button.action = #selector(togglePopover(_:))

            let hosting = NSHostingView(rootView: MenuBarCapsuleView(priceText: initialPrice))
            hosting.frame = NSRect(x: 0, y: 0, width: initialWidth, height: NSStatusBar.system.thickness)
            button.addSubview(hosting)
            self.capsuleHosting = hosting
        }
        statusItem = item

        // Обновляем заголовок при изменении aiTotals.
        Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                await self?.refreshTitle()
            }
        }
        // Подписка на изменения totals через простой Combine sink.
        observeTotals()
    }

    func refreshTitle() async {
        let cost = await viewModel.todayCost()
        let formatted = String(format: "$%.2f", cost)
        updateCapsule(priceText: formatted)
    }

    private func updateCapsule(priceText: String) {
        guard let hosting = capsuleHosting else { return }
        // Обновляем SwiftUI rootView (diff'ит содержимое, view state сохраняется)
        // и пересчитываем ширину детерминированно из priceText.
        hosting.rootView = MenuBarCapsuleView(priceText: priceText)
        let width = Self.capsuleWidth(for: priceText)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: NSStatusBar.system.thickness)
        statusItem?.length = width
        statusItem?.button?.title = ""
    }

    private func observeTotals() {
        // Каждые 30 сек обновляем title — дешёвый запрос к DB.
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshTitle() }
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover == nil {
            let pop = NSPopover()
            pop.behavior = .transient
            // Фиксируем appearance — без этого vibrancy material блекнет при потере фокуса.
            pop.appearance = NSApp.effectiveAppearance
            let hosting = NSHostingController(rootView: DropdownView(
                viewModel: viewModel,
                onRefresh: { [weak self] in self?.onRefresh() },
                onOpenSettings: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.onOpenSettings()
                },
                onQuit: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.onQuit()
                }
            ))
            pop.contentViewController = hosting
            popover = pop
        }
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Активируем app чтобы popover не открывался в «inactive» состоянии.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            Task { @MainActor in
                await viewModel.reload()
                await refreshTitle()
            }
        }
    }
}
