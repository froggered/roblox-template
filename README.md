# Roblox game template

A starting point for a new game: Rojo project layout, [DataService] for
replicated player data, a single monetization catalog, and the server-side
managers that every game ends up needing anyway.

## Starting a new game from this

1. Copy the folder, then rename the project in `default.project.json`
   (`"name"`) and `wally.toml` (`[package] name`).
2. `rokit install` — gets rojo, wally and luau-lsp on PATH.
3. `wally install` — populates `Packages/`.
4. `rojo serve` and connect from Studio, or `rojo build -o game.rbxl` for a
   place file to open.
5. Set the game's **Repository** on the gnomecode.com dashboard to this repo,
   so its `CHANGELOG.md` feeds the game's update log. See "Releasing" below.

Nothing else needs renaming. DataStores are scoped to the universe, so the
profile store index in `DataManager` is the same string in every game.

## Layout

```
src/
  client/                     -> StarterPlayerScripts.Client (LocalScript)
    init.client.luau            entry point: starts the data replica, then controllers
    Controllers/                self-starting client modules, one concern each
  server/
    Main.server.luau          -> ServerScriptService.Main (Script) — the only entry point
    ServerModules/            -> ServerScriptService.ServerModules
      DataManager               THE writer for currency / inventory / stats
      MarketManager             receipts, gamepass ownership, purchase prompts
      MarketFunctions           what each product grants, keyed by catalog key
      LeaderboardManager        OrderedDataStore boards
    ServerData/               -> ServerScriptService.ServerData
      DataTemplate              the shape of a player profile
  shared/
    Data/                     -> ReplicatedStorage.Data — dictionary modules, no logic
      Products                  every gamepass + dev product id, once
      Currencies                every persistent currency
      GameConfig                tunable constants
    Modules/                  -> ReplicatedStorage.Modules — shared logic
      ProductUtil               flatten / look up / price / prompt the catalog
      Remotes                   find-or-create remote accessor
      Format                    number + time formatting for UI
Packages/                     -> ReplicatedStorage.Packages (wally, gitignored)
```

## The rules that make this work

**All player data goes through DataManager.** Currency is never written by
gameplay code — `DataManager.AddCurrency` / `TrySpend` are the only writers, so
the economy has one audit point, one analytics call site, and one place to add
a cap or a cheat check later.

```lua
if not DataManager.TrySpend(player, "Coins", item.Price, item.Name) then return end
DataManager.GrantItem(player, "Hats", item.Name)
```

**Reads are free, from either side.** The client holds a live replica, so UI
reads its own data locally and never asks the server:

```lua
local DataService = require(ReplicatedStorage.Packages.DataService).client
local coins = DataService:get({ "Coins" })
DataService:getChangedSignal({ "Coins" }):Connect(render)
```

**Every product id is written exactly once**, in `Data/Products`. Shop UI,
receipt handling, ownership checks and price labels all resolve through
`ProductUtil`, so an id never appears in two files. Products with no `Id` yet
are inert — you can build the whole shop before the products exist.

**Grants are keyed by catalog key, not asset id.** `MarketFunctions.CoinsSmall`
is the grant for whatever id `Products.Currency.CoinsSmall` carries.

**Never delete a product entry.** Set `ForSale = false`. A retired id can still
arrive on a receipt months later, and an unmapped receipt is left pending
forever.

## Adding things

**A currency** — add a key to `Data/Currencies` and the same key to
`ServerData/DataTemplate`. Leaderstats, player attributes, analytics and its
leaderboard all follow from the config.

**A product** — add an entry to the right group in `Data/Products` (leave `Id`
nil until it exists in Studio), then a grant in `ServerModules/MarketFunctions`
under the same key. Currency packs need neither: they generate themselves.

**A profile field** — add it to `ServerData/DataTemplate` with a real default.
ProfileStore reconciles it into existing profiles on their next join. Removing
a field does *not* strip it from stored profiles, which is the escape hatch
when a shape needs migrating: leave the old key, read it once in DataManager's
`onPlayerInit`, write the new shape.

**A client feature** — drop a ModuleScript in `src/client/Controllers/`. It's
required automatically at startup; a controller that errors is warned about and
skipped rather than taking the rest of the client down.

**A remote** — `Remotes.event("Name")` on both sides. Never author remote
instances in the place file: a duplicate folder silently splits client and
server onto different instances and the symptom is "the event just doesn't
fire".

## Studio and live data are separate

`DataManager.init` picks a `Test` profile store index in Studio and `Game`
otherwise, and leaderboards write to a `Test` scope in Studio. Live player data
is unreachable from Studio, and test data is disposable. Requires *Studio
access to API services* in Game Settings.

## Releasing

Publishing is done by hand in Studio. Afterwards, run

```sh
python tools/release.py
```

(or tell the agent you're working with that you've just published). It dates
the `## Unreleased` section of `CHANGELOG.md`, commits and tags it
(`release-YYYY-MM-DD`) and pushes. gnomecode.com reads `CHANGELOG.md` from
GitHub every hour and shows each release in the game's update log, so set the
game's **Repository** on the dashboard once. To correct a release, edit its
section and push.

## Checking your work

```sh
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json \
  --base-luaurc=.luaurc --ignore="Packages/**" src
```

`globalTypes.d.luau` is the Roblox API surface for the type checker. Refresh it
when new API shows up:

```sh
curl -o globalTypes.d.luau \
  https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
```

[DataService]: https://github.com/leifstout/DataService
