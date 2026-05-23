import SwiftUI
import AppKit
import GRDB

struct SettingsView: View {
    // GeneralTab props
    let configPath: String
    let dbPath: String
    let dbSizeBytes: Int64
    let version: String
    let onOpenConfig: () -> Void
    let onExport: () -> Void
    let onImport: () -> Void
    let onRefreshNow: () -> Void

    // AccountTab + FriendsTab dependencies
    @StateObject var accountViewModel: AccountTabViewModel
    @StateObject var friendsViewModel: FriendsTabViewModel

    var body: some View {
        TabView {
            GeneralTabView(
                configPath: configPath,
                dbPath: dbPath,
                dbSizeBytes: dbSizeBytes,
                version: version,
                onOpenConfig: onOpenConfig,
                onExport: onExport,
                onImport: onImport,
                onRefreshNow: onRefreshNow
            )
            .tabItem { Label("Общие", systemImage: "gear") }

            AccountTabView(viewModel: accountViewModel)
                .tabItem { Label("Аккаунт", systemImage: "person.crop.circle") }

            FriendsTabView(viewModel: friendsViewModel)
                .tabItem { Label("Друзья", systemImage: "person.2") }
        }
        .padding()
        .frame(width: 540, height: 480)
    }
}
