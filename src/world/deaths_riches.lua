local db = require("src/database/db")
local line_of_sight = require("src/world/line_of_sight")
local office_walls = require("src/world/office_walls")

-- Draws Death's riches: game models on a screen layer, moved every frame so
-- they look like they stand in Death's office. Each spot's models are in a
-- small model group centred on where the game draws the spot. Models in a
-- group are drawn as a 3D scene through the group's own camera, which looks at
-- them from the same direction and distance as the game's camera looks at the
-- spot, so they turn and tilt like the world around them. The groups are part
-- of the interface, so walls and players never hide the riches.
local deaths_riches = {}

local subscription_name = "deaths-riches"

-- How much bigger than real life the riches look in the world.
local riches_size = 1.5

-- A place in the world where riches are drawn. The tile and the items are kept
-- as plain values (the arguments for CoordGrid.new, and names in id.Model),
-- so nothing from the game is needed until the riches are drawn.
---@class RichesSpot
---@field tile integer[] Arguments for CoordGrid.new
---@field height number How far above the ground there the riches float
---@field items string[] The riches' models, as names in id.Model, drawn together
---@field item_scale number How big the items are drawn
---@field offset? number[] How far from the middle of the tile, as { x, z } in fine units (a tile is 512 wide)
---@field rotation? number How far the items are turned around the vertical, in degrees
---@field visible_height? number How tall the riches are, in fine units. Used to show the part sticking up over low walls like Death's desk; without it, riches whose bottom is hidden are hidden whole.

---@type RichesSpot
local desk = { tile = { 0, 6, 10, 29, 38 }, height = 1150, items = { "INV_PARTYHAT" }, item_scale = 1 }
-- Furniture models didn't tilt right when every model faced the camera on its
-- own. In a model group they're seen from the camera's direction like
-- everything else, so they should work now (not tried yet).
---@type RichesSpot
local top_left_corner = { tile = { 0, 6, 10, 26, 42 }, height = 0, items = { "INV_GOLDPEICES_10000" }, item_scale = 1 }
local beside_death = { tile = { 0, 6, 10, 32, 40 }, height = 0, items = { "HUMAN_FURNITURE_GOLD_PILE_PLINTH", "HUMAN_FURNITURE_GOLD_PILE_COINS_HUGE" }, item_scale = 1, visible_height = 1800 }

---@type RichesSpot[]
local riches_spots = { desk, top_left_corner, beside_death }

-- Further than this from a spot, the camera can't be in Death's office, so its
-- riches are hidden. The camera was about 3,000-10,000 away in the office.
local max_camera_distance = 30000

-- The player counts as in Death's office within this many tiles of his desk.
-- The furthest point in the office is about 28 tiles away.
local office_radius = 40
-- Fine coordinates per tile.
local tile_size = 512

-- How big each spot's model group is on screen, in pixels. Riches that grow
-- past it are cut off at its edges.
local view_size = 800

-- The game's field of view isn't in the API, so it's worked out from where the
-- game draws a point beside the camera's focus (see measure_fov). The point is
-- this part of the camera's distance to the side: far enough that whole pixels
-- don't throw the measurement off much, and close enough to stay on screen
-- when the camera is close (a fixed distance went off screen and shrank the
-- riches).
-- Until a measurement has worked, the default is used. After the first one,
-- each measurement only moves the field of view part of the way, so it
-- doesn't make the riches jitter.
local default_fov = 60
local fov_probe_share = 0.25
local fov_smoothing = 0.05

-- Which way a positive roll turns a group's camera isn't in the docs. If the
-- riches turn the wrong way when looking down, try -1.
local roll_sign = 1

-- How many times the search for where riches show over a low wall halves
-- the gap; 8 gets within 1/256 of their visible_height.
local seen_height_search_steps = 8

-- The groups' cameras only draw what's between these distances from them.
local near_clip = 10
local far_clip = 60000

local root
local game_fov = default_fov
local fov_measured = false

-- A spot's model group, with its camera and one model per item. The group
-- keeps a copy of a camera when it's added, so camera is changed and then
-- swapped in for the group's (see use_camera). The group is in a layer of its
-- own, which cuts off the part of the riches that's behind a low wall (see
-- draw_spot); the layer is what's moved and hidden.
---@class SpotView
---@field layer table
---@field group table
---@field camera table
---@field camera_index integer?
---@field models table[]

