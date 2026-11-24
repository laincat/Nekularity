# Kit declarative modules and service packages

[简体中文](KIT-EXTENSIONS.md) | English

## Reader modules

`VCModuleDocument.parse` reads UTF-8 text in the `veneracat-module/1-draft` format. The header requires `#!name`, `#!version`, and `#!format`. `#!desc`, `#!id`, and `#!requires` are optional. The current supported requirement is `settings-module.v1`. The initial section is `[Reader]` with `page-gap` (0–128), `keep-screen-on`, `layout` (`vertical` or `paged`), `right-to-left`, and `auto-next`. Booleans use `true` or `false`. A line that starts with `;` or `#` is a comment. Unknown sections or keys, duplicate assignments, and invalid values cause the whole module to be rejected.

The host supplies `VCModuleStore.install` with a stable identity, such as the collection ID paired with the entry ID. Modules start disabled. Later installed and enabled modules override earlier enabled modules per key. Updates to the same identity keep their position and enabled state. Pass the current base settings to `effectiveSettings(over:)`. Disabling or removing a module restores the next layer's values. Module bodies and enablement live in the same atomic snapshot with file protection. A damaged index is preserved for recovery. Module management and effective settings are available through the Kit API.

## Service package call contract

Core calls `handle(method, payloadText)` exported by the service package. Parameters travel as a JSON object in text form, or `null` for an empty request. The bridge follows the packages in Sources and validates the `{ok, service, method, data}` envelope before decoding `data`. Execution errors report the service and method. Credential values stay out of request parameters and diagnostics.

| Service package | Methods and requests |
|---|---|
| `service.bangumi` | `account.me`, `metadata.search` (`keyword/type/limit`), `metadata.detail` (`subjectId` with optional `includeEpisodes/episodeType/episodeOffset`), `collection.get` (`subjectId` or list filters), `collection.update`, and `episode.update` (`subjectId/episodeIds/type`). The built-in client still loads the broadcast calendar |
| `service.tmdb` | `metadata.search`, `metadata.detail`, and `artwork.list`. TV requests include `mediaType: "tv"` and a language. The current package omits the next episode to air |
| `service.trakt` | `account.me`, `metadata.search`, `watchlist.list`, `history.list`, `scrobble.start`, and `scrobble.stop`. `TraktService` reports unsupported watchlist writes, history writes, and pause when the package returns `UNSUPPORTED_METHOD` |

Bangumi account, collection, and progress methods require `access_token`. TMDB accepts `api_read_token` or `api_key`. Trakt search requires `client_id` and account routes also require `access_token`. These values come from `ServiceAccounts` for the current profile. Authorization for built-in features is bound to the installed archive digest. Calls receive only the required and declared `network` and `secrets` permissions. Existing Bangumi and TMDB credentials stay in their original Keychain entries for the built-in clients when the package is absent. Enter credentials for the package in its service account screen or the corresponding settings. Trakt accepts an injected `TraktProvider` fallback. The current app has no built-in Trakt client.

Core's service host currently exposes `fetch(url)` for GET requests. Authorization headers, POST, PATCH, and PUT depend on expanded HTTP support in Core. Sources publishes three packages verified with offline fixtures. The tests here cover Swift requests and responses, permissions, and fallback behavior. An installed test package exercises the actual Core and `CoreHost` call path.
