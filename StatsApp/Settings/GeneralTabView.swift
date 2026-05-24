import SwiftUI
import AppKit

struct GeneralTabView: View {
    let configPath: String
    let dbPath: String
    let dbSizeBytes: Int64
    let version: String
    let onOpenConfig: () -> Void
    let onExport: () -> Void
    let onImport: () -> Void
    let onRefreshNow: () -> Void

    /// Source-of-truth — SMAppService у системы. Toggle отражает её и обновляет
    /// после каждого toggle. Init читает изначальное состояние из системы.
    @State private var launchAtLogin: Bool = LaunchAtLoginService().isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section(NSLocalizedString("settings.config_file", comment: "")) {
                Text(configPath).font(.system(.body, design: .monospaced))
                Button(NSLocalizedString("settings.open_in_editor", comment: ""), action: onOpenConfig)
            }

            section(NSLocalizedString("settings.database", comment: "")) {
                Text(dbPath).font(.system(.body, design: .monospaced))
                Text(formatBytes(dbSizeBytes)).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(NSLocalizedString("settings.export", comment: ""), action: onExport)
                    Button(NSLocalizedString("settings.import", comment: ""), action: onImport)
                }
            }

            section(NSLocalizedString("settings.sync", comment: "")) {
                Button(NSLocalizedString("settings.refresh_now", comment: ""), action: onRefreshNow)
            }

            section(NSLocalizedString("settings.startup", comment: "")) {
                Toggle(NSLocalizedString("settings.launch_at_login", comment: ""), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }
                if let err = launchAtLoginError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            Spacer()
            Text("Burn \(version)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            try LaunchAtLoginService().setEnabled(enabled)
            // Подтягиваем актуальное состояние — система могла отказать (например
            // .requiresApproval) и реальное значение ≠ запрошенному.
            let actual = LaunchAtLoginService().isEnabled
            if actual != enabled {
                launchAtLogin = actual
                launchAtLoginError = NSLocalizedString("settings.launch_at_login.requires_approval", comment: "")
            }
        } catch {
            launchAtLogin = LaunchAtLoginService().isEnabled
            launchAtLoginError = error.localizedDescription
        }
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        return formatter.string(fromByteCount: bytes)
    }
}
