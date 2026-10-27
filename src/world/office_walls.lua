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

-- Thick walls grow away from this tile (see WallLine's thickness): the middle
-- of Death's desk.
office_walls.middle = { 30, 38 }

-- A box covering whole tiles, from one corner tile to the other (both
-- included), going up from the ground.
---@class WallBox
---@field from    number[] { local tile x, local tile z } of one corner
---@field to      number[] { local tile x, local tile z } of the opposite corner
---@field height  number   How high the box goes above the ground, in fine units (a tile is 512 wide)
---@field offset? number   Moves the whole box up, or down when negative, in fine units

-- To add one, stand next to the wall in game and read the tile from the
-- "[Riches debug] standing on" print, then check the box with show below.
---@type WallBox[]
office_walls.boxes = {
    -- Deaths desk
    { from = { 27.8, 38 }, to = { 32.2, 38.3 }, height = 1130 },
    -- The candles on Deaths desk are pillars now (see office_walls.pillars);
    -- these were the boxes around them.
    --{ from = { 28.3, 38 }, to = { 28.3, 38 }, height = 600, offset = 1130 },
    --{ from = { 32, 38 }, to = { 32, 38 }, height = 600, offset = 1130 }
}

-- A thin, straight wall, from the middle of one tile to the middle of another,
-- going up from the ground. Unlike boxes, these can run diagonally, and a
-- curved wall can be made of a few short ones.
-- A third number in from or to is how high the wall is at that end, so the
-- top can slope: { from = { 23, 40, 3000 }, to = { 24, 41, 2000 } }. An end
-- without one uses height. With arch, the top curves up from the ends'
-- heights to the arch's height in the middle, in the pointed shape of the
-- office's windows: { from = { 23, 39, 2500 }, to = { 24, 41, 2500 }, arch = 4200 }.
---@class WallLine
---@field from       number[]      { local tile x, local tile z, height? } where the wall starts
---@field to         number[]      { local tile x, local tile z, height? } where the wall ends
---@field height?    number        How high the wall goes above the ground, in fine units (a tile is 512 wide), at ends without their own
---@field arch?      number        How high the top of a pointed arch is above the ground, in the middle of the wall
---@field offset?    number        Moves the whole wall up, or down when negative, in fine units; its heights are measured from there
---@field thickness? number        How thick the wall is, in fine units, growing from the mapped line away from office_walls.middle (towards it when negative)
---@field openings?  WallOpening[] Holes through the wall, like doorways or the gap under a freestanding arch

-- A hole through a wall line, from one side to the other (both on the floor,
-- placed along the wall where they land), going up from the wall's bottom.
-- Like walls, it can have a pointed arch on top: its sides go straight up to
-- height, then curve to arch in the middle. Without arch the top is flat.
-- Example, a doorway: { from = { 37, 32.4 }, to = { 37, 34.6 }, height = 2000, arch = 3400 }
---@class WallOpening
---@field from    number[] { local tile x, local tile z } of one side
---@field to      number[] { local tile x, local tile z } of the other side
---@field height  number   How high its sides go above the wall's bottom, in fine units
---@field arch?   number   How high the top of its pointed arch is above the wall's bottom
---@field bottom? number   How high above the wall's bottom it starts, like a window sill (0 if not given)

-- Added the same way as boxes. Each wall goes west to east (x grows), or, if
-- it runs more north-south than east-west, north to south (z shrinks); north
-- is +z. The direction doesn't change how a wall works, it just keeps them
-- easy to read. tests/world/office_walls_test.lua checks it.
--
-- The windows curve around Death's desk from the War's Retreat door (22, 37)
-- to the Closure's Study door (38, 37). The office is the same on both sides
-- of x = 30 (the middle of the desk and of Death's chair), so the east half
-- mirrors the west half, and the top runs through Death's door (the big
-- statue window, tiles 28-31 at z = 44).
---@type WallLine[]
office_walls.walls = {
    -- Outer walls

    -- Wall from the eastern most window to the eastern most wall (west to east)
    { from = { 37, 37.8 }, to = { 43, 37.8 }, height = 2000, thickness = 500 },
    -- Eastern most wall (north to south)
    { from = { 43, 37.8 }, to = { 43, 31 }, height = 2000, thickness = 250, offset = -100 },
    -- South wall, east of the middle (west to east)
    { from = { 32.5, 31 }, to = { 43.5, 31 }, height = 2000, thickness = 250, offset = -550 },
    -- South wall, west of the middle (west to east)
    { from = { 17, 31 }, to = { 27.5, 31 }, height = 2000, thickness = 250, offset = -550 },
    -- Western most wall (north to south)
    { from = { 17, 37.5 }, to = { 17, 30.5 }, height = 2000, thickness = 250, offset = -550 },
    -- Wall from the western most wall to the western most window (west to east)
    { from = { 17, 37.5 }, to = { 23.5, 37.5 }, height = 2000, thickness = 250 },

    -- Freestanding arches, from west to east. GUESSED: they span from the
    -- north wall (z = 37.8) to the south wall (z = 31), are about 200 thick
    -- and about as tall as Death's door (peak 5300). The opening under each
    -- leaves legs about 0.4 tiles wide and a band about 300 thick on top.

    -- Arch on the western most wall (north to south): the eastern most one
    -- mirrored around x = 30, starting at the west side's north wall (z = 37.5)
    {
        from = { 17, 37.5 },
        to = { 17, 30.5 },
        height = 2500,
        arch = 4500,
        thickness = 200,
        openings = { { from = { 17, 37.1 }, to = { 17, 31 }, height = 2300, arch = 4250 } }
    },
    -- First arch on the western side: the first eastern one mirrored
    {
        from = { 20.2, 37.5 },
        to = { 20.2, 30.5 },
        height = 2500,
        arch = 5100,
        thickness = 200,
        openings = { { from = { 20.2, 37.1 }, to = { 20.2, 31 }, height = 2300, arch = 4900 } }
    },
    -- First arch on the eastern side
    {
        from = { 39.8, 37.8 },
        to = { 39.8, 30.5 },
        height = 2500,
        arch = 5100,
        thickness = 200,
        openings = { { from = { 39.8, 37.4 }, to = { 39.8, 31 }, height = 2300, arch = 4900 } }
    },
    -- Arch on the eastern most wall (north to south)
    {
        from = { 43, 37.8 },
        to = { 43, 30.5 },
        height = 2500,
        arch = 5000,
        thickness = 200,
        openings = { { from = { 43, 37.4 }, to = { 43, 31 }, height = 2300, arch = 4700 } }
    },

    -- Windows and Death's door, from west to east

    -- Western most window (north to south)
    { from = { 24, 41, 3000 }, to = { 23.5, 37.5, 3000 }, arch = 3600, offset = -700, thickness = 250 },
    -- Small gap between windows (north to south)
    { from = { 24.45, 41.5 }, to = { 24, 41 }, height = 2800, offset = -700, thickness = 250 },
    -- Second window from west (west to east)
    { from = { 24.45, 41.5, 3000 }, to = { 27.25, 43.5, 3000 }, arch = 4200, offset = -700, thickness = 250 },
    -- Death's door (west to east)
    { from = { 27.25, 43.5, 2300 }, to = { 32.5, 43.5, 2700 }, arch = 5300, thickness = 250 },
    -- Second window from the east (west to east)
    { from = { 32.5, 43.5, 2700 }, to = { 35, 41, 2700 }, arch = 4100, offset = -700, thickness = 250 },
    -- Small gap between windows (west to east)
    { from = { 35, 41 }, to = { 35.5, 41 }, height = 2800, offset = -700, thickness = 250 },
    -- Eastern most window (north to south)
    { from = { 35.5, 41, 3000 }, to = { 36.5, 37.5, 3000 }, arch = 3800, offset = -700, thickness = 250 }
}

-- A standing cylinder, like a candle or a round pillar: round seen from
-- above, the same size all the way up, going up from the ground. Unlike boxes,
-- it can be any size, and riches show through the gaps between them.
---@class WallPillar
---@field at      number[] { local tile x, local tile z } of its middle
---@field radius  number   In fine units (a tile is 512 wide)
---@field height  number   How high it goes above the ground, in fine units
---@field offset? number   Moves it up, or down when negative, in fine units, like onto a desk

-- The candles on Death's desk, standing on it (1130 up). Their places are
-- measured with Shift+M looking straight down; their heights are a first
-- guess, still to be tuned (Shift+H gives one from the floor, so take off the
-- desk's 1130).
---@type WallPillar[]
office_walls.pillars = {
    -- Western candles
    { at = { 28.30, 37.83 }, radius = 45, height = 300, offset = 1130 },
    { at = { 28.15, 38.35 }, radius = 45, height = 450, offset = 1130 },
    { at = { 28.25, 38.25 }, radius = 55, height = 400, offset = 1130 },
    { at = { 28.08, 38.05 }, radius = 55, height = 600, offset = 1130 },
    { at = { 27.93, 38.27 }, radius = 55, height = 600, offset = 1130 },
    -- Eastern candles
    { at = { 32.09, 37.76 }, radius = 45, height = 300, offset = 1130 },
    { at = { 31.82, 38.02 }, radius = 55, height = 400, offset = 1130 },
    { at = { 31.59, 38.03 }, radius = 45, height = 400, offset = 1130 },
    { at = { 31.50, 38.12 }, radius = 45, height = 250, offset = 1130 },
    { at = { 31.67, 38.27 }, radius = 55, height = 450, offset = 1130 },
    { at = { 32.06, 38.27 }, radius = 55, height = 600, offset = 1130 },
}

-- Whether the boxes and walls are drawn in game as wireframes, to check they
-- cover the walls. Set from the "Show wall outlines" checkbox.
office_walls.show = false

return office_walls
