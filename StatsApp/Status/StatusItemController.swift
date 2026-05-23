import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let viewModel: DropdownViewModel
    private let onRefresh: () -> Void
    private let onOpenSettings: () -> Void

    init(viewModel: DropdownViewModel, onRefresh: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = ""
            button.target = self
            button.action = #selector(togglePopover(_:))
            updateCapsule(in: button, priceText: "$0.00")
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
        guard let button = statusItem?.button else { return }
        updateCapsule(in: button, priceText: formatted)
    }

    private func updateCapsule(in button: NSStatusBarButton, priceText: String) {
        let hosting = NSHostingView(rootView: MenuBarCapsuleView(priceText: priceText))
        hosting.frame.size = hosting.intrinsicContentSize
        // Cap height to menu bar thickness so the capsule never overflows.
        let menuBarHeight = NSStatusBar.system.thickness
        if hosting.frame.size.height > menuBarHeight {
            hosting.frame.size.height = menuBarHeight
        }
        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(hosting)
        button.frame.size = hosting.frame.size
        button.title = ""
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
