-- A debug tool for mapping the walls in office_walls, on while "Show wall
-- outlines" is ticked. The API has no mouse click event, so it uses keys:
--   Shift+M  prints the tile under the mouse, with fractions, ready to use in
--            a box or wall.
--   Shift+H  prints how high the mouse is above the last Shift+M point, to
--            measure a wall's height: point at its top, straight above.
local office_walls = require("src/world/office_walls")

local wall_measure = {}

local subscription_name = "rich-death-wall-measure"

-- Fine coordinates per tile.
local tile_size = 512
-- Shift+H searches for the height up to this, in fine units.
local max_height = 10000
-- How many times the height search halves the gap; 14 gets within 1 unit.
local height_search_steps = 14

-- The last point measured with Shift+M, on the ground.
---@type Vector3?
local last_point

-- A fine x or z position as a tile number in Death's office, where a whole
-- number is a tile's middle (see office_walls).
---@param fine number
---@param map_square integer
---@return number
function wall_measure.tile_number(fine, map_square)
    return fine / tile_size - map_square * 64 - 0.5
end

local function measure_point()
    local mouse = Mouse.GetPosition()
    local coord = mouse and ScreenConvert.ScreenToCoordFine(mouse)
    if not coord then
        print("[Riches debug] no ground under the mouse")
        return
    end
    local position = coord.position
    local ground_height = World.GetGroundHeight(0, math.floor(position.x), math.floor(position.z))
    last_point = Vector3.new(position.x, ground_height, position.z)
    print(string.format("[Riches debug] mouse at { %.2f, %.2f }",
        wall_measure.tile_number(position.x, office_walls.map_square[1]),
        wall_measure.tile_number(position.z, office_walls.map_square[2])))
end

-- How high above the point the mouse is: the height where the game draws a
-- point straight above it at the mouse's height on screen. Higher points are
-- drawn further up the screen, so it's found by halving the gap a few times.
---@param point Vector3
---@param mouse_y number
---@return number? height nil if it couldn't be worked out
local function height_at_mouse(point, mouse_y)
    local function screen_y(height)
        local on_screen = ScreenConvert.Vector3ToScreen(Vector3.new(point.x, point.y + height, point.z))
        return on_screen and on_screen.y
    end
    local bottom_y, top_y = screen_y(0), screen_y(max_height)
    if not bottom_y or not top_y or mouse_y > bottom_y or mouse_y < top_y then
        return nil
    end
    local low, high = 0, max_height
    for _ = 1, height_search_steps do
        local middle = (low + high) / 2
        local middle_y = screen_y(middle)
        if not middle_y then
            return nil
        end
        if middle_y > mouse_y then
            low = middle
        else
            high = middle
        end
    end
    return (low + high) / 2
end

local function measure_height()
    if not last_point then
        print("[Riches debug] measure a point on the floor with Shift+M first")
        return
    end
    local mouse = Mouse.GetPosition()
    local height = mouse and height_at_mouse(last_point, mouse.y)
    if not height then
        print("[Riches debug] the mouse isn't above the last point, between 0 and " .. max_height)
        return
    end
    print(string.format("[Riches debug] height %d above the last point", math.floor(height + 0.5)))
end

---@param event KeyDownEventPayload
local function on_key_down(event)
    if not office_walls.show or event.isRepeat or (event.modifiers & ModifierKey.SHIFT) == 0 then
        return
    end
    if event.gameKey == GameKey.M then
        measure_point()
    elseif event.gameKey == GameKey.H then
        measure_height()
    end
end

function wall_measure.start()
    Event.KeyDown.Subscribe(subscription_name, on_key_down)
end

function wall_measure.stop()
    Event.KeyDown.Unsubscribe(subscription_name)
    last_point = nil
end

return wall_measure
