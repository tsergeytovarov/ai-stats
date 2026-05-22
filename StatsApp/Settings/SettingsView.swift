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
            Text("Settings").font(.title2).bold()

            section("Config file") {
                Text(configPath).font(.system(.body, design: .monospaced))
                Button("Open in editor", action: onOpenConfig)
            }

            section("Database") {
                Text(dbPath).font(.system(.body, design: .monospaced))
                Text(formatBytes(dbSizeBytes)).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Export…", action: onExport)
                    Button("Import…", action: onImport)
                }
            }

            section("Sync") {
                Button("Refresh now", action: onRefreshNow)
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
