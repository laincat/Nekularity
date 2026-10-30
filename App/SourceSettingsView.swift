import SwiftUI
import NekularityKit

/// The settings a comic source declares, drawn by type and stored as JSON in
/// that source's store — the same values Core hands back through `getSetting`.
///
/// A source may declare a number or a boolean, so a chosen value is written as
/// the source wrote it: `JSONValue` keeps the text instead of turning
/// everything into a string.
struct SourceSettingsView: View {
    let source: PluginRecord
    @Environment(SourceLibrary.self) private var library
    @State private var model = SettingsModel()

    var body: some View {
        Form {
            if model.loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = model.error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("重试") { Task { await model.load(library, key: source.key) } }
                }
            } else if model.settings.isEmpty {
                Section {
                    Text("这个源没有声明设置。").foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.settings) { setting in
                    settingRow(setting)
                }
            }
        }
        .navigationTitle("\(source.name) 的设置")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: source.key) { await model.load(library, key: source.key) }
    }

    @ViewBuilder
    private func settingRow(_ setting: SourceSetting) -> some View {
        switch setting.kind {
        case .choice:
            let options = setting.options ?? []
            Picker(title(setting), selection: Binding(
                get: { model.choiceIndex(setting) },
                set: { index in
                    guard options.indices.contains(index) else { return }
                    Task { await model.save(library, key: source.key, setting: setting, value: options[index].value) }
                }
            )) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Text(option.text ?? option.value.stringValue ?? "").tag(index)
                }
            }
        case .toggle:
            Toggle(title(setting), isOn: Binding(
                get: { model.toggleValue(setting) },
                set: { on in
                    Task { await model.save(library, key: source.key, setting: setting, value: .bool(on)) }
                }
            ))
        case .text:
            VStack(alignment: .leading, spacing: 4) {
                Text(title(setting)).font(.footnote).foregroundStyle(.secondary)
                TextField(text(setting), text: Binding(
                    get: { model.textValue(setting) },
                    set: { model.texts[setting.key] = $0 }
                ))
                .textInputAutocapitalization(.never)
                .onSubmit {
                    Task {
                        let ok = await model.save(library, key: source.key, setting: setting,
                                                 value: .string(model.textValue(setting)))
                        if !ok { model.error = "内容不符合要求：\(setting.validator ?? "")" }
                    }
                }
            }
        case .action:
            LabeledContent(title(setting), value: "源内的操作，客户端暂不支持")
                .foregroundStyle(.secondary)
        }
    }

    private func title(_ setting: SourceSetting) -> String {
        setting.title.isEmpty ? setting.key : setting.title
    }

    private func text(_ setting: SourceSetting) -> String {
        model.textValue(setting)
    }
}

/// Loads a source's declaration and the values in force.
@MainActor @Observable
final class SettingsModel {
    var settings: [SourceSetting] = []
    var values: [String: JSONValue] = [:]
    /// Text being typed into an input, before it is saved.
    var texts: [String: String] = [:]
    var loading = false
    var error: String?

    func load(_ library: SourceLibrary, key: String) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let declared = try await library.core.settings(key: key)
            settings = declared
            values = [:]
            texts = [:]
            let store = library.core.host.store
            for setting in declared {
                if let stored = try store.loadSetting(key: key, settingKey: setting.key),
                   let value = try? JSONValue.parse(stored) {
                    values[setting.key] = value
                } else if let fallback = setting.default {
                    values[setting.key] = fallback
                }
                texts[setting.key] = values[setting.key]?.stringValue ?? ""
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The index of the option in force, for a Picker.
    func choiceIndex(_ setting: SourceSetting) -> Int {
        let options = setting.options ?? []
        let current = values[setting.key]?.stringValue
        if let index = options.firstIndex(where: { $0.value.stringValue == current }) {
            return index
        }
        return 0
    }

    func toggleValue(_ setting: SourceSetting) -> Bool {
        if case .bool(let on) = values[setting.key] ?? .null { return on }
        return false
    }

    func textValue(_ setting: SourceSetting) -> String {
        texts[setting.key] ?? values[setting.key]?.stringValue ?? ""
    }

    /// Writes one value and keeps what is on screen in step. Returns whether
    /// the value was accepted by the source's validator.
    @discardableResult
    func save(_ library: SourceLibrary, key: String, setting: SourceSetting, value: JSONValue) async -> Bool {
        if setting.kind == .text {
            if let pattern = setting.validator, !pattern.isEmpty,
               let regex = try? NSRegularExpression(pattern: pattern),
               value.stringValue.map({ regex.firstMatch(in: $0, range: NSRange(location: 0, length: $0.utf16.count)) == nil }) ?? false {
                return false
            }
        }
        do {
            try library.core.host.store.saveSetting(key: key, settingKey: setting.key, json: value.jsonText)
            values[setting.key] = value
            texts[setting.key] = value.stringValue ?? ""
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
