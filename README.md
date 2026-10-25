# Rich Death

A RuneScape 3 plugin that keeps track of how much you've paid Death to get your items back.

## Usage

Build the plugin, install PrettyUI, and add the `Rich-Death` folder to the `dev_plugins` folder in the RuneScape-BETA folder.

The plugin asks for the optional **chat access** permission. It needs it to see what you pay Death, so nothing is tracked without it.

## Features

- Adds up the coins you pay at Death's office to retrieve your items, and keeps the total when the plugin or the game is restarted.
- Shows the total death cost on the plugin's page. Large amounts are shortened the way the game shortens stack sizes (`100K`, `9999K`, `10M`, `9999M`, `10B`), with the full amount when you hover over it.
- A **Render Death's riches** setting (on by default) that turns the work-in-progress riches below on or off.

## How the death cost is tracked

I have not found a better way to track when you pay Death, so the plugin reads the general chat instead. When the message "You pay 800,000 coins and retrieve your items." appears, 800,000 is added to the total.

This works, but it's a workaround:

- Only payments that produce that exact message are counted. If Jagex changes the wording, tracking stops until the pattern in `src/tracker/death_cost_listener.lua` is updated.
- Deaths before the plugin was installed, or while it wasn't running, aren't counted.

If a better signal turns up (a var, an event or an interface), it should replace the chat message.

## Work in progress: Death's riches

The idea: as your total death cost passes GP milestones, Death's office fills up with more and more riches, as if he's been spending your money on himself.

As far as I know, we cant render object in the game world, so the riches have to be drawn by the plugin itself. The options found so far:

1. **A model on a screen layer**, moved every frame to where the spot in the office is on screen. This is what the prototype uses. The world doesn't hide it, so it shows through walls and NPCs.
2. **The plugin's own triangles in the world** (ShapeData).
3. **Game models from the cache**, turned into ShapeData. This would look best, but Jagex hasn't said whether plugins may read the cache, so it could get the plugin rejected in moderation.

### The prototype

`src/world/deaths_riches.lua` draws a partyhat on Death's desk and a stack of gold pieces in the corner of his office. There are no milestones yet: both are shown whenever the setting is on, whatever the death cost.

How it works:

- **Spots.** Each place riches are drawn is a spot: a tile, a height above the ground, and the items to draw there. Adding a spot is adding one to the `riches_spots` list.
- **Placing.** Each frame, the spot's position is turned into a screen position and the model is moved there. Its zoom follows the camera's distance, so the item keeps its size in the world. The ground height is read every frame, since right after entering the office it reads 0 or -1 for a few frames.
- **Tilting.** A model on its own always faces the camera. Putting the item in an NPC's body slot (any NPC, the item replaces all of him) lets it be rotated, so it tilts with how far the camera looks down on it. Changing a model's rotation means reloading it, which lags behind the camera, so each spot has 31 models, one per 3 degrees of tilt, and the closest one is shown.
- **Loading.** A model only loads once it's shown, and flickers while it does. At start every model is shown for half a second at 1x1 pixel, zoomed far out, so they've all loaded before they're needed.
- **Only in the office.** Once per game tick the plugin checks whether you're within 40 tiles of Death's desk, and only draws the riches then.

Limitations:

- **The riches don't turn as the camera goes around them.** They always show the same side. Turning around the vertical works on its own, but combined with the tilt it leans the item sideways, and a model for every tilt and direction is far too many models. `ui.Model:SetTransform` doesn't change what's drawn.
- **Only inventory models.** Furniture models (like the gold hoard) are oriented differently and never tilted right with the camera.
- **They show through walls and NPCs,** since they're drawn on top of the game.

Until the API offers a better way to draw or rotate models, the riches stay at this prototype.

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
src/world/         Death's riches, drawn into the office (work in progress)
tests/             tests, mirroring src/, with fakes for the game and prettyui in tests/helpers/
```
