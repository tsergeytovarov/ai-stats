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

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = ""
            button.target = self
            button.action = #selector(togglePopover(_:))

            // Создаём NSHostingView один раз — переиспользуем между обновлениями.
            // Раньше пересоздавали на каждый refresh — это терялок view state, плюс
            // на первом install SwiftUI считал fittingSize до того как view получит
            // window context → размер был мусором, capsule выглядел обрезанным.
            // Чинится тремя выстрелами: persistent view + addSubview ДО измерения +
            // layoutSubtreeIfNeeded перед чтением размера.
            let hosting = NSHostingView(rootView: MenuBarCapsuleView(priceText: "$0.00"))
            hosting.frame = NSRect(x: 0, y: 0, width: 60, height: NSStatusBar.system.thickness)
            button.addSubview(hosting)
            self.capsuleHosting = hosting
        }
        statusItem = item

        // Первый layout: button уже в window, hosting в hierarchy → fittingSize вернёт
        // правильный размер. На следующем runloop'е чтобы SwiftUI успел начальный pass.
        DispatchQueue.main.async { [weak self] in
            self?.layoutCapsule()
        }

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
        // Обновляем rootView (SwiftUI diff'нет содержимое) — view state не теряется.
        hosting.rootView = MenuBarCapsuleView(priceText: priceText)
        layoutCapsule()
    }

    /// Принудительный layout pass + чтение реального fittingSize + обновление length
    /// statusItem'а и frame'а hosting view. Используется при install и при каждом обновлении.
    private func layoutCapsule() {
        guard let hosting = capsuleHosting else { return }
        // Прогоняем layout subtree — SwiftUI пересчитает intrinsic размеры.
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let menuBarHeight = NSStatusBar.system.thickness
        hosting.frame = NSRect(x: 0, y: 0, width: fitting.width, height: menuBarHeight)
        statusItem?.length = fitting.width
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