---@type table<RichesSpot, SpotView>
local spot_views = {}
-- The riches are only drawn while the player is in Death's office, so they
-- don't show up elsewhere in the world. Checked once per game tick.
local in_office = false
-- The middle of the tile the player stands on, also checked once per game
-- tick. Riches on that tile are hidden, so they don't cover the player.
---@type Vector3?
local player_tile

---@param a Vector3
---@param b Vector3
local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

---@param a Vector3
---@param b Vector3
---@return Vector3
local function cross(a, b)
    return Vector3.new(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

---@param from Vector3
---@param to Vector3
---@return Vector3
local function direction(from, to)
    return Vector3.new(to.x - from.x, to.y - from.y, to.z - from.z)
end

---@param vector Vector3
---@return Vector3?
local function normalised(vector)
    local length = math.sqrt(dot(vector, vector))
    if length < 0.0001 then
        return nil
    end
    return Vector3.new(vector.x / length, vector.y / length, vector.z / length)
end

-- The middle of the spot's tile, in fine coordinates.
---@param riches_spot RichesSpot
---@return Vector3
local function tile_position(riches_spot)
    return CoordGrid.new(table.unpack(riches_spot.tile)):ToCoordFine(true).position
end

-- Replaces the group's camera with the view's changed copy.
---@param view SpotView
local function use_camera(view)
    if view.camera_index then
        view.group:DeleteCamera(view.camera_index)
    end
    view.camera_index = view.group:AddCamera(view.camera)
    view.group:SwitchCamera(view.camera_index, ui.ModelCameraTransition.NONE, -1, 0)
end

-- The docs call it ui.ModelCamera, but in the game it's ui.ModelCameraInfo.
local function new_camera()
    local camera = ui.ModelCameraInfo.new()
    camera.clearColour = Vector4.new(0, 0, 0, 0) -- see-through, so the game shows behind the riches
    camera.useLookAt = true
    camera:SetFOV(default_fov, 0)
    camera:SetClipPlanes(near_clip, far_clip)
    return camera
end

-- The riches stand in the middle of the group's scene, at their real size.
---@param riches_spot RichesSpot
---@return SpotView
local function create_view(riches_spot)
    local layer = ui.Layer.new(root)
    layer:SetSize(view_size, view_size)
    layer.hidden = true
    local group = ui.ModelGroup.new(layer)
    group:SetPos(0, 0)
    group:SetSize(view_size, view_size)
    local view = { layer = layer, group = group, camera = new_camera(), models = {} }
    use_camera(view)

    local size = riches_spot.item_scale * riches_size
    for _, item in ipairs(riches_spot.items) do
        local model = ui.Model.new(group)
        -- A component without a size is invisible. In the docs' example the
        -- models in a group are as big as the group.
        model:SetSize(view_size, view_size)
        model:SetModel(ui.ModelType.MODEL, id.Model[item])
        local yaw = math.rad(riches_spot.rotation or 0)
        model:SetTransform(Vector3.new(0, 0, 0), Vector3.new(yaw, 0, 0), Vector3.new(size, size, size), 0)
        table.insert(view.models, model)
    end
    return view
end

local function create_views()
    root = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    for _, riches_spot in ipairs(riches_spots) do
        spot_views[riches_spot] = create_view(riches_spot)
    end
end

-- ScreenConvert can also give a point far outside the screen instead of nil,
-- e.g. while the camera hasn't settled after loading.
local function is_on_screen(point)
    return point ~= nil
        and point.x >= 0 and point.x <= root.width
        and point.y >= 0 and point.y <= root.height
end

-- The game's vertical field of view, in degrees, worked out from how far to
-- the side the game draws a point beside the camera's focus: the narrower the
-- view, the further out it shows. The point is to the side, not above, as
-- sideways is always across the screen; looking down, a point above the focus
-- came out only a pixel or two from it, which made the riches grow. Assumes
-- pixels are as wide as they're high. nil when it can't be worked out.
---@param camera_position Vector3
---@param focus Vector3
---@return number?
local function measure_fov(camera_position, focus)
    local to_focus = direction(camera_position, focus)
    local distance = math.sqrt(dot(to_focus, to_focus))
    local forward = normalised(to_focus)
    local right = forward and normalised(cross(forward, Vector3.new(0, 1, 0)))
    if not right then
        return nil
    end

    local sideways = distance * fov_probe_share
    local beside = Vector3.new(focus.x + right.x * sideways, focus.y, focus.z + right.z * sideways)
    local focus_on_screen = ScreenConvert.Vector3ToScreen(focus)
    local beside_on_screen = ScreenConvert.Vector3ToScreen(beside)
    if not is_on_screen(focus_on_screen) or not is_on_screen(beside_on_screen) then
        return nil
    end
    local pixels_aside = math.abs(beside_on_screen.x - focus_on_screen.x)
    if pixels_aside == 0 then
        return nil
    end

    local tan_half_fov = sideways / distance * (root.height / 2) / pixels_aside
    return 2 * math.deg(math.atan(tan_half_fov))
end

local function update_game_fov()
    local measured = measure_fov(Camera.GetPosition(), Camera.GetFocusPosition())
    if measured and fov_measured then
        game_fov = game_fov + (measured - game_fov) * fov_smoothing
    elseif measured then
        game_fov = measured
        fov_measured = true
    end
end

-- The field of view that makes a group show its riches as big as the game
-- would: the game's view spans the screen's height, a group's only its own.
---@return number
local function view_fov()
    local tan_half = math.tan(math.rad(game_fov) / 2) * view_size / root.height
    return 2 * math.deg(math.atan(tan_half))
end

-- Where in the world the riches at the given spot are drawn. nil while the
-- ground there hasn't loaded yet, which shows as a height of 0 or -1 for the
-- first frames after entering the office. Worked out every frame, so the
-- right height is picked up as soon as it's there.
---@param riches_spot RichesSpot
---@return Vector3?
local function find_spot(riches_spot)
    local middle = tile_position(riches_spot)
    local offset = riches_spot.offset or { 0, 0 }
    local x, z = middle.x + offset[1], middle.z + offset[2]
    local ground_height = World.GetGroundHeight(0, x, z)
    if ground_height <= 0 then
        return nil
    end
    return Vector3.new(x, ground_height + riches_spot.height, z)
end

-- The up direction on screen of a camera looking along forward, which (like
-- the game's camera) never rolls to the side. nil when looking straight up or
-- down, where up isn't defined.
---@param forward Vector3 Normalised
---@return Vector3?
local function screen_up(forward)
    local right = normalised(cross(forward, Vector3.new(0, 1, 0)))
    return right and cross(right, forward)
end

-- How far, in radians, a group's camera has to roll so that up on its screen
-- is up on the game's screen. The group's camera looks straight at its spot,
-- so without the roll its up comes from the direction to the spot, not from
-- the way the game's camera faces. Looking almost straight down those are far
-- apart, and the riches stayed put on screen while the world turned around them.
---@param spot Vector3
---@param camera_position Vector3
---@param focus Vector3
---@return number
local function view_roll(spot, camera_position, focus)
    local to_spot = normalised(direction(camera_position, spot))
    local game_forward = normalised(direction(camera_position, focus))
    local view_up = to_spot and screen_up(to_spot)
    local game_up = game_forward and screen_up(game_forward)
    if not view_up or not game_up then
        return 0
    end
    -- The game's up, flattened onto the group's screen.
    local along = dot(game_up, to_spot)
    local wanted_up = Vector3.new(game_up.x - to_spot.x * along, game_up.y - to_spot.y * along, game_up.z - to_spot.z * along)
    return math.atan(dot(cross(view_up, wanted_up), to_spot), dot(view_up, wanted_up))
end

-- Where a tile in Death's office is, in fine coordinates. Whole numbers are a
-- tile's middle; fractions go that part of a tile further, so 23.5 is the
-- border between tiles 23 and 24.
---@param tile number[] { local tile x, local tile z }
---@return Vector3
local function office_tile_middle(tile)
    local square_x, square_z = office_walls.map_square[1], office_walls.map_square[2]
    local whole_x, whole_z = math.floor(tile[1]), math.floor(tile[2])
    local middle = CoordGrid.new(0, square_x, square_z, whole_x, whole_z):ToCoordFine(true).position
    return Vector3.new(middle.x + (tile[1] - whole_x) * tile_size, middle.y, middle.z + (tile[2] - whole_z) * tile_size)
end

-- The corners of a wall box in the world, or nil while the ground there
-- hasn't loaded yet.
---@param box WallBox
---@return Vector3? min
---@return Vector3? max
local function wall_corners(box)
    local first, second = office_tile_middle(box.from), office_tile_middle(box.to)
    -- The positions are the tiles' middles, and the box covers the whole tiles.
    local half_tile = tile_size // 2
    local min_x, max_x = math.min(first.x, second.x) - half_tile, math.max(first.x, second.x) + half_tile
    local min_z, max_z = math.min(first.z, second.z) - half_tile, math.max(first.z, second.z) + half_tile
    local ground_height = World.GetGroundHeight(0, math.floor((min_x + max_x) / 2), math.floor((min_z + max_z) / 2))
    if ground_height <= 0 then
        return nil, nil
    end
    return Vector3.new(min_x, ground_height, min_z), Vector3.new(max_x, ground_height + box.height, max_z)
end

-- Where a wall line starts and ends, on the ground, or nil while the ground
-- there hasn't loaded yet.
---@param wall WallLine
---@return Vector3? wall_start
---@return Vector3? wall_end
local function wall_ends(wall)
    local first, second = office_tile_middle(wall.from), office_tile_middle(wall.to)
    local ground_height = World.GetGroundHeight(0, math.floor((first.x + second.x) / 2), math.floor((first.z + second.z) / 2))
    if ground_height <= 0 then
        return nil, nil
    end
    return Vector3.new(first.x, ground_height, first.z), Vector3.new(second.x, ground_height, second.z)
end

-- Whether a wall box or line is between the camera and the spot. A box the
-- spot is inside doesn't count, or riches standing against a wall would never
-- show.
---@param camera_position Vector3
---@param spot Vector3
---@return boolean
local function is_behind_wall(camera_position, spot)
    for _, box in ipairs(office_walls.boxes) do
        local min, max = wall_corners(box)
        if min and max and not line_of_sight.is_inside_box(spot, min, max)
            and line_of_sight.passes_through_box(camera_position, spot, min, max) then
            return true
        end
    end
    for _, wall in ipairs(office_walls.walls) do
        local wall_start, wall_end = wall_ends(wall)
        if wall_start and wall_end and line_of_sight.passes_through_wall(camera_position, spot,
            wall_start, wall_end, wall_start.y, wall_start.y + wall.height) then
            return true
        end
    end
    return false
end

-- Has the game draw each wall box and line as a wireframe, on top of everything.
local function draw_walls()
    for _, box in ipairs(office_walls.boxes) do
        local min, max = wall_corners(box)
        if min and max then
            ShapeList.Draw({
                shapePositions = {
                    Vector3.new(min.x, min.y, min.z), Vector3.new(max.x, min.y, min.z),
                    Vector3.new(max.x, min.y, max.z), Vector3.new(min.x, min.y, max.z),
                    Vector3.new(min.x, max.y, min.z), Vector3.new(max.x, max.y, min.z),
                    Vector3.new(max.x, max.y, max.z), Vector3.new(min.x, max.y, max.z),
                },
                -- The bottom square, the top square, and the four edges between them.
                shapeLines = { 0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7 },
                ignoreDepth = true,
                colour = 0xFF8800FF,
                lineWidth = 2,
            })
        end
    end
    for _, wall in ipairs(office_walls.walls) do
        local wall_start, wall_end = wall_ends(wall)
        if wall_start and wall_end then
            local top = wall_start.y + wall.height
            ShapeList.Draw({
                shapePositions = {
                    wall_start, wall_end,
                    Vector3.new(wall_end.x, top, wall_end.z), Vector3.new(wall_start.x, top, wall_start.z),
                },
                -- The outline, and a cross so it reads as a panel.
                shapeLines = { 0, 1, 1, 2, 2, 3, 3, 0, 0, 2, 1, 3 },
                ignoreDepth = true,
                colour = 0xFF8800FF,
                lineWidth = 2,
            })
        end
    end
end

---@param riches_spot RichesSpot
---@return boolean
local function is_player_on(riches_spot)
    local middle = tile_position(riches_spot)
    return player_tile ~= nil and player_tile.x == middle.x and player_tile.z == middle.z
end

-- How far up the riches the camera starts to see them, over whatever wall is
-- in the way: 0 when nothing is in the way, nil when they're hidden all the
-- way up to visible_height. In between, it's found by halving the gap between
-- a hidden and a seen height a few times.
---@param camera_position Vector3
---@param spot Vector3
---@param visible_height number
---@return number?
local function lowest_seen_height(camera_position, spot, visible_height)
    local function hidden_at(height)
        return is_behind_wall(camera_position, Vector3.new(spot.x, spot.y + height, spot.z))
    end
    if not hidden_at(0) then
        return 0
    end
    if visible_height <= 0 or hidden_at(visible_height) then
        return nil
    end
    local hidden, seen = 0, visible_height
    for _ = 1, seen_height_search_steps do
        local middle = (hidden + seen) / 2
        if hidden_at(middle) then
            hidden = middle
        else
            seen = middle
        end
    end
    return seen
end

-- How many rows of the layer, from its top, to show: down to where the
-- riches go behind a low wall, or all of them when nothing is in the way.
---@param spot Vector3
---@param seen_from number lowest_seen_height
---@param layer_top integer
---@return integer
local function rows_to_show(spot, seen_from, layer_top)
    if seen_from == 0 then
        return view_size
    end
    local cut = ScreenConvert.Vector3ToScreen(Vector3.new(spot.x, spot.y + seen_from, spot.z))
    if not cut then
        return view_size
    end
    return math.max(0, math.min(view_size, math.floor(cut.y) - layer_top))
end

---@param riches_spot RichesSpot
local function draw_spot(riches_spot)
    local view = spot_views[riches_spot]
    local spot = find_spot(riches_spot)
    if not spot or is_player_on(riches_spot) then
        view.layer.hidden = true
        return
    end

    local camera_position = Camera.GetPosition()
    local from_spot_to_camera = direction(spot, camera_position)
    local on_screen = ScreenConvert.Vector3ToScreen(spot)
    local seen_from = lowest_seen_height(camera_position, spot, riches_spot.visible_height or 0)
    if math.sqrt(dot(from_spot_to_camera, from_spot_to_camera)) > max_camera_distance or not is_on_screen(on_screen)
        or not seen_from then
        view.layer.hidden = true
        return
    end

    local layer_top = math.floor(on_screen.y) - view_size // 2
    view.layer:SetPos(math.floor(on_screen.x) - view_size // 2, layer_top)
    view.layer:SetSize(view_size, rows_to_show(spot, seen_from, layer_top))
    view.camera:SetPosition(from_spot_to_camera, 0)
    view.camera:SetLookAt(Vector3.new(0, 0, 0), 0)
    local roll = view_roll(spot, camera_position, Camera.GetFocusPosition())
    view.camera:SetYawPitchRoll(Vector3.new(0, 0, roll * roll_sign), 0)
    view.camera:SetFOV(view_fov(), 0)
    use_camera(view)
    view.layer.hidden = false
end

local function draw()
    if not (in_office and World.IsAvailable() and Camera.IsAvailable()) then
        for _, view in pairs(spot_views) do
            view.layer.hidden = true
        end
        return
    end

    update_game_fov()
    for _, riches_spot in ipairs(riches_spots) do
        draw_spot(riches_spot)
    end
    if office_walls.show then
        draw_walls()
    end
end

-- How many tiles a position is from Death's desk, ignoring height.
---@param position Vector3
---@return number
local function tiles_from_desk(position)
    local desk_position = tile_position(desk)
    return math.sqrt((position.x - desk_position.x) ^ 2 + (position.z - desk_position.z) ^ 2) / tile_size
end

-- TEMPORARY: prints the tile the player stands on whenever it changes, to
-- find the tiles for the boxes in office_walls.
local printed_tile
local function print_player_tile()
    local tile = Player.GetEntity().coordGrid
    local text = string.format("[Riches debug] standing on %s, %s (map square %s, %s)",
        tile.localX, tile.localZ, tile.mapSquareX, tile.mapSquareZ)
    if text ~= printed_tile then
        printed_tile = text
        print(text)
    end
end

local function check_office()
    print_player_tile()
    player_tile = Player.GetEntity().coordGrid:ToCoordFine(true).position
    in_office = tiles_from_desk(player_tile) <= office_radius
end

function deaths_riches.start()
    if db.get_render_deaths_riches() == false then
        return
    end
    -- Already started, so its models are already there.
    if root then
        return
    end
    create_views()
    Event.Draw.Subscribe(subscription_name, draw)
    Event.ServerLogic.Subscribe(subscription_name, check_office)
end

function deaths_riches.stop()
    Event.Draw.Unsubscribe(subscription_name)
    Event.ServerLogic.Unsubscribe(subscription_name)
    for _, view in pairs(spot_views) do
        for _, model in ipairs(view.models) do
            model:Destroy()
        end
        view.group:Destroy()
        view.layer:Destroy()
    end
    spot_views = {}
    game_fov = default_fov
    fov_measured = false
    root = nil
    in_office = false
    player_tile = nil
end

return deaths_riches
