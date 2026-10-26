-- The walls and pillars in Death's office that riches should hide behind. The
-- riches are drawn on top of the game, so the game can't hide them; instead a
-- spot's riches are hidden while the line from the camera to them passes
-- through one of these boxes or walls.
local office_walls = {}

-- Death's office is in this map square, so the boxes and walls only give local
-- tiles. Whole numbers are a tile's middle, and fractions go that part of a
-- tile further: 23.5 is the border between tiles 23 and 24, and a box from
-- 23.5 starts half a tile later than one from 23.
office_walls.map_square = { 6, 10 }

-- A box covering whole tiles, from one corner tile to the other (both
-- included), going up from the ground.
---@class WallBox
---@field from number[] { local tile x, local tile z } of one corner
---@field to number[] { local tile x, local tile z } of the opposite corner
---@field height number How high the box goes above the ground, in fine units (a tile is 512 wide)

-- To add one, stand next to the wall in game and read the tile from the
-- "[Riches debug] standing on" print, then check the box with show below.
---@type WallBox[]
office_walls.boxes = {
    -- Deaths desk
    { from = {28, 38}, to = {32, 38}, height = 1100},
}

-- A thin, straight wall, from the middle of one tile to the middle of another,
-- going up from the ground. Unlike boxes, these can run diagonally, and a
-- curved wall can be made of a few short ones.
---@class WallLine
---@field from number[] { local tile x, local tile z } where the wall starts
---@field to number[] { local tile x, local tile z } where the wall ends
---@field height number How high the wall goes above the ground, in fine units (a tile is 512 wide)

-- Added the same way as boxes.
---@type WallLine[]
-- The windows curve around Death's desk from the War's Retreat door (22, 37)
-- to the Closure's Study door (38, 37). The office is the same on both sides
-- of x = 30 (the middle of the desk and of Death's chair), so the east half
-- mirrors the west half, and the top runs through Death's door (the big
-- statue window, tiles 28-31 at z = 44).
office_walls.walls = {
    -- West half
    { from = {23, 38}, to = {23, 39}, height = 3500},
    { from = {23, 39}, to = {23, 40}, height = 3000},
    { from = {23, 40}, to = {24, 41}, height = 2000},
    { from = {24, 41}, to = {26, 43}, height = 2000},
    -- Top, through Death's door
    { from = {26, 43}, to = {28, 44}, height = 3000},
    { from = {28, 44}, to = {31, 44}, height = 5000},
    { from = {31, 44}, to = {32, 44}, height = 4500},
    { from = {32, 44}, to = {33, 43.5}, height = 3000},
    { from = {33, 43.5}, to = {33.5, 43.5}, height = 3500},
    { from = {33.5, 43.4}, to = {34, 43}, height = 4000},
    -- East half, the west half mirrored
    { from = {34, 43}, to = {35, 42}, height = 4000},
    { from = {35, 42}, to = {35.5, 41.5}, height = 3000},
    { from = {35.5, 41.5}, to = {36, 41}, height = 2000},
    { from = {36, 41}, to = {37, 40}, height = 3000},
    { from = {37, 40}, to = {37, 39}, height = 3000},
    { from = {37, 39}, to = {37, 38}, height = 3500},
}

-- Draws the boxes and walls in game as wireframes, to check they cover the walls.
office_walls.show = true

return office_walls
