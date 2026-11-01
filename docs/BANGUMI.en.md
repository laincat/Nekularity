# Bangumi support

[简体中文](BANGUMI.md) | English

Bangumi (bgm.tv) is the *account* side of watching shows on this device: collection state, ratings, progress, and the air date of every episode. It divides the work with TMDB — TMDB knows when a western show airs, Bangumi has the Chinese title, the episode list and where Chinese viewers keep their collections — and the reminder planner merges both into one plan.

## What it does

| Feature | Where | Notes |
|---|---|---|
| Connect an account | Mine → Bangumi | Paste a personal token; it is checked against `/v0/me` before it is written to the Keychain |
| See collections | same screen | Wish / done / watching / on hold / dropped, read one state at a time |
| Change state and rating | subject detail | A segmented picker for the state, a 0–10 rating |
| Mark an episode watched | the episode list | One check per episode, through Bangumi's progress endpoint |
| Search subjects | below the collections | Anime only (type=2), a POST search by keyword |
| Weekly calendar | below the collections | Public data, shown without signing in |
| Airing reminders | Settings → reminders | Watching entries join `AiringPlan` by their next episode date, in the same notifications as TMDB's |

## Endpoints used

| Endpoint | Purpose | Needs a token |
|---|---|---|
| `GET /v0/me` | Validate the token, read nickname and avatar | yes |
| `POST /v0/search/subjects` | Keyword search, `filter.type` in the body | no |
| `GET /v0/subjects/{id}` | Subject detail | no |
| `GET /v0/episodes?subject_id=` | Episode list, 100 per page, 500 at most | no |
| `GET /calendar` | Weekly broadcast calendar | no |
| `GET /v0/users/-/collections` | This account's collections, filterable by state and subject type | yes |
| `GET /v0/users/-/collections/{id}` | One subject's state; 404 means not collected | yes |
| `POST /v0/users/-/collections/{id}` | Change state, rating, progress | yes |
| `PATCH /v0/users/-/collections/{id}/episodes` | Mark one episode watched; answers 202 (queued) | yes |

Every request carries `User-Agent: laincat/Nekularity (...)`. That is not decoration: Bangumi answers 403 to the default URLSession agent and throttles anonymous traffic hard.

## Credentials

The token lives only in the Keychain (`com.laincat.nekularity.bangumi`, with a per-environment service name) under `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — being restored onto another phone from a backup should not hand over someone's collection. Collections and episode lists stay in memory and are not written to disk.

There is no OAuth: OAuth would put a client secret in an app bundle anyone can unzip, which is not a secret. A personal token is the way Bangumi offers third-party clients.

## Not done yet

| Item | Why |
|---|---|
| Collection paging | One page of 50 for now, so a large collection will not be shown in full |
| Subject comments and discussion | The endpoints exist; no interface was designed |
| Books and games | Search is anime only (type=2); the model already decodes `type` |
| Caching collections on disk | Every visit asks again, and offline is a blank screen |
| Calendar aligned to the local week | The calendar shows Bangumi's weekday, not the device's |

## How to check it

The unit tests do not touch the network: request shape, field decoding, error wording and the watching → reminder-plan join are covered in `Tests/NekularityKitTests/BangumiTests.swift` against a fake transport.

```sh
swift test --filter Bangumi
```

What a device has to confirm:

1. A rejected token should say the token is the problem, not show an empty list;
2. Whether switching between the five states shows the right entries each time;
3. Whether marking an episode watched moves the progress at once (the API answers 202 and writes queued);
4. With reminders on, a watching entry should produce a notification on the morning of its air day.
