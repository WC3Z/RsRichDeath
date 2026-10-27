-- Where Death's riches are drawn in his office, and what they are.
local riches_spots = {}

-- A place in the world where riches are drawn. The tile and the items are kept
-- as plain values (the arguments for CoordGrid.new, and names in id.Model),
-- so nothing from the game is needed until the riches are drawn.
---@class RichesSpot
---@field tile number[] Arguments for CoordGrid.new: level, map square x and z, then the local tile x and z, which can have fractions (35 is the middle of tile 35, 35.5 the border with tile 36)
---@field height number How far above the ground there the riches float
---@field items string[] The riches' models, as names in id.Model, drawn together
---@field item_scale number How big the items are drawn
---@field offset? number[] How far from the middle of the tile, as { x, z } in fine units (a tile is 512 wide)
---@field rotation? number How far the items are turned around the vertical, in degrees
---@field visible_height? number How tall the riches are, in fine units. Used to show the part sticking up over low walls like Death's desk; without it, riches whose bottom is hidden are hidden whole.
---@field visible_width? number How wide the riches are, in fine units. With strips, their width is split into the strips, so each strip covers the same part of them however big they are on screen; without it, the whole view is split.
---@field occluders? string[] EXPERIMENT: config names of locs near the spot (like Death's desk, "BSLAY_2014_DESKBASE") whose models are drawn in the riches' groups too, so the group itself hides the riches behind them, edge for edge.
---@field strips? integer The most side-by-side strips the riches are drawn in (1 if not given); the "Hiding detail" slider picks how many, up to this. Each strip is cut off on its own, so the riches can go behind a slanted wall edge or part of the way behind a pillar. Each strip draws the models again, which costs frame rate.

-- Death's desk, which the player has to be near for the riches to show.
riches_spots.desk_tile = { 0, 6, 10, 29, 38 }

---@type RichesSpot[]
riches_spots.spots = {
    -- On Death's desk
    { tile = { 0, 6, 10, 29, 38 }, height = 1150, items = { "INV_PARTYHAT" }, item_scale = 1, visible_height = 100 },
    -- Top left corner
    { tile = { 0, 6, 10, 26, 42 }, height = 0, items = { "INV_GOLDPEICES_10000" }, item_scale = 1, visible_height = 250 },
    -- East of Death's desk. It was beside Death, behind the desk, but hiding it
    -- well behind the desk was too hard there. Furniture models didn't tilt
    -- right when every model faced the camera on its own; in a model group
    -- they're seen from the camera's direction like everything else, so they
    -- work now.
    {
        tile = { 0, 6, 10, 34, 40 }, height = 0,
        items = { "HUMAN_FURNITURE_GOLD_PILE_PLINTH", "HUMAN_FURNITURE_GOLD_PILE_COINS_HUGE" }, item_scale = 1,
        visible_height = 1800, visible_width = 900, strips = 8,
        -- EXPERIMENT, off: hides the hoard behind a copy of Death's desk model,
        -- edge for edge, but the copy can't be made invisible (alpha, colour
        -- and rgba are ignored, and the material swap in deaths_riches needs
        -- the desk's material IDs, which the API doesn't give).
        --occluders = { "BSLAY_2014_DESKBASE" },
    },
}

return riches_spots
