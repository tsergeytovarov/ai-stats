import SwiftUI

/// Вкладка «Аналитика» (спека 2.2): карточка советника за фикс-окно 30 дней.
/// Композирует `AnalyticsCard` (суммы/утечки/советы) и `ModelGuide` (шпаргалка).
/// Рендер — из дизайн-токенов; логика/загрузка живут во VM. Состояния «нет данных»/
/// «мало данных»/«утечек нет» — дословные тексты спеки 6.
struct DropdownAnalyticsSection: View {
    @ObservedObject var viewModel: DropdownViewModel

    var body: some View {
        Group {
            if let card = viewModel.analyticsCard {
                switch card.state {
                case .noData:
                    stateMessage(Self.noDataText)
                case .tooFewData:
                    stateMessage(Self.tooFewDataText)
                case .ready:
                    ready(card)
                }
            } else {
                // Первичная загрузка (карточка ещё не прочитана из БД).
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Разбираю историю агентов…")
                        .font(BrandFont.body)
                        .foregroundStyle(TextColor.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Ready

    @ViewBuilder
    private func ready(_ card: AnalyticsCard) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header(card)
                ForEach(card.sources, id: \.source) { sourceBlock($0) }
                leaks(card)
                guide()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private func header(_ card: AnalyticsCard) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Crumb(category: .ai, title: "Аналитика", period: "30 дней")
            Text("За последние 30 дней")
                .font(BrandFont.unitL)
                .foregroundStyle(TextColor.primary)
            Text("\(Self.dayMonth(card.rangeStart)) — \(Self.dayMonth(card.rangeEnd))")
                .font(BrandFont.caption)
                .foregroundStyle(TextColor.muted)
        }
    }

    // MARK: - Per source

    private func sourceBlock(_ s: AnalyticsCard.SourceSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(s.displayName)
                .font(BrandFont.lbl)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(BrandColor.cyanLight.opacity(0.7))

            HStack(spacing: 8) {
                Text(AnalyticsFormat.tokens(s.tokens))
                Text("·").foregroundStyle(TextColor.muted)
                Text(MoneyFormatter.widget(s.costUsd))
            }
            .font(BrandFont.body)
            .foregroundStyle(TextColor.secondary)

            if let avgWeek = s.avgWeekLimitPct {
                Text("в среднем ≈\(Self.intPct(avgWeek))%/нед лимита")
                    .font(BrandFont.caption)
                    .foregroundStyle(TextColor.muted)
            }

            // Строка утечки источника — только если у источника был расход.
            if let leakPct = s.leakPct {
                Text(Self.leakLine(leakPct: leakPct, expSaved: s.expSavedUsd, avgWeek: s.avgWeekLimitPct))
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.pinkLight)
            }
        }
    }

    // MARK: - Leaks

    @ViewBuilder
    private func leaks(_ card: AnalyticsCard) -> some View {
        Text("ГЛАВНЫЕ УТЕЧКИ И ЧТО ДЕЛАТЬ")
            .font(BrandFont.lbl)
            .tracking(1.2)
            .foregroundStyle(BrandColor.cyanLight.opacity(0.7))

        if card.leaks.isEmpty {
            Text(Self.noLeaksText)
                .font(BrandFont.body)
                .foregroundStyle(TextColor.secondary)
        } else {
            ForEach(card.leaks, id: \.key) { leak in
                VStack(alignment: .leading, spacing: 2) {
                    Text(leak.title)
                        .font(BrandFont.body)
                        .foregroundStyle(TextColor.primary)
                    Text("\(leak.nTurns) ходов на \(leak.model) · ≈\(MoneyFormatter.widget(leak.expSavedUsd))/мес")
                        .font(BrandFont.caption)
                        .foregroundStyle(TextColor.muted)
                    Text(leak.adviceText)
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.cyanLight.opacity(0.85))
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Шпаргалка

    @ViewBuilder
    private func guide() -> some View {
        if let guide = viewModel.modelGuide, !(guide.codex.isEmpty && guide.claude.isEmpty) {
            Text("ШПАРГАЛКА: КАКУЮ МОДЕЛЬ КОГДА")
                .font(BrandFont.lbl)
                .tracking(1.2)
                .foregroundStyle(BrandColor.cyanLight.opacity(0.7))

            if !guide.codex.isEmpty {
                guideGroup(title: "Codex", entries: guide.codex)
            }
            if !guide.claude.isEmpty {
                guideGroup(title: "Claude", entries: guide.claude)
            }
        }
    }

    private func guideGroup(title: String, entries: [ModelGuide.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(BrandFont.caption)
                .foregroundStyle(TextColor.secondary)
            // Grid: колонка слагов авто-выравнивается по самому длинному,
            // описания встают в ровную левую колонку и переносятся внутри неё.
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 5) {
                ForEach(entries, id: \.slug) { e in
                    GridRow {
                        Text(e.slug)
                            .font(BrandFont.caption)
                            .foregroundStyle(BrandColor.pinkLight)
                            .gridColumnAlignment(.leading)
                        Text(e.description)
                            .font(BrandFont.caption)
                            .foregroundStyle(TextColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - States

    private func stateMessage(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Crumb(category: .ai, title: "Аналитика", period: "30 дней")
            Text(text)
                .font(BrandFont.body)
                .foregroundStyle(TextColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Тексты состояний (дословно, спека 6)

    static let noDataText = "Пока нечего анализировать. Burn читает историю Claude Code и Codex локально — поработай с агентами несколько дней, карточка соберётся сама."
    static let tooFewDataText = "Мало данных для выводов — карточка появится, когда наберётся история."
    static let noLeaksText = "Утечек не видно: модели подобраны по задачам."

    // MARK: - Форматтеры

    /// «Утекает ≈9% объёма = $168/мес». Пересчёт в п.п. недельного лимита убран:
    /// путал и был только у Codex (у Claude лимит локально не виден), а средний
    /// недельный лимит уже показан отдельной строкой выше.
    static func leakLine(leakPct: Double, expSaved: Double, avgWeek: Double?) -> String {
        "Утекает ≈\(intPct(leakPct))% объёма = \(MoneyFormatter.widget(expSaved))/мес"
    }

    static func intPct(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    static func dayMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM"
        f.locale = Locale(identifier: "ru_RU")
        return f.string(from: date)
    }
}
