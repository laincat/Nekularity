# Kit declarative modules and service packages

[简体中文](KIT-EXTENSIONS.md) | English

## Reader modules

`VCModuleDocument.parse` reads UTF-8 text in the `veneracat-module/1-draft` format. The header requires `#!name`, `#!version`, and `#!format`. `#!desc` is optional. The initial section is `[Reader]` with `page-gap` (0–128), `keep-screen-on`, `layout` (`vertical` or `paged`), `right-to-left`, and `auto-next`. Booleans use `true` or `false`. A line that starts with `;` or `#` is a comment. Unknown sections or keys, duplicate assignments, and invalid values cause the whole module to be rejected.

The host supplies `VCModuleStore.install` with a stable identity, such as the collection ID paired with the entry ID. Modules start disabled. Later installed and enabled modules override earlier enabled modules per key. Updates to the same identity keep their position and enabled state. Pass the current base settings to `effectiveSettings(over:)`. Disabling or removing a module restores the next layer's values. Module bodies and enablement live in the same atomic snapshot with file protection. A damaged index is preserved for recovery. Module management and effective settings are available through the Kit API.

## Service package call contract

Core calls `handle(method, payloadText)` in the service package. `payloadText` is a JSON object as text when parameters are present, and `null` when there are none. Read methods return a result object or array directly. `collection.get` may return `null` when a subject is absent from the collection. Write methods should return `null` or `{"ok":true}` after success.

| Service package | Methods | Request fields and results |
|---|---|---|
| `service.bangumi` | `account.me`, `calendar.list` | No parameters. Return `BangumiUser` and `[BangumiCalendarDay]`, respectively |
| `service.bangumi` | `subject.search`, `subject.detail`, `subject.episodes` | Send `keyword/type/limit`, `subject_id`, `subject_id/type`. Return subjects, a subject, or episodes, respectively |
| `service.bangumi` | `collection.list`, `collection.get`, `collection.update`, `episode.markWatched` | Send `subject_type/limit/type?`, `subject_id`, `subject_id/type/rate?/ep_status?/comment?`, `subject_id/episode_id`, respectively |
| `service.tmdb` | `series.search`, `series.detail`, `series.artwork` | Send `query/language`, `id/language`, `id/language`, respectively. Series use `id/name/overview?/poster?/firstAirDate?/nextEpisode?/status?`. Artwork uses `TMDBArtwork` |
| `service.trakt` | `account.me`, `search`, `watchlist.list`, `history.list` | `search` takes `query`. The others take no parameters. Return an account, a list of items, or a list of viewing records |
| `service.trakt` | `watchlist.set`, `history.add`, `scrobble` | Send `item/included`, `item/watchedAt`, `item/action/progress`, respectively. A request item uses `kind/id`. Returned items also include `title` and optional `year` |

Bangumi account, collection, and progress methods require `token`. TMDB methods require `api_key`. Trakt search requires `client_id` and account routes also require `access_token`. These values come from `ServiceAccounts` for the current profile. Authorization for built-in features is bound to the installed archive digest. Calls receive the permissions they require from the package's declared `network` and `secrets` permissions. Existing Bangumi and TMDB credentials stay in their original Keychain entries for the built-in clients when the package is absent. Once a package is authorized, enter credentials for it in its service account screen or the corresponding settings. Trakt accepts an injected `TraktProvider` fallback. The current app has no built-in Trakt client.

Core's service host currently exposes `fetch(url)` for GET requests. Live upstream operations requiring authorization headers, POST, or PATCH depend on expanded HTTP support in Core. All three packages are still designs in the source collection. Offline tests exercise Swift request and response contracts, permissions, and fallback behavior. An installed test package exercises the actual Core and `CoreHost` call path.
