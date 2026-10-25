# Rich Death

A RuneScape 3 plugin that keeps track of how much you've paid Death to get your items back.

## Usage

Build the plugin, install PrettyUI, and add the `Rich-Death` folder to the `dev_plugins` folder in the RuneScape-BETA folder.

The plugin asks for the optional **chat access** permission. It needs it to see what you pay Death, so nothing is tracked without it.

## Features

- Adds up the coins you pay at Death's office to retrieve your items, and keeps the total when the plugin or the game is restarted.
- Shows the total death cost on the plugin's page. Large amounts are shortened the way the game shortens stack sizes (`100K`, `9999K`, `10M`, `9999M`, `10B`), with the full amount when you hover over it.
- A **Render Death's riches** setting (on by default) for the planned riches below. It doesn't do anything yet.

## How the death cost is tracked

I have not found a better way to track when you pay Death, so the plugin reads the general chat instead. When the message "You pay 800,000 coins and retrieve your items." appears, 800,000 is added to the total.

This works, but it's a workaround:

- Only payments that produce that exact message are counted. If Jagex changes the wording, tracking stops until the pattern in `src/tracker/death_cost_listener.lua` is updated.
- Deaths before the plugin was installed, or while it wasn't running, aren't counted.

If a better signal turns up (a var, an event or an interface), it should replace the chat message.

## Planned: Death's riches

The idea: as your total death cost passes GP milestones, Death's office fills up with more and more riches, as if he's been spending your money on himself.

This may not be feasible. As far as I know, we cant render object in the game world, so the riches would have to be drawn by the plugin itself. The options found so far:

1. **A model on a screen layer**, moved every frame to where the spot in the office is on screen. This has been prototyped (`model:SetPos`). The world doesn't hide it, so it would show through walls and NPCs.
2. **The plugin's own triangles in the world** (ShapeData). 
3. **Game models from the cache**, turned into ShapeData. This would look best, but Jagex hasn't said whether plugins may read the cache, so it could get the plugin rejected in moderation.

## Dependencies

- [prettyui](https://prettyui.j3.gg/) for the interface

## Building

```
./build.sh
```

This copies the plugin, without the tests, into `Rich-Death/`. To also copy it into your game's `dev_plugins` folder, create `build.local.sh` (see `build.sh`).

## Tests

The tests need Lua 5.4. Run them from the repository root:

```
lua tests/run.lua
```

A pre-commit hook in `.githooks/` runs the tests and stops the commit if any fail. Turn it on once per clone with:

```
git config core.hooksPath .githooks
```

## Project layout

```
main.lua           starts everything
src/database/      saved settings and the death cost total
src/tracker/       reads the chat to find out what was paid to Death
src/interface/     the plugin's page
tests/             tests, mirroring src/, with fakes for the game and prettyui in tests/helpers/
```
