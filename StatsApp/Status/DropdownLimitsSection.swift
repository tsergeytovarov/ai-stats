import SwiftUI

/// Секция «Лимиты» на вкладке «Расходы»: по строке на провайдера, внутри —
/// полоска на каждое окно.
struct DropdownLimitsSection: View {
    let limits: [LimitProvider: ProviderLimits]
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ЛИМИТЫ")
                .font(BrandFont.lbl)
                .tracking(1.2)
                .foregroundStyle(BrandColor.cyanLight.opacity(0.7))

            ForEach(LimitProvider.allCases, id: \.self) { provider in
                providerRow(provider, limits: limits[provider])
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: LimitProvider, limits: ProviderLimits?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(provider.displayTitle)
                    .font(BrandFont.body)
                Spacer()
                Text(LimitFormat.fetchedAt(limits?.fetchedAt, status: limits?.status ?? .ok))
                    .font(BrandFont.caption)
                    // ok — обычный приглушённый лейбл; stale/throttled — заметно
                    // приглушённее, чтобы не сливаться со свежими данными
                    // (спека §9, находка 5 финального ревью).
                    .foregroundStyle((limits?.status ?? .ok) == .ok ? TextColor.secondary : TextColor.muted)
            }

            if let action = limits.flatMap({ LimitFormat.actionText(for: provider, status: $0.status) }) {
                Text(action)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.danger.opacity(0.9))
            } else if let windows = limits?.windows, !windows.isEmpty {
                ForEach(windows.sorted { $0.windowMinutes < $1.windowMinutes }, id: \.windowMinutes) { window in
                    windowRow(window, provider: provider)
                }
            } else {
                Text("нет данных")
                    .font(BrandFont.caption)
                    .foregroundStyle(TextColor.muted)
            }

            // 429: прошлые цифры выше уже показаны (если были) — здесь только
            // время следующей попытки (спека §9, находка 6 финального ревью).
            if limits?.status == .throttled,
               let retryText = LimitFormat.retryAfterText(limits?.retryAfter, now: now) {
                Text(retryText)
                    .font(BrandFont.caption)
                    .foregroundStyle(TextColor.muted)
            }
        }
        .padding(.vertical, 2)
    }

    private func windowRow(_ window: LimitWindow, provider: LimitProvider) -> some View {
        HStack(spacing: 8) {
            Text(LimitFormat.window(minutes: window.windowMinutes))
                .font(BrandFont.caption)
                .foregroundStyle(TextColor.secondary)
                .frame(width: 62, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(LimitRingPalette.trackColor)
                    // Полоска окна красится по СВОЕМУ проценту, в отличие от кольца:
                    // здесь видно все окна сразу, подменять цвет худшим незачем.
                    Capsule()
                        .fill(LimitRingPalette.color(
                            for: provider,
                            severity: LimitThresholds.severity(worstPercent: window.usedPercent)))
                        .frame(width: geo.size.width * window.usedPercent / 100)
                }
            }
            .frame(height: 5)

            Text(LimitFormat.percent(window.usedPercent))
                .font(BrandFont.caption)
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)

            if let reset = LimitFormat.resetsIn(window.resetsAt, now: now) {
                Text(reset)
                    .font(BrandFont.caption)
                    .foregroundStyle(TextColor.muted)
            }
        }
    }
}
