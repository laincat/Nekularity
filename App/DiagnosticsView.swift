import AVKit
import NekularityKit
import SwiftUI
import UIKit

/// 自检: what this build can say about itself, in a form that can be pasted.
///
/// It exists because verifying a real device otherwise means "install it and tell me
/// what you see", which yields a screenshot and no facts. Everything here is a count,
/// a version or a boolean — never a token — because the point is to paste it.
struct DiagnosticsView: View {
    @Environment(SourceLibrary.self) private var library
    @Environment(ShelfStore.self) private var shelf
    @Environment(DownloadStore.self) private var downloads
    @Environment(ProfileStore.self) private var profiles
    @Environment(MediaServerStore.self) private var servers
    @Environment(MetadataStore.self) private var metadata
    @Environment(LocalComicStore.self) private var local
    @Environment(TagGlossaryStore.self) private var glossary
    @Environment(VideoLibraryStore.self) private var media

    @State private var copied = false

    private var report: DiagnosticsReport {
        DiagnosticsReport(sections: [
            .init("运行", [
                .init("版本", Self.shortVersion),
                .init("Core", CoreVersion.short),
                .init("系统", UIDevice.current.systemName + " " + UIDevice.current.systemVersion),
                .init("设备", Self.deviceKind),
            ]),
            .init("环境", [
                .init("当前环境", profiles.active.name),
                .init("环境数", "\(profiles.profiles.count)"),
                .init("目录", profiles.activeDirectory.lastPathComponent),
            ]),
            .init("源", [
                .init("总数", "\(library.sources.count)"),
                .init("启用的漫画源", "\(library.comicSources.filter(\.enabled).count)"),
                .init("启用的视频源", "\(library.sources.filter { $0.enabled && $0.isVideo }.count)"),
                .init("恢复失败", "\(library.restoreFailures.count)", ok: library.restoreFailures.isEmpty),
            ]),
            .init("账号与凭据", [
                .init("TMDB key", metadata.hasKey ? "已保存" : "未设置", ok: metadata.hasKey ? true : nil),
                .init("媒体服务器", "\(servers.servers.count)"),
                .init("保存了令牌的服务器",
                      "\(servers.servers.filter { servers.token(for: $0) != nil }.count)"),
            ]),
            .init("内容", [
                .init("书库记录", "\(shelf.history.count)"),
                .init("收藏夹", "\(shelf.folders.count)"),
                .init("已下载章节", "\(downloads.chapters.count)"),
                .init("本地漫画", "\(local.comics.count)"),
                .init("本机视频", "\(media.items.count)"),
                .init("标签译名覆盖", "\(glossary.count)"),
            ]),
            .init("能力", [
                .init("画中画", AVPictureInPictureController.isPictureInPictureSupported() ? "支持" : "不支持",
                      ok: AVPictureInPictureController.isPictureInPictureSupported() ? true : nil),
                // A PiP window over an app that may not keep playing closes itself,
                // so this is worth failing loudly rather than discovering later.
                .init("后台音频", Self.hasBackgroundAudio ? "已声明" : "未声明", ok: Self.hasBackgroundAudio),
                .init("网络策略", Self.allowsArbitraryLoads ? "允许任意来源" : "受限"),
            ]),
        ])
    }

    var body: some View {
        List {
            Section {
                Text(report.failures == 0 ? "全部检查通过。" : "有 \(report.failures) 项需要看。")
                    .font(.callout)
                    .foregroundStyle(report.failures == 0 ? .secondary : .orange)
                Button {
                    UIPasteboard.general.string = report.text()
                    copied = true
                } label: {
                    Label(copied ? "已复制" : "复制报告", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("diagnostics.copy")
            }

            ForEach(report.sections) { section in
                Section(section.name) {
                    ForEach(section.lines, id: \.self) { line in
                        HStack {
                            Text(line.title)
                            Spacer()
                            Text(line.value)
                                .foregroundStyle(line.ok == false ? Color.red : .secondary)
                        }
                    }
                }
            }

            Section {
                Text("报告只有版本、数量和开关状态,没有令牌、Cookie 或密码。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("自检")
        .accessibilityIdentifier("diagnostics")
    }

    private static var shortVersion: String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static var deviceKind: String {
        // Not the model identifier: a report is pasted into a chat, and the exact
        // hardware is neither needed nor something to hand out by default.
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    private static var hasBackgroundAudio: Bool {
        let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] ?? []
        return modes.contains("audio")
    }

    private static var allowsArbitraryLoads: Bool {
        let ats = Bundle.main.infoDictionary?["NSAppTransportSecurity"] as? [String: Any]
        return ats?["NSAllowsArbitraryLoads"] as? Bool == true
    }
}
