import NekularityKit
import SwiftUI
import UniformTypeIdentifiers

/// Installed service packages: what Core holds, what each one asks for, and a
/// way to add or remove one.
///
/// This is the first screen behind `CoreService`. It deliberately does not run a
/// service: running one needs this client's transport and its account values,
/// and nothing here has been given those yet.
struct ServicesView: View {
    @Environment(ServiceStore.self) private var services
    @State private var importing = false
    @State private var pendingRemoval: ServiceRecord?
    /// The package whose permissions the user is about to allow for one run.
    @State private var pendingRun: ServiceRecord?
    /// The package whose account values are being edited.
    @State private var accountsFor: ServiceRecord?
    @State private var accessFor: ServiceRecord?

    var body: some View {
        List {
            if let run = services.run {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(run.id) · \(run.method)").font(.caption).foregroundStyle(.secondary)
                        Text(run.text).font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(run.ok ? .primary : Color.red)
                    }
                    .accessibilityIdentifier("service.run.result")
                } header: {
                    Text(run.ok ? "运行结果" : "运行失败")
                }
            }
            if let error = services.error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            Section {
                if services.records.isEmpty {
                    ContentUnavailableView("还没有服务", systemImage: "shippingbox",
                                           description: Text("服务包是一个 zip，装着 service.json 与它指向的代码。"))
                } else {
                    ForEach(services.records) { record in
                        row(record)
                    }
                }
            } header: {
                Text("已安装")
            } footer: {
                Text("可在服务包的菜单里管理账号值与内置功能授权。")
            }
        }
        .navigationTitle("服务")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importing = true
                } label: {
                    Label("导入服务包", systemImage: "plus")
                }
                .disabled(services.installing)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await services.install(from: url) }
        }
        .confirmationDialog("移除这个服务包？", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }), presenting: pendingRemoval) { record in
            Button("移除", role: .destructive) {
                services.remove(record.id)
                pendingRemoval = nil
            }
            Button("取消", role: .cancel) { pendingRemoval = nil }
        } message: { record in
            Text("\(record.name) 的代码会从这台设备删除；它保存的账号值不在这里。")
        }
        .overlay {
            if services.installing { ProgressView("正在安装…") }
        }
        .sheet(item: $pendingRun) { record in
            ServiceRunSheet(record: record, methods: services.offeredMethods(for: record.id))
        }
        .sheet(item: $accountsFor) { record in
            ServiceAccountsView(record: record)
        }
        .confirmationDialog("允许内置功能调用服务包？", isPresented: Binding(
            get: { accessFor != nil },
            set: { if !$0 { accessFor = nil } }), presenting: accessFor) { record in
            Button("允许") { services.setStructuredAccess(true, for: record) }
            Button("撤销授权", role: .destructive) { services.setStructuredAccess(false, for: record) }
        } message: { record in
            Text("\(record.name) 可经由宿主访问网络，并读取为这个包保存的账号值。授权只适用于当前包版本。")
        }
        .task { services.reload() }
        .refreshable { services.reload() }
    }

    /// Describes the package first, then asks for the permission it needs.
    private func askToRun(_ record: ServiceRecord) {
        Task {
            await services.describe(record)
            pendingRun = record
        }
    }

    @ViewBuilder
    private func row(_ record: ServiceRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.name).font(.headline)
                Spacer()
                Text(record.version).font(.footnote).foregroundStyle(.secondary)
            }
            Text(record.id).font(.caption).foregroundStyle(.secondary)
            if let permissions = record.permissions, !permissions.isEmpty {
                Text(permissions.map(Self.permissionName).joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("不申请任何权限").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("service.\(record.id)")
        .swipeActions {
            Button("运行") { askToRun(record) }.tint(.accentColor)
            Button("移除", role: .destructive) { pendingRemoval = record }
        }
        .contextMenu {
            Button {
                askToRun(record)
            } label: {
                Label("运行…", systemImage: "play")
            }
            Button {
                accountsFor = record
            } label: {
                Label("账号值…", systemImage: "key")
            }
            if [KnownServiceID.bangumi, KnownServiceID.tmdb, KnownServiceID.trakt].contains(record.id) {
                Button {
                    accessFor = record
                } label: {
                    Label("内置功能授权…", systemImage: "checkmark.shield")
                }
            }
        }
    }

    /// The names a person can act on, rather than the identifiers Core stores.
    private static func permissionName(_ permission: String) -> String {
        switch permission {
        case "network": return "网络（经宿主）"
        case "storage": return "本地小数据"
        case "secrets": return "读取账号值"
        default: return permission
        }
    }
}
