import SwiftUI
import NekularityKit

/// The switches a provider plugin declares, and the user's choices.
///
/// A change is written down and pushed to the package at once: the plugin reads
/// its options through `input.magpie.option`, so a value that only lives in the
/// screen would look applied until the next request, which is exactly when it
/// matters.
struct MagpieOptionsView: View {
    let accounts: MagpieAccounts
    let provider: String
    let providerName: String

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [MagpieOptionStore.Resolved] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    Section { ProgressView("正在读取插件开关…") }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows, id: \.key) { option in
                            Toggle(isOn: Binding(
                                get: { option.value },
                                set: { change(option, to: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                    if !option.description.isEmpty {
                                        Text(option.description)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } footer: {
                        Text("这些开关由插件自己声明,只影响 \(providerName),不会串到别家。")
                    }
                } else if !loading && error == nil {
                    Section { Text("这个插件没有声明开关。").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("\(providerName) 开关")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .task { load() }
        }
    }

    private func load() {
        loading = true
        Task {
            defer { loading = false }
            do {
                guard let store = accounts.options else {
                    throw MagpieError("没有配置开关的保存位置")
                }
                let spec = try accounts.runner(for: provider).auth(provider: provider)
                rows = try store.resolve(spec?.options ?? [], provider: provider)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func change(_ option: MagpieOptionStore.Resolved, to value: Bool) {
        do {
            guard let store = accounts.options else { return }
            try store.set(provider: provider, key: option.key, value: value)
            try accounts.runner(for: provider).setOptions(try store.optionsJSON(provider: provider))
            rows = try store.resolve(rows.map {
                MagpieAuthSpec.Option(key: $0.key, label: $0.label, description: $0.description,
                                      confirm: $0.confirm, default: $0.value)
            }, provider: provider)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
