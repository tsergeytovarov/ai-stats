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
            button.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "ai-stats")
            button.imagePosition = .imageLeading
            button.title = " $0.00"
            button.target = self
            button.action = #selector(togglePopover(_:))
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
        statusItem?.button?.title = String(format: " $%.2f", cost)
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
            pop.contentViewController = NSHostingController(rootView: DropdownView(
                viewModel: viewModel,
                onRefresh: { [weak self] in self?.onRefresh() },
                onOpenSettings: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.onOpenSettings()
                }
            ))
            popover = pop
        }
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            Task { @MainActor in
                await viewModel.reload()
                await refreshTitle()
            }
        }
    }
}
