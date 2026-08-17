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
        recentProjects = Array(
            NSDocumentController.shared.recentDocumentURLs
                .filter { FileManager.default.fileExists(atPath: $0.path) }
                .prefix(6)
        )
    }
}
