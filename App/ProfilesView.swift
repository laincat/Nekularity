import NekularityKit
import SwiftUI

/// Environments: switch between accounts, and make or delete one.
///
/// Each environment carries its own sources, cookies, AI sign-ins, shelf and
/// downloads, so switching is a real switch rather than a filter — which is the
/// only version of "two accounts" that does not leak one account's sessions into
/// the other.
struct ProfilesView: View {
    let profiles: ProfileStore
    /// Rebuilds the object graph; provided by the app model.
    let switchTo: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var newName = ""
    @State private var renaming: Profile?
    @State private var renameText = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(profiles.profiles) { profile in
                        Button {
                            guard profile.id != profiles.activeID else { return }
                            busy = true
                            Task {
                                await switchTo(profile.id)
                                busy = false
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: profile.id == profiles.activeID ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(profile.id == profiles.activeID ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                    Text(Self.date(profile.created)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            // Without this the row only answers where it has
                            // text, which reads as "the list ignores my taps".
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.\(profile.name)")
                        .swipeActions {
                            Button("重命名") { renaming = profile; renameText = profile.name }
                            if profiles.profiles.count > 1 {
                                Button("删除", role: .destructive) { try? profiles.remove(profile.id) }
                            }
                        }
                    }
                } footer: {
                    Text("每个环境有自己的漫画源、登录状态、书架和下载。切换环境会重新加载 Core，因为它就是按这个环境的源与 Cookie 建起来的。")
                }

                Section {
                    Button {
                        newName = ""
                        creating = true
                    } label: {
                        Label("新建环境", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("profile.create")
                }
            }
            .navigationTitle("环境")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .overlay { if busy { ProgressView("正在切换…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .alert("新环境名称", isPresented: $creating) {
                TextField("名称", text: $newName)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    if let profile = try? profiles.create(name: newName) {
                        Task {
                            busy = true
                            await switchTo(profile.id)
                            busy = false
                            dismiss()
                        }
                    }
                }
            }
            .alert("重命名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("名称", text: $renameText)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") {
                    if let profile = renaming { profiles.rename(profile.id, to: renameText) }
                    renaming = nil
                }
            }
        }
    }

    private static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: value)
    }
}
