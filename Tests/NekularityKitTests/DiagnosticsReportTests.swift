import Foundation
import Testing

@testable import NekularityKit

@Suite("Diagnostics report")
struct DiagnosticsReportTests {
    private func report() -> DiagnosticsReport {
        DiagnosticsReport(sections: [
            .init("运行", [.init("版本", "0.1.0"), .init("Core", "8aebcedd5c6a")]),
            .init("检查", [.init("钥匙串", "可读", ok: true),
                          .init("后台音频", "未声明", ok: false)]),
        ], takenAt: Date(timeIntervalSince1970: 0))
    }

    @Test("a report reads as sections of marked lines")
    func formats() {
        let text = report().text()
        #expect(text.hasPrefix("Nekularity 自检 · 1970-01-01 00:00:00Z"))
        #expect(text.contains("[运行]"))
        #expect(text.contains("  · 版本:0.1.0"))
        #expect(text.contains("  ✓ 钥匙串:可读"))
        #expect(text.contains("  ✗ 后台音频:未声明"))
    }

    @Test("failures are counted, because that is why anyone reads the report")
    func countsFailures() {
        #expect(report().failures == 1)
        #expect(DiagnosticsReport(sections: []).failures == 0)
    }

    @Test("a report never carries a secret")
    func noSecrets() {
        // The type takes whatever a caller passes, so this pins the intent: the
        // screen that builds it must pass counts and booleans, and this test names
        // the words that must never appear in the output of a well-formed report.
        let text = report().text()
        for forbidden in ["token", "password", "cookie=", "Bearer"] {
            #expect(!text.lowercased().contains(forbidden.lowercased()))
        }
    }
}
