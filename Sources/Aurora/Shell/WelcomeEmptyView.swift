import AuroraDesignSystem
import AppKit
import AuroraUI
import SwiftUI

/// Restrained empty / no-show surface (UI-02G / C6D brand fidelity).
struct WelcomeEmptyView: View {
    var onNew: () -> Void
    var onOpen: () -> Void
    var onDemo: () -> Void
    var onOpenRecent: (URL) -> Void

    @State private var recentProjects: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            // Brand stack: mark + full wordmark image (welcome is a brand surface).
            VStack(spacing: 18) {
                PrismMarkView(size: 56, showsGlow: true)
                PrismWordmarkView(height: 32)
                Text(PrismBrandCopy.productLine)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(3.2)
                    .foregroundStyle(AuroraColor.textTertiary)
                Text(PrismBrandCopy.welcomeDetail)
                    .font(AuroraTypography.secondary)
                    .foregroundStyle(AuroraColor.textSecondary)
                    .padding(.top, 2)
            }

            HStack(spacing: AuroraSpacing.md) {
                AuroraButton("New Show", kind: .secondary, action: onNew)
                AuroraButton("Open…", kind: .secondary, action: onOpen)
                AuroraButton("Open Demo Show", kind: .primary, action: onDemo)
            }
            .padding(.top, 36)

            if !recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECENT PROJECTS")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(AuroraColor.textTertiary)
                        .padding(.horizontal, 10)

                    VStack(spacing: 2) {
                        ForEach(recentProjects, id: \.self) { url in
                            Button {
                                onOpenRecent(url)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AuroraColor.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(url.deletingPathExtension().lastPathComponent)
                                            .font(AuroraTypography.secondary)
                                            .foregroundStyle(AuroraColor.textPrimary)
                                            .lineLimit(1)
                                        Text(url.deletingLastPathComponent().path)
                                            .font(.system(size: 10))
                                            .foregroundStyle(AuroraColor.textTertiary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer(minLength: 20)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AuroraColor.textTertiary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open recent project \(url.lastPathComponent)")
                        }
                    }
                }
                .frame(maxWidth: 460)
                .padding(.top, 30)
            }

            Spacer(minLength: 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                AuroraColor.surfaceBase
                RadialGradient(
                    colors: [
                        AuroraColor.accent.opacity(0.06),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.5, y: 0.38),
                    startRadius: 20,
                    endRadius: 320
                )
                .blendMode(.plusLighter)
            }
        )
        .onAppear(perform: refreshRecentProjects)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome")
    }

    private func refreshRecentProjects() {
        recentProjects = Array(RecentProjectStore.urls().prefix(6))
    }
}

/// App-owned recent-project history. `NSDocumentController.recentDocumentURLs` is not a
/// reliable launch-time data source for this non-NSDocument app, and plain paths lose
/// sandbox access across launches. Persisting security-scoped bookmarks makes both the
/// welcome list and opening an entry deterministic.
enum RecentProjectStore {
    private struct Entry: Codable {
        var path: String
        var bookmark: Data?
        var lastOpened: Date
    }

    private static let defaultsKey = "prism.recent-projects.v1"
    private static let maximumEntryCount = 12

    static func note(_ url: URL, defaults: UserDefaults = .standard) {
        let normalizedURL = url.standardizedFileURL
        let bookmark = try? normalizedURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var entries = load(from: defaults)
        entries.removeAll { URL(fileURLWithPath: $0.path).standardizedFileURL == normalizedURL }
        entries.insert(
            Entry(path: normalizedURL.path, bookmark: bookmark, lastOpened: Date()),
            at: 0
        )
        save(Array(entries.prefix(maximumEntryCount)), to: defaults)
    }

    static func urls(defaults: UserDefaults = .standard) -> [URL] {
        var entries = load(from: defaults)

        // Migrate the system list once for users upgrading from the original welcome UI.
        if entries.isEmpty {
            for url in NSDocumentController.shared.recentDocumentURLs.reversed() {
                note(url, defaults: defaults)
            }
            entries = load(from: defaults)
        }

        var changed = false
        var resolved: [URL] = []
        resolved.reserveCapacity(entries.count)
        for index in entries.indices {
            let entry = entries[index]
            guard let bookmark = entry.bookmark else {
                resolved.append(URL(fileURLWithPath: entry.path))
                continue
            }

            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                resolved.append(URL(fileURLWithPath: entry.path))
                continue
            }

            if stale,
               let refreshed = try? url.bookmarkData(
                   options: .withSecurityScope,
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ) {
                entries[index].bookmark = refreshed
                entries[index].path = url.standardizedFileURL.path
                changed = true
            }
            resolved.append(url)
        }

        if changed { save(entries, to: defaults) }
        return resolved
    }

    private static func load(from defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func save(_ entries: [Entry], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
