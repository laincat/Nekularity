import NekularityKit
import SwiftUI

/// Lets any screen offer the environment switcher without threading a closure
/// through every view between here and there.
struct SwitchProfileKey: EnvironmentKey {
    static let defaultValue: @MainActor (String) async -> Void = { _ in }
}

extension EnvironmentValues {
    var switchProfile: @MainActor (String) async -> Void {
        get { self[SwitchProfileKey.self] }
        set { self[SwitchProfileKey.self] = newValue }
    }
}
