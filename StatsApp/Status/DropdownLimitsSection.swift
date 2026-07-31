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

    /// Ширина полоски фиксирована намеренно. Раньше полоска была единственным
    /// резиновым элементом строки и забирала остаток после хвоста со временем
    /// сброса, а хвост у каждой строки своей длины («сброс через 4д 12ч» против
    /// «сброс через 27д 5ч»). Из-за этого полоски начинались и кончались на
    /// разных местах и не складывались в колонку. Теперь резиновый — хвост.
    static let barWidth: CGFloat = 110

    /// Заполненная часть полоски. Процент клампим: сервер теоретически может
    /// прислать больше сотни (перерасход квоты), и тогда заливка вылезла бы
    /// за пределы дорожки.
    static func fillWidth(percent: Double, barWidth: CGFloat = barWidth) -> CGFloat {
        barWidth * min(max(percent, 0), 100) / 100
    }

    private func windowRow(_ window: LimitWindow, provider: LimitProvider) -> some View {
        HStack(spacing: 8) {
            Text(LimitFormat.window(minutes: window.windowMinutes))
                .font(BrandFont.caption)
                .foregroundStyle(TextColor.secondary)
                .frame(width: 62, alignment: .leading)

            ZStack(alignment: .leading) {
                Capsule().fill(LimitRingPalette.trackColor)
                // Цвет — фирменный цвет провайдера, тот же что у его кольца
                // в капсуле. Полоска и кольцо обязаны читаться как одно и то
                // же, иначе связь между меню-баром и попапом теряется.
                Capsule()
                    .fill(LimitRingPalette.color(for: provider))
                    .frame(width: Self.fillWidth(percent: window.usedPercent))
            }
            .frame(width: Self.barWidth, height: 5)

            Text(LimitFormat.percent(window.usedPercent))
                .font(BrandFont.caption)
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)

            Text(LimitFormat.resetsIn(window.resetsAt, now: now) ?? "")
                .font(BrandFont.caption)
                .foregroundStyle(TextColor.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
