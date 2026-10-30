import SwiftUI
import NekularityKit

/// The provider list: what is installed on this device, who is signed in, and
/// the way in for a package the user has on disk.
///
/// Nothing here talks to a comic source. These accounts and their packages are
/// separate, which is why they live in their own screen instead of inside a
/// source's settings.
struct MagpieProvidersView: View {
    let accounts: MagpieAccounts

    @State private var rows: [MagpieProviderRow] = []
    @State private var picking = false
    @State private var busy = false
    @State private var error: String?
    @State private var signingIn: MagpieProviderRow?

    var body: some View {
        List {
            if rows.isEmpty {
                Section {
                    Text("还没有安装任何供应商插件。")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("供应商插件是一个文件夹(含 package.json)。登录与用量都只在这台设备上使用这家供应商自己的授权。")
                }
            } else {
                Section("已安装") {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.name)
                                Spacer()
                                Text(row.signedIn ? "已登录" : "未登录")
                                    .font(.footnote)
                                    .foregroundStyle(row.signedIn ? .green : .secondary)
                            }
                            if !row.version.isEmpty {
                                Text("版本 \(row.version)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                if row.hasSignIn {
                                    Button(row.signedIn ? "重新登录" : "登录") {
                                        signingIn = row
                                    }
                                    .buttonStyle(.borderless)
                                }
                                if row.signedIn {
                                    Button("退出登录", role: .destructive) {
                                        perform { try accounts.signOut(provider: row.provider) }
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Spacer()
                                Button("卸载", role: .destructive) {
                                    perform { try accounts.remove(provider: row.provider) }
                                }
                                .buttonStyle(.borderless)
                            }
                            .font(.footnote)
                        }
                    }
                }
            }

            Section {
                Button {
                    picking = true
                } label: {
                    Label("从文件夹安装插件…", systemImage: "folder.badge.plus")
                }
                .disabled(busy)
            }
        }
        .navigationTitle("AI 供应商")
        .overlay { if busy { ProgressView() } }
        .sheet(item: $signingIn) { row in
            MagpieSignInView(
                accounts: accounts,
                provider: row.provider,
                providerName: row.name.isEmpty ? row.provider : row.name,
                onSignedIn: { reload() }
            )
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                perform {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    _ = try accounts.install(folder: url)
                }
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
        .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task { reload() }
    }

    private func reload() {
        do { rows = try accounts.rows() } catch { self.error = error.localizedDescription }
    }

    private func perform(_ work: @escaping () throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try work()
                reload()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

}
