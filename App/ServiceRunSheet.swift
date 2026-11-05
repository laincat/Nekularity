import NekularityKit
import SwiftUI

/// Runs one method of an installed service.
///
/// The methods are what the package says it offers; a package that does not
/// describe itself still answers `ping`, so that stays as one honest fallback.
/// The payload is JSON and is sent as written: Core refuses text that is not
/// JSON rather than guessing, and the permissions listed are the ones granted
/// for this call only.
struct ServiceRunSheet: View {
    let record: ServiceRecord
    let methods: [ServiceMethod]
    @Environment(ServiceStore.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var method = ""
    @State private var payload = "null"
    @State private var problem: String?

    private var offered: [ServiceMethod] {
        methods.isEmpty ? [ServiceMethod(name: "ping", title: nil)] : methods
    }

    private var granted: [String] {
        record.permissions ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("方法") {
                    Picker("方法", selection: $method) {
                        ForEach(offered) { method in
                            Text(method.label).tag(method.name)
                        }
                    }
                    .accessibilityIdentifier("service.run.method")
                }

                Section {
                    TextEditor(text: $payload)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 96)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("service.run.payload")
                } header: {
                    Text("参数（JSON）")
                } footer: {
                    Text("原样发送。Core 不接受非 JSON 文本，也不会替你补全。")
                }

                Section {
                    let names = granted.map(Self.permissionName)
                    Text(names.isEmpty
                         ? "\(record.name) 不申请任何权限。"
                         : "\(record.name) 申请：\(names.joined(separator: "、"))。这些权限只在这次调用期间允许，它仍然读不到你保存的账号值以外的任何东西。")
                        .font(.footnote)
                } header: {
                    Text("这次调用")
                }

                if let problem {
                    Section {
                        Text(problem).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("运行 \(record.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("运行") { run() }
                        .disabled(method.isEmpty)
                        .accessibilityIdentifier("service.run.start")
                }
            }
            .onAppear {
                if method.isEmpty { method = offered.first?.name ?? "ping" }
            }
        }
    }

    private func run() {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text.isEmpty ? "null" : text
        guard (try? JSONSerialization.jsonObject(with: Data(body.utf8))) != nil else {
            problem = "参数不是合法 JSON，未发送。"
            return
        }
        problem = nil
        let chosen = method
        dismiss()
        Task { await services.call(record, method: chosen, payload: body, granted: granted) }
    }

    private static func permissionName(_ permission: String) -> String {
        switch permission {
        case "network": return "网络（经宿主）"
        case "storage": return "本地小数据"
        case "secrets": return "读取账号值"
        default: return permission
        }
    }
}
