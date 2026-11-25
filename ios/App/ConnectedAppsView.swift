// Connected apps, using the same catalog and connection inventory as the
// desktop's Apps panel. The phone can start an authorization and reports the
// same accounts the computer knows about; credentials stay on the computer.
import SwiftUI
import CompanionCore

struct ConnectedAppsView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var catalog: ConnectorCatalog?
    @State private var services: [String: ConnectorServiceStatus] = [:]
    @State private var query = ""
    @State private var loading = true
    @State private var connectingSlug: String?
    @State private var problem: String?

    var body: some View {
        List {
            if loading, catalog == nil {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("正在读取应用…")
                        Spacer()
                    }
                    .padding(.vertical, 28)
                }
            } else if let catalog, catalog.configured == false {
                Section {
                    ContentUnavailableView {
                        Label("连接应用尚未就绪", systemImage: "app.badge")
                    } description: {
                        Text("请先在电脑上的 OpenMausBot → Apps 完成应用连接服务设置。")
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if !connectedApps.isEmpty {
                    Section("已连接") {
                        ForEach(connectedApps) { app in
                            ConnectedAppRow(
                                app: app,
                                status: services[app.slug],
                                busy: connectingSlug == app.slug,
                                connect: { connect(app) }
                            )
                        }
                    }
                }

                Section {
                    if availableApps.isEmpty {
                        ContentUnavailableView(
                            query.isEmpty ? "没有可连接的应用" : "没有匹配结果",
                            systemImage: query.isEmpty ? "square.grid.2x2" : "magnifyingglass",
                            description: Text(
                                query.isEmpty
                                    ? "电脑端还没有可用的应用目录。"
                                    : "没有与“\(query)”匹配的应用。"
                            )
                        )
                    } else {
                        ForEach(availableApps) { app in
                            ConnectedAppRow(
                                app: app,
                                status: services[app.slug],
                                busy: connectingSlug == app.slug,
                                connect: { connect(app) }
                            )
                        }
                    }
                } header: {
                    Text("可连接")
                } footer: {
                    Text("授权完成后回到这里，应用会刷新为已连接。账号与凭据只保存在电脑上。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("连接应用")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索应用")
        .refreshable { await load() }
        .task {
            if catalog == nil { await load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, catalog != nil {
                Task { await load(showLoading: false) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
    }

    private var matchingApps: [ConnectorApp] {
        guard let cards = catalog?.cards else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cards }
        return cards.filter { app in
            [app.label, app.slug, app.blurb, app.domain ?? "", (app.categories ?? []).joined(separator: " ")]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var connectedApps: [ConnectorApp] {
        matchingApps
            .filter { services[$0.slug]?.isConnected == true || services[$0.slug]?.isPending == true }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private var availableApps: [ConnectorApp] {
        matchingApps
            .filter {
                let state = services[$0.slug]
                return state?.isConnected != true && state?.isPending != true
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    @MainActor
    private func load(showLoading: Bool = true) async {
        if showLoading { loading = true }
        defer { loading = false }
        do {
            let nextCatalog = try await session.connectorCatalog()
            let inventory = try await session.connectedApps()
            catalog = nextCatalog
            services = inventory.services
            problem = inventory.credentialStore == "unavailable"
                ? "电脑暂时无法读取已连接应用。"
                : nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func connect(_ app: ConnectorApp) {
        guard connectingSlug == nil else { return }
        connectingSlug = app.slug
        problem = nil
        Task {
            defer { connectingSlug = nil }
            do {
                let authorization = try await session.authorizeConnector(slug: app.slug)
                guard let url = URL(string: authorization.url),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "https" || scheme == "http"
                else {
                    problem = "电脑返回的授权地址无法打开。"
                    return
                }
                openURL(url)
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}

private struct ConnectedAppRow: View {
    let app: ConnectorApp
    let status: ConnectorServiceStatus?
    let busy: Bool
    let connect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConnectorAppIcon(app: app)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            if busy {
                ProgressView()
                    .controlSize(.small)
            } else if status?.isConnected == true {
                Label("已连接", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else if status?.isPending == true {
                Text("等待授权")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("连接", action: connect)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 3)
    }

    private var detail: String {
        if let accounts = status?.accounts, !accounts.isEmpty {
            let names = accounts.map { $0.alias?.isEmpty == false ? $0.alias! : app.label }
            return names.joined(separator: "、")
        }
        return app.blurb.isEmpty ? app.slug : app.blurb
    }
}

private struct ConnectorAppIcon: View {
    let app: ConnectorApp

    var body: some View {
        AsyncImage(url: imageURL) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                fallback
            }
        }
        .frame(width: 42, height: 42)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var imageURL: URL? {
        if let logo = app.logo, !logo.isEmpty, let url = URL(string: logo) {
            return url
        }
        if let domain = app.domain, !domain.isEmpty,
           let encoded = domain.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: "https://www.google.com/s2/favicons?domain=\(encoded)&sz=64")
        }
        return nil
    }

    private var fallback: some View {
        Text(String(app.label.prefix(1)).uppercased())
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
