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
    // nonisolated — используются из nonisolated static func capsuleWidth(for:showsRings:)
    // ниже; сами по себе неизменяемые константы, actor isolation им не нужна.
    nonisolated private static let emberSize: CGFloat = 12
    nonisolated private static let interItemSpacing: CGFloat = 4
    nonisolated private static let horizontalPadding: CGFloat = 8 * 2  // лево + право

    // Геометрия колец лимитов — должна точно соответствовать MenuBarCapsuleView:
    //   .padding(.leading, 2) + HStack(spacing: 3) из 3 LimitRingView(diameter: 10)
    // Без этого слагаемого frame капсулы уже, чем реальный SwiftUI-контент —
    // кольца обрезаются по правому краю, а не просто «не помещаются красиво».
    nonisolated private static let ringDiameter: CGFloat = 10
    nonisolated private static let ringSpacing: CGFloat = 3
    nonisolated private static let ringsLeadingPadding: CGFloat = 2

    nonisolated private static var ringsWidth: CGFloat {
        let count = CGFloat(LimitProvider.allCases.count)
        guard count > 0 else { return 0 }
        return ringsLeadingPadding + count * ringDiameter + (count - 1) * ringSpacing
    }

    /// Считает ширину capsule под priceText (+ кольца лимитов, если показаны).
    /// Использует NSString.size(...) с тем же шрифтом что MenuBarCapsuleView
    /// (11pt semibold monospaced digit).
    /// nonisolated — pure-функция, не трогает actor state, тестируется без MainActor.
    /// showsRings по умолчанию false — старые вызовы (и тесты капсулы без лимитов)
    /// продолжают считать ширину так же, как до задачи 8.
    ///
    /// Внешний HStack(spacing: 4) в MenuBarCapsuleView — это 2 дочерних вью без
    /// колец (Ember, Text) и 3 с кольцами (Ember, Text, HStack колец): 1 разрыв
    /// spacing превращается в 2. Без второго interItemSpacing правый край
    /// последнего кольца съезжал под обрезку NSStatusItem на 4pt — это нашли
    /// в ревью до слияния.
    nonisolated static func capsuleWidth(for priceText: String, showsRings: Bool = false) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let textWidth = (priceText as NSString)
            .size(withAttributes: [.font: font])
            .width
        var width = emberSize + interItemSpacing + textWidth + horizontalPadding
        if showsRings {
            width += interItemSpacing + ringsWidth
        }
        return ceil(width)
    }

    func install() {
        // Стартуем сразу с правильной шириной — никаких 3-стадийных мерцаний.
        let initialPrice = "$0.00"
        // Источник лимитов — тот же, что у попапа (DropdownViewModel.limits),
        // второй путь загрузки не заводим. На старте он обычно ещё пуст —
        // до первого loadLimits() кольца просто не покажутся.
        let initialLimits = viewModel.limits
        let showsRings = MenuBarCapsuleView.showsRings(for: initialLimits)
        let initialWidth = Self.capsuleWidth(for: initialPrice, showsRings: showsRings)
        let item = NSStatusBar.system.statusItem(withLength: initialWidth)
        if let button = item.button {
            button.title = ""
            button.target = self
            button.action = #selector(togglePopover(_:))

            let hosting = NSHostingView(
                rootView: MenuBarCapsuleView(priceText: initialPrice, limits: initialLimits)
            )
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
        // limits читаем из той же вью-модели, что и попап (DropdownViewModel.limits) —
        // она обновляется через loadLimits(), отдельного опроса тут нет.
        updateCapsule(priceText: formatted, limits: viewModel.limits)
    }

    private func updateCapsule(priceText: String, limits: [LimitProvider: ProviderLimits]) {
        guard let hosting = capsuleHosting else { return }
        // Обновляем SwiftUI rootView (diff'ит содержимое, view state сохраняется)
        // и пересчитываем ширину детерминированно из priceText + наличия колец.
        let showsRings = MenuBarCapsuleView.showsRings(for: limits)
        hosting.rootView = MenuBarCapsuleView(priceText: priceText, limits: limits)
        let width = Self.capsuleWidth(for: priceText, showsRings: showsRings)
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
                await viewModel.loadLimits()
                await refreshTitle()
            }
        }
    }
}
