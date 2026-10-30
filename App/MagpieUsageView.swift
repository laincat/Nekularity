import SwiftUI
import NekularityKit

/// An account's quota windows, as its plugin reported them.
///
/// A window with no share shows the vendor's own words instead of a bar: drawing
/// 0% would say "plenty left" when the truth is "this vendor doesn't say".
struct MagpieUsageView: View {
    let accounts: MagpieAccounts
    let provider: String
    let providerName: String

    @Environment(\.dismiss) private var dismiss
    @State private var usage: MagpieUsage?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    Section { ProgressView("正在读取用量…") }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if let usage {
                    if !usage.plan.isEmpty || !usage.user.isEmpty {
                        Section {
                            LabeledContent("套餐", value: usage.plan.isEmpty ? "未报告" : usage.plan)
                            if !usage.user.isEmpty {
                                LabeledContent("账号", value: usage.user)
                            }
                        }
                    }
                    if !usage.windows.isEmpty {
                        Section("用量") {
                            ForEach(usage.windows) { window in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(window.name.isEmpty ? "额度" : window.name)
                                        Spacer()
                                        Text(window.summary).foregroundStyle(.secondary)
                                    }
                                    // A share can be drawn; a count or a wallet cannot
                                    // without inventing a total it never gave.
                                    if let used = window.used {
                                        ProgressView(value: min(max(used, 0), 100), total: 100)
                                    }
                                    if !window.resetsAt.isEmpty {
                                        Text("重置于 \(window.resetsAt)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if !usage.error.isEmpty {
                        Section { Text(usage.error).font(.footnote).foregroundStyle(.secondary) }
                    }
                } else if !loading && error == nil {
                    Section { Text("这个插件没有报告用量。").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("\(providerName) 用量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            usage = try await Task.detached { [accounts, provider] in
                try accounts.runner(for: provider).usageReport(provider: provider)
            }.value
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
