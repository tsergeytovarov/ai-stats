import SwiftUI
import AppKit

struct SettingsView: View {
    let configPath: String
    let dbPath: String
    let dbSizeBytes: Int64
    let version: String
    let onOpenConfig: () -> Void
    let onExport: () -> Void
    let onImport: () -> Void
    let onRefreshNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.title").font(.title2).bold()

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

            Spacer()
            Text("ai-stats \(version)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 460, height: 360)
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
