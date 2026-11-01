import Foundation

/// The source API level this client implements.
///
/// A source declares `minAppVersion`, and Core compares it with the value the
/// client passes to `CoreConfig`. That value is *not* the app's own version:
/// every official source requires 1.0.0 or higher, so reporting 0.1.0 made Core
/// refuse all of them with `minAppVersion 1.0.0 is required` and the app showed an
/// empty source list.
///
/// It tracks the official client's release, which is 1.6.3. The desktop client
/// names the same number in `internal/sourceapi`, and a source that needs an
/// interface this client lacks still fails at the call that needs it, which is
/// what its own error says.
public enum SourceAPI {
    /// What sources see through `getAppVersion()` and what `minAppVersion` is
    /// compared with.
    public static let level = "1.6.3"
}
