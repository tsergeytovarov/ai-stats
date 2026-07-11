import SwiftUI

struct DropdownView: View {
    @ObservedObject var viewModel: DropdownViewModel
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                content
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                Spacer(minLength: 0)

                Divider().background(SurfaceColor.dividerSubtle).padding(.horizontal, 18)

                HStack {
                    Text(String(format: NSLocalizedString("footer.last_sync %@", comment: ""),
                                viewModel.lastSyncDescription))
                        .font(BrandFont.caption)
                        .foregroundStyle(TextColor.muted)
                    Spacer()
                    SyncIconButton(systemImage: "arrow.clockwise", action: onRefresh)
                    SyncIconButton(systemImage: "gearshape", action: onOpenSettings)
                    SyncIconButton(systemImage: "power", action: onQuit)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, BrandSpacing.islandClearance)
            }
            .frame(width: 400, height: 560, alignment: .topLeading)
            .brandSurface()

            FloatingIsland(section: $viewModel.section, period: $viewModel.period)
                .padding(.bottom, BrandSpacing.islandBottomOffset)
        }
        .frame(width: 400, height: 560)
        .onChange(of: viewModel.section) { _, newValue in
            if newValue == .analytics {
                Task { await viewModel.loadAnalytics() }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.section {
        case .expenses:
            DropdownAISection(viewModel: viewModel)
        case .analytics:
            DropdownAnalyticsSection(viewModel: viewModel)
        }
    }
}
