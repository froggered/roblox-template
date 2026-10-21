# Working in this codebase

Roblox game, Rojo + Wally, Luau (`.luau`). Read `README.md` first for the
layout — this file is the rules that aren't obvious from reading the code.

## Where things go

- Dictionaries and constants → `src/shared/Data/`. Data modules contain **no
  logic** — they return a table. Logic that reads them goes in
  `src/shared/Modules/`.
- Server-only logic → `src/server/ServerModules/`. Nothing in `shared/Modules`
  may assume it's on the server.
- Client features → `src/client/Controllers/`, one concern per module. They're
  auto-required at startup, so a new controller needs no wiring.
- Never author remotes, or data, in the place file. Instances in the `.rbxl`
  are for geometry and GUI only.

## Data

- `DataService` (leifstout) wraps ProfileStore and replicates the profile to
  the owning client. Server: `require(ReplicatedStorage.Packages.DataService).server`.
  Client: `.client`.
- **Writing:** currency, inventory and stats go through `DataManager` only.
  Do not call `DataService:set` on those paths from gameplay code, and never
  touch `profile.Data` directly — a raw write persists but never reaches the
  client's replica, so client-side gates read stale for the whole session.
- **Reading:** `DataService:get(player, path)` on the server,
  `DataService:get(path)` on the client, anywhere, freely.
- Guard every server-side data access with `DataService:hasProfile(player)`.
  Any code that yields may resume after the player has left.
- Profile values are JSON: no `Vector3`/`Color3`/`Instance`, no mixed
  array+dictionary tables, no `nil` holes in arrays.
- New profile fields go in `ServerData/DataTemplate` with a real default so
  readers never need a fallback. Reconcile fills them in on next join.

## Monetization

- Asset ids live in `src/shared/Data/Products.luau` and **nowhere else**. If
  you're about to type a number that came from the Creator Dashboard into any
  other file, stop.
- Resolve through `ProductUtil` (`byKey`, `byId`, `forSale`, `getPrice`).
- Grants live in `MarketFunctions`, keyed by the catalog key. Dev product
  grants may be retried; gamepass grants run again on every join, so they must
  be idempotent.
- Don't confirm a receipt outside `MarketManager` — the exactly-once handshake
  (grant → record purchase id → force save → confirm) is the whole point.

## Luau style

- Match the surrounding file. Tabs, `local X = game:GetService("X")` at the
  top, requires below in alphabetical order.
- Prefer `if x then a else b` expressions and string interpolation
  (`` `text {value}` ``) — this is Luau, not Lua 5.1.
- Generalized iteration (`for k, v in table do`), not `pairs`/`ipairs`.
- Comment the *why*, especially anything that looks arbitrary: an ordering
  constraint, a race that was actually hit, a value that was tuned. Don't
  comment what the line already says.

## Before saying it works

```sh
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json \
  --base-luaurc=.luaurc --ignore="Packages/**" src
```

Must come back clean. `rojo build` succeeding proves nothing — it doesn't parse
Luau.

## The changelog

`CHANGELOG.md` is this game's update log. gnomecode.com reads it from GitHub
every hour and shows each dated section on the game's dashboard page, so write
it for that log, not for git.

- When a change is something a player would notice, or a decision worth
  remembering later (a price, an odds change, a mode removed and why), add one
  line under `## Unreleased`. Plain English, what changed rather than how:
  "Gold packs give Legends at double odds this weekend", not "Bump
  LegendWeight in PackOdds".
- Refactors, tooling, tests and fixes to bugs that never shipped get no line.
  Most commits get none; that is the point of the file.
- Add to the end of the Unreleased list. If a later change reworks something
  that is already listed and not yet released, edit that line rather than
  adding a second one.
- Only release when Ed says the game has just been published from Studio. Then
  run `python tools/release.py --type <Content|Bugfix|Config|Misc> --yes`
  (ask him the type if it isn't obvious), which dates the section, commits,
  tags and pushes. Never make `release-*` tags or move lines out of Unreleased
  any other way.
- Released sections are the published record. Only change one when Ed asks for
  a correction; the dashboard follows within the hour.
