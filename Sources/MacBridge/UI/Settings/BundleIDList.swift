import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Editable exclude-apps list: show current bundleIDs (with icon + display
/// name resolved via LaunchServices) + Add (NSOpenPanel) + per-row Remove.
struct BundleIDListView: View {
    @Binding var bundleIDs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if bundleIDs.isEmpty {
                Text("No apps excluded — this rule fires everywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bundleIDs, id: \.self) { id in
                    BundleRow(bundleID: id) {
                        bundleIDs.removeAll { $0 == id }
                    }
                }
            }
            Button {
                pickApp()
            } label: {
                Label("Add app…", systemImage: "plus.circle")
            }
            .padding(.top, 2)
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Pick an app to exclude from this rule"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        if !bundleIDs.contains(id) {
            bundleIDs.append(id)
        }
    }
}

private struct BundleRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            let info = AppInfoCache.shared.info(for: bundleID)
            if let icon = info.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(info.displayName ?? bundleID)
                    .lineLimit(1)
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

/// Tiny cache so repeatedly-rendered rows don't re-query LaunchServices /
/// re-load icons on every redraw. In-memory only, lives for the session.
private final class AppInfoCache {
    static let shared = AppInfoCache()

    struct Info {
        let displayName: String?
        let icon: NSImage?
    }

    private var cache: [String: Info] = [:]

    func info(for bundleID: String) -> Info {
        if let hit = cache[bundleID] { return hit }
        let resolved = lookup(bundleID)
        cache[bundleID] = resolved
        return resolved
    }

    private func lookup(_ bundleID: String) -> Info {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return Info(displayName: nil, icon: nil)
        }
        let name = (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? FileManager.default.displayName(atPath: url.path)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 20, height: 20)
        return Info(displayName: name, icon: icon)
    }
}
