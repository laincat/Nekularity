import NekularityKit
import SwiftUI

/// The account values one service may read.
///
/// A service that asks for `secrets` reads what is entered here and nothing
/// else: the values live in this device's Keychain, never in Core, and they are
/// only passed for the duration of one call. Values are never shown again after
/// they are saved; a key can be replaced or deleted.
struct ServiceAccountsView: View {
    let record: ServiceRecord
    @Environment(ServiceStore.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var keys: [String] = []
    @State private var key = ""
    @State private var value = ""
    @State private var problem: String?
    @State private var notice: String?

    private var wantsSecrets: Bool {
        (record.permissions ?? []).contains("secrets")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if keys.isEmpty {
                        Text("还没有账号值。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(keys, id: \.self) { name in
                            HStack {
                                Text(name).font(.system(.body, design: .monospaced))
                                Spacer()
                                Text("已保存").font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityIdentifier("service.account.\(name)")
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                let name = keys[index]
                                do {
                                    try services.accounts.remove(service: record.id, key: name)
                                    notice = "已删除 \(name)"
                                } catch {
                                    problem = error.localizedDescription
                                }
                            }
                            reload()
                        }
                    }
                } header: {
                    Text("已保存的键")
                } footer: {
                    Text(wantsSecrets
                         ? "\(record.name) 申请了「读取账号值」，运行时会读到这里保存的值。值保存后不再显示。"
                         : "\(record.name) 没有申请「读取账号值」，这里保存的值它读不到。")
                }

                Section("添加或替换") {
                    TextField("键，例如 token", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("service.account.key")
                    SecureField("值", text: $value)
                        .accessibilityIdentifier("service.account.value")
                    Button("保存") { save() }
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty
                                  || value.isEmpty)
                        .accessibilityIdentifier("service.account.save")
                }

                if let problem {
                    Section {
                        Text(problem).font(.footnote).foregroundStyle(.red)
                    }
                }
                if let notice {
                    Section {
                        Text(notice).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("账号值")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        keys = services.accounts.keys(service: record.id)
    }

    private func save() {
        let name = key.trimmingCharacters(in: .whitespaces)
        do {
            try services.accounts.set(service: record.id, key: name, value: value)
            notice = "已保存 \(name)"
            problem = nil
            key = ""
            value = ""
            reload()
        } catch {
            problem = error.localizedDescription
        }
    }
}
