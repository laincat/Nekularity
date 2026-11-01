#!/bin/sh
# Fails when a capability the official comic sources declare is no longer read.
#
# The desktop has the same check. Both exist because every one of these was
# found by hand: the category page, the random part, the ranking page, the three
# login styles, the source's own favorites, the translation table. Each had been
# declared by the sources and silently ignored, so an empty screen was the only
# symptom.
#
# This is a regression net, not a discovery tool: it checks that Kit and the
# interface still have a path for what the client claims to support. Matching is
# by fixed string, so a renamed member cannot keep passing on a shared prefix.
set -e
root=$(dirname "$0")/..
cd "$root"

fail=0
need() {
	# need <capability> <file> <fixed text>
	if ! grep -qF -- "$3" "$2" 2>/dev/null; then
		printf 'check-capabilities: %s is not read any more (%s)\n' "$1" "$2"
		exit 1
	fi
}

# A source's category page: parts, values, options, and the loader.
need "category page" Sources/NekularityKit/Core/CoreClient.swift 'public func categoryPage(key: String) async throws -> CategoryPage?'
need "category values" Sources/NekularityKit/Core/CoreClient.swift 'public func categoryComics(key: String, category: String, param: String,'
need "category screen" App/BrowseView.swift 'CategoryBrowser(source: sourceKey)'
# A part whose values are searched rather than loaded.
need "random part" App/CategoryView.swift 'func searchRandom(_ core: CoreClient, part: CategoryPart) async'
# The ranking page: a flat option list with its own loader.
need "ranking page" Sources/NekularityKit/Core/CoreClient.swift 'public func rankingComics(key: String, option: String, page: Int) async throws -> ComicPage'
need "ranking entry" App/CategoryView.swift 'func selectRanking(_ core: CoreClient, option: String) async'
# The three login styles, each with its own path.
need "login styles" Sources/NekularityKit/Core/CoreClient.swift 'account.loginWithCookies.validate'
need "password login" Sources/NekularityKit/Core/CoreClient.swift 'path: "account.login"'
need "account screen" App/SourceSettingsView.swift 'private var accountSection: some View'
# The in-page login: five sources log in on their own site, and the page's own
# checkStatus decides when it finished.
need "webview login" Sources/NekularityKit/Core/CoreClient.swift 'public func webviewLogin(key: String) async throws -> WebviewLogin'
need "webview login status" Sources/NekularityKit/Core/CoreClient.swift 'public func webviewStatus(key: String, handle: String,'
need "webview login session" Sources/NekularityKit/Platform/WebviewLoginSession.swift 'public final class WebviewLoginSession: NSObject, WKNavigationDelegate'
need "webview login sheet" App/WebviewLoginView.swift 'WebviewLoginSession(login: login, key: key,'
# Logout belongs to every login style, not only the password one.
need "account logout" App/SourceSettingsView.swift 'if model.account.logout {'
# A callback setting is a function in the source; the client can only offer its
# own button text and run it.
need "setting callback" Sources/NekularityKit/Core/CoreClient.swift 'public func callSettingCallback(key: String, setting: String) async throws -> String'
need "setting callback button" App/SourceSettingsView.swift 'await model.runCallback(library, key: source.key, setting: setting.key)'
need "setting button text" Sources/NekularityKit/Core/Models.swift 'public var buttonText: String?'
# The interface tests press these controls, so each needs a stable handle: a
# label is localized, and a source renames itself.
need "test handle: source row" App/SourcesView.swift '.accessibilityIdentifier("source.\(source.key)")'
need "test handle: settings" App/SourcesView.swift '.accessibilityIdentifier("source.settings")'
need "test handle: in-page login" App/SourceSettingsView.swift '.accessibilityIdentifier("account.webviewLogin")'
need "test handle: callback" App/SourceSettingsView.swift '.accessibilityIdentifier("setting.callback.\(setting.key)")'
need "test handle: comments" App/ComicDetailView.swift '.accessibilityIdentifier("detail.comments")'
# Sources compare minAppVersion with the level the client reports. Reporting the
# app's own version (0.1.0) made Core refuse every official source.
need "source API level" Sources/NekularityKit/Core/SourceAPI.swift 'public static let level = "1.6.3"'
need "source API level used" App/NekularityApp.swift 'CoreConfig(appVersion: Self.sourceLevel'
# The source's own favorites, in one folder or several.
need "favorites shape" Sources/NekularityKit/Core/CoreClient.swift 'public func favoritesSupport(key: String) async -> FavoritesSupport'
need "favorites list" Sources/NekularityKit/Core/CoreClient.swift 'path: "favorites.loadComics"'
need "favorites screen" App/SourcesView.swift 'SourceFavoritesView(source: current)'
need "favorites toggle" Sources/NekularityKit/Core/CoreClient.swift 'path: "favorites.addOrDelFavorite"'
need "backup export" Sources/NekularityKit/Core/CoreClient.swift 'public func exportBackup(searchHistory:'
need "backup export entry" App/SourcesView.swift 'Label("导出备份"'
need "source log panel" App/SourceLogView.swift 'struct SourceLogView: View'
need "browse cursor" Sources/NekularityKit/Core/CoreClient.swift 'cursor: String = ""'
need "browse cursor paging" App/BrowseView.swift 'func nextPage(_ core: CoreClient) async'
need "comment support" Sources/NekularityKit/Core/CoreClient.swift 'public func commentSupport(key: String)'
need "comment thread" App/ComicCommentsView.swift 'struct ComicCommentsView: View'
need "comment vote" Sources/NekularityKit/Core/CoreClient.swift 'public func likeComment(key: String, comicID: String, subID: String,'
need "comment replies" App/ComicCommentsView.swift 'private func showReplies(_ one: ComicComment) async'
need "tag click" Sources/NekularityKit/Core/CoreClient.swift 'public func clickTag(key: String, namespace: String, tag: String)'
need "link open" Sources/NekularityKit/Core/CoreClient.swift 'public func openLink(_ raw: String) async throws -> LinkTarget'
need "link detection" Sources/NekularityKit/Core/LinkDetection.swift 'public static func looksLikeLink(_ text: String) -> Bool'
need "tag search sheet" App/SourceSearchSheet.swift 'struct SourceSearchSheet: View'
need "category param entry" App/CategoryView.swift 'var initialParam: String = ""'
need "source log lines" Sources/NekularityKit/Core/CoreClient.swift 'public func logLines() async throws -> [SourceLogEntry]'
need "favorite toggle state" App/ComicDetailView.swift 'final class SourceFavoriteState'
# The UI strings a source declares for this locale.
need "translations" Sources/NekularityKit/Core/CoreClient.swift 'public func translations(key: String) async throws -> [String: String]'
need "translated titles" App/SourceSettingsView.swift 'translations[raw] ?? raw'
# A declaration that is data rather than a function.
need "data declarations" Sources/NekularityKit/Core/CoreClient.swift 'comicValue(key: key, path: "favorites.multiFolder")'

printf 'check-capabilities: ok (category, random, ranking, account, favorites, translations)\n'
