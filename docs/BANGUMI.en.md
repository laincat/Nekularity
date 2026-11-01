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
| Search subjects | below the collections | Anime only (type=2). The v0 search **returns nothing for Chinese keywords while anonymous**, so an empty answer falls back to the older endpoint |
| Weekly calendar | below the collections | Public data, shown without signing in |
| Airing reminders | Settings → reminders | Watching entries join `AiringPlan` by their next episode date, in the same notifications as TMDB's |

## Endpoints used

| Endpoint | Purpose | Needs a token |
|---|---|---|
| `GET /v0/me` | Validate the token, read nickname and avatar | yes |
| `POST /v0/search/subjects` | Keyword search, `filter.type` in the body | no |
| `GET /search/subject/{keyword}` | The older search, **the one that finds Chinese**; its `id`/`type` are strings and its date is `air_date` | no |
| `GET /v0/subjects/{id}` | Subject detail | no |
| `GET /v0/episodes?subject_id=` | Episode list, 100 per page, **paged to the `total` the server reports** (ONE PIECE measured at 1155 episodes), capped at 2000 | no |
| `GET /calendar` | Weekly broadcast calendar | no |
| `GET /v0/users/-/collections` | This account's collections, filterable by state and subject type | yes |
| `GET /v0/users/-/collections/{id}` | One subject's state; 404 means not collected | yes |
| `POST /v0/users/-/collections/{id}` | Change state, rating, progress | yes |
| `PATCH /v0/users/-/collections/{id}/episodes` | Mark one episode watched; answers 202 (queued) | yes |

The collection endpoint answers **404 rather than 401 when there is no token** (measured), so a 404 there is reported as "the account was not recognised" rather than "no such entry".

The same date has two names: `/v0/subjects` calls it `date`, while the calendar and the older search call it `air_date`. Both are decoded, the former first — otherwise a subject opened from the calendar arrives with no date at all.

Every request carries `User-Agent: laincat/Nekularity (...)` because Bangumi's documentation asks callers to identify themselves. Measured on 2026-11-01: a request without a UA answered 200 too, so the claim that "the default agent gets a 403" **did not reproduce** and is recorded here rather than repeated as fact.

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

Every endpoint shape was checked once against the **live responses** of 2026-11-01 (`/v0/subjects/12`, `/v0/episodes`, `/calendar`, and the older search). One finding came out of that: while anonymous, the v0 search **returns nothing for Chinese keywords** — "进击的巨人" gave 0 results and the older endpoint gave 128. Search therefore falls back to the older endpoint instead of showing "nothing found".

```sh
swift test --filter Bangumi
```

What a device has to confirm:

1. A rejected token should say the token is the problem, not show an empty list;
2. Whether switching between the five states shows the right entries each time;
3. Whether marking an episode watched moves the progress at once (the API answers 202 and writes queued);
4. With reminders on, a watching entry should produce a notification on the morning of its air day.
