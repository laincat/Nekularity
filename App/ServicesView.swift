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
                Text("服务由 Core 校验、解包与记录；账号值由客户端保存，不会写进 Core。运行一个服务还需要宿主与账号，这一版尚未接入。")
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
        .confirmationDialog("允许这些权限并运行？", isPresented: Binding(
            get: { pendingRun != nil },
            set: { if !$0 { pendingRun = nil } }), presenting: pendingRun) { record in
            Button("允许并运行") {
                let granted = record.permissions ?? []
                let id = record.id
                pendingRun = nil
                Task { await services.call(record, method: "ping", granted: granted) }
                _ = id
            }
            Button("取消", role: .cancel) { pendingRun = nil }
        } message: { record in
            let names = (record.permissions ?? []).map(Self.permissionName)
            Text(names.isEmpty
                 ? "\(record.name) 不申请任何权限。这次运行会调用它的 ping。"
                 : "\(record.name) 申请：\(names.joined(separator: "、"))。这次运行只在这次调用期间允许这些权限，它仍然读不到账号值。")
        }
        .task { services.reload() }
        .refreshable { services.reload() }
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
            Button("运行") { pendingRun = record }.tint(.accentColor)
            Button("移除", role: .destructive) { pendingRemoval = record }
        }
        .contextMenu {
            Button {
                pendingRun = record
            } label: {
                Label("运行 ping", systemImage: "play")
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
