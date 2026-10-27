local db = require("src/database/db")
local line_of_sight = require("src/world/line_of_sight")
local office_walls = require("src/world/office_walls")
local riches_spots = require("src/world/riches_spots")
local wall_measure = require("src/world/wall_measure")

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

-- EXPERIMENT: whether the occluder models (see RichesSpot's occluders) are
-- drawn. With false they get alpha 0: if the game still uses them for depth,
-- they hide the riches without a second copy of the desk showing.
local occluders_visible = false
-- How many tiles from a spot its occluder locs are looked for.
local occluder_search_range = 10
-- Which way round a loc's 90 degree rotation turns its model; try -1 if the
-- desk copy is turned the wrong way.
local occluder_yaw_sign = 1

-- How far to the side of a spot a point is drawn to find which way the
-- screen's sideways is there (see screen_sideways), in fine units.
local sideways_probe = 200

-- How many times the search for where riches show over a low wall halves
-- the gap; 8 gets within 1/256 of their visible_height.
local seen_height_search_steps = 8

-- The groups' cameras only draw what's between these distances from them.
local near_clip = 10
local far_clip = 60000

local root
local game_fov = default_fov
local fov_measured = false

-- One side-by-side strip of a spot's riches: a model group with its camera
-- and one model per item. The group keeps a copy of a camera when it's added,
-- so camera is changed and then swapped in for the group's (see use_camera).
-- The group is in a layer of its own, which is only as wide as the strip and
-- cuts off the part of the riches that's behind a low wall (see draw_spot);
-- the layer is what's moved and hidden. The group is the whole view's size,
-- moved left inside the layer so the strip shows its own slice of it.
---@class RichesStrip
---@field layer table
---@field group table
---@field camera table
---@field camera_index integer?
---@field models table[]
---@field occluders OccluderModel[] EXPERIMENT: models of locs drawn to hide the riches behind them
---@field left integer Where the strip starts, in pixels from the view's left edge
---@field width integer In pixels

-- EXPERIMENT: a model of a loc (like Death's desk) drawn in a strip's group, at
-- the loc's place in the world, so the group's own depth hides the riches
-- behind it.
---@class OccluderModel
---@field model table
---@field translation Vector3 Where the model goes in the world, before the riches' spot is taken off
---@field yaw number Radians
---@field scale Vector3

-- A spot's riches, drawn in one or more strips side by side.
---@class SpotView
---@field strips RichesStrip[]

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

-- Replaces the strip's group's camera with its changed copy.
---@param strip RichesStrip
local function use_camera(strip)
    if strip.camera_index then
        strip.group:DeleteCamera(strip.camera_index)
    end
    strip.camera_index = strip.group:AddCamera(strip.camera)
    strip.group:SwitchCamera(strip.camera_index, ui.ModelCameraTransition.NONE, -1, 0)
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
---@param left integer
---@param width integer
---@return RichesStrip
local function create_strip(riches_spot, left, width)
    local layer = ui.Layer.new(root)
    layer:SetSize(width, view_size)
    layer.hidden = true
    local group = ui.ModelGroup.new(layer)
    group:SetPos(-left, 0)
    group:SetSize(view_size, view_size)
    local strip = {
        layer = layer, group = group, camera = new_camera(), models = {}, occluders = {}, left = left, width = width,
    }
    use_camera(strip)

    local size = riches_spot.item_scale * riches_size
    for _, item in ipairs(riches_spot.items) do
        local model = ui.Model.new(group)
        -- A component without a size is invisible. In the docs' example the
        -- models in a group are as big as the group.
        model:SetSize(view_size, view_size)
        model:SetModel(ui.ModelType.MODEL, id.Model[item])
        local yaw = math.rad(riches_spot.rotation or 0)
        model:SetTransform(Vector3.new(0, 0, 0), Vector3.new(yaw, 0, 0), Vector3.new(size, size, size), 0)
        table.insert(strip.models, model)
    end
    return strip
end

---@param riches_spot RichesSpot
---@return SpotView
local function create_view(riches_spot)
    local strip_count = riches_spot.strips or 1
    local strip_width = view_size // strip_count
    local view = { strips = {} }
    for index = 0, strip_count - 1 do
        table.insert(view.strips, create_strip(riches_spot, index * strip_width, strip_width))
    end
    return view
end

---@param view SpotView
local function hide_view(view)
    for _, strip in ipairs(view.strips) do
        strip.layer.hidden = true
    end
end

local function create_views()
    root = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    for _, riches_spot in ipairs(riches_spots.spots) do
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
    local bottom = ground_height + (box.offset or 0)
    return Vector3.new(min_x, bottom, min_z), Vector3.new(max_x, bottom + box.height, max_z)
end

-- Where a wall line starts and ends, at its bottom (the ground, moved by its
-- offset), or nil while the ground there hasn't loaded yet.
---@param wall WallLine
---@return Vector3? wall_start
---@return Vector3? wall_end
local function wall_ends(wall)
    local first, second = office_tile_middle(wall.from), office_tile_middle(wall.to)
    local ground_height = World.GetGroundHeight(0, math.floor((first.x + second.x) / 2), math.floor((first.z + second.z) / 2))
    if ground_height <= 0 then
        return nil, nil
    end
    local bottom = ground_height + (wall.offset or 0)
    return Vector3.new(first.x, bottom, first.z), Vector3.new(second.x, bottom, second.z)
end

-- How far up its arch a pointed (gothic) arch is at a point along it, from 0
-- at its ends to 1 in the middle. Each half is part of a circle centred on
-- the far end, like the office's windows.
---@param along number 0 at one end, 1 at the other
---@return number
local function pointed_arch(along)
    local from_middle = math.abs(2 * along - 1)
    return math.sqrt(4 - (1 + from_middle) ^ 2) / math.sqrt(3)
end

-- How high the top of a wall line is along it, in the world, as a function of
-- how far along (0 at from, 1 at to): straight from one end's height to the
-- other's, plus the arch if it has one, rising to its height in the middle.
---@param wall WallLine
---@param ground_height number
---@return fun(along: number): number
local function wall_top(wall, ground_height)
    local start_top = ground_height + (wall.from[3] or wall.height)
    local end_top = ground_height + (wall.to[3] or wall.height)
    local rise = wall.arch and ground_height + wall.arch - (start_top + end_top) / 2 or 0
    return function(along)
        return start_top + (end_top - start_top) * along + rise * pointed_arch(along)
    end
end

-- How many straight pieces an arched wall's top is drawn with.
local arch_draw_pieces = 12

-- The faces of a wall line, each { start, end } at its bottom: the mapped line
-- itself and, for a thick wall, a copy moved thickness away from the office's
-- middle (towards it when negative). Together they hide what's behind any
-- part of the wall's thickness.
---@param wall WallLine
---@param wall_start Vector3
---@param wall_end Vector3
---@return Vector3[][]
local function wall_faces(wall, wall_start, wall_end)
    local faces = { { wall_start, wall_end } }
    local along_x, along_z = wall_end.x - wall_start.x, wall_end.z - wall_start.z
    local length = math.sqrt(along_x ^ 2 + along_z ^ 2)
    if not wall.thickness or wall.thickness == 0 or length == 0 then
        return faces
    end

    -- Square to the wall, seen from above, turned to point away from the middle.
    local out_x, out_z = -along_z / length, along_x / length
    local middle = office_tile_middle(office_walls.middle)
    local from_middle_x = (wall_start.x + wall_end.x) / 2 - middle.x
    local from_middle_z = (wall_start.z + wall_end.z) / 2 - middle.z
    if out_x * from_middle_x + out_z * from_middle_z < 0 then
        out_x, out_z = -out_x, -out_z
    end

    local shift_x, shift_z = out_x * wall.thickness, out_z * wall.thickness
    table.insert(faces, {
        Vector3.new(wall_start.x + shift_x, wall_start.y, wall_start.z + shift_z),
        Vector3.new(wall_end.x + shift_x, wall_end.y, wall_end.z + shift_z),
    })
    return faces
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
        if wall_start and wall_end then
            local top_at = wall_top(wall, wall_start.y)
            for _, face in ipairs(wall_faces(wall, wall_start, wall_end)) do
                if line_of_sight.passes_through_wall(camera_position, spot, face[1], face[2], wall_start.y, top_at) then
                    return true
                end
            end
        end
    end
    return false
end

-- Has the game draw one face of a wall line as a wireframe panel.
---@param face_start Vector3
---@param face_end Vector3
---@param top_at fun(along: number): number
---@param pieces integer How many straight pieces the top is drawn with
local function draw_wall_face(face_start, face_end, top_at, pieces)
    -- The bottom corners, then the top from the end back to the start: two
    -- points for a straight top, more to follow an arch.
    local positions = { face_start, face_end }
    for piece = 0, pieces do
        local along = 1 - piece / pieces
        table.insert(positions, Vector3.new(face_start.x + (face_end.x - face_start.x) * along,
            top_at(along), face_start.z + (face_end.z - face_start.z) * along))
    end
    local last = #positions - 1 -- 0-indexed, the top at the start
    -- The bottom, the end's side, the top, the start's side, and a cross so
    -- it reads as a panel.
    local lines = { 0, 1, 1, 2 }
    for index = 2, last - 1 do
        table.insert(lines, index)
        table.insert(lines, index + 1)
    end
    for _, index in ipairs({ last, 0, 0, 2, 1, last }) do
        table.insert(lines, index)
    end
    ShapeList.Draw({
        shapePositions = positions,
        shapeLines = lines,
        ignoreDepth = true,
        colour = 0xFF8800FF,
        lineWidth = 2,
    })
end

-- Has the game join a thick wall's two faces at their corners, so they read
-- as one wall.
---@param inner Vector3[]
---@param outer Vector3[]
---@param top_at fun(along: number): number
local function draw_wall_joins(inner, outer, top_at)
    local function top(point, along) return Vector3.new(point.x, top_at(along), point.z) end
    ShapeList.Draw({
        shapePositions = {
            inner[1], outer[1], inner[2], outer[2],
            top(inner[1], 0), top(outer[1], 0), top(inner[2], 1), top(outer[2], 1),
        },
        shapeLines = { 0, 1, 2, 3, 4, 5, 6, 7 },
        ignoreDepth = true,
        colour = 0xFF8800FF,
        lineWidth = 2,
    })
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
            local top_at = wall_top(wall, wall_start.y)
            local pieces = wall.arch and arch_draw_pieces or 1
            local faces = wall_faces(wall, wall_start, wall_end)
            for _, face in ipairs(faces) do
                draw_wall_face(face[1], face[2], top_at, pieces)
            end
            if faces[2] then
                draw_wall_joins(faces[1], faces[2], top_at)
            end
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

-- Which way the screen's sideways is at the spot, as a direction across the
-- floor square to the camera's line to it, and how many pixels one fine unit
-- that way moves on screen (negative if it moves left). Found by having the
-- game draw a point a little to the side. nil when it can't be worked out,
-- like with the camera straight above the spot.
---@param spot Vector3
---@param camera_position Vector3
---@param on_screen table The spot on screen
---@return Vector3? across
---@return number? pixels_per_unit
local function screen_sideways(spot, camera_position, on_screen)
    local to_spot = direction(camera_position, spot)
    local across = normalised(Vector3.new(-to_spot.z, 0, to_spot.x))
    if not across then
        return nil, nil
    end
    local beside = ScreenConvert.Vector3ToScreen(Vector3.new(spot.x + across.x * sideways_probe, spot.y,
        spot.z + across.z * sideways_probe))
    if not beside or beside.x == on_screen.x then
        return nil, nil
    end
    return across, (beside.x - on_screen.x) / sideways_probe
end

-- Draws one strip: shows it down to where its own slice of the riches goes
-- behind a low wall, or hides it if the slice is hidden all the way up.
---@param strip RichesStrip
---@param riches_spot RichesSpot
---@param column Vector3 The bottom of the riches in the middle of the strip
---@param view_left integer
---@param view_top integer
---@return boolean shown
local function draw_strip(strip, riches_spot, column, view_left, view_top)
    local seen_from = lowest_seen_height(Camera.GetPosition(), column, riches_spot.visible_height or 0)
    if not seen_from then
        strip.layer.hidden = true
        return false
    end
    strip.layer:SetPos(view_left + strip.left, view_top)
    strip.layer:SetSize(strip.width, rows_to_show(column, seen_from, view_top))
    strip.layer.hidden = false
    return true
end

---@param riches_spot RichesSpot
local function draw_spot(riches_spot)
    local view = spot_views[riches_spot]
    local spot = find_spot(riches_spot)
    if not spot or is_player_on(riches_spot) then
        hide_view(view)
        return
    end

    local camera_position = Camera.GetPosition()
    local from_spot_to_camera = direction(spot, camera_position)
    local on_screen = ScreenConvert.Vector3ToScreen(spot)
    if math.sqrt(dot(from_spot_to_camera, from_spot_to_camera)) > max_camera_distance or not is_on_screen(on_screen) then
        hide_view(view)
        return
    end

    local view_left = math.floor(on_screen.x) - view_size // 2
    local view_top = math.floor(on_screen.y) - view_size // 2
    local roll = view_roll(spot, camera_position, Camera.GetFocusPosition())
    local across, pixels_per_unit = screen_sideways(spot, camera_position, on_screen)
    for _, strip in ipairs(view.strips) do
        -- The strip's middle, in pixels from the riches' middle, as a point
        -- that far to the side in the world. Without a sideways (or with one
        -- strip) it's the spot itself.
        local pixels_aside = strip.left + strip.width / 2 - view_size / 2
        local column = spot
        if across and pixels_aside ~= 0 then
            local units_aside = pixels_aside / pixels_per_unit
            column = Vector3.new(spot.x + across.x * units_aside, spot.y, spot.z + across.z * units_aside)
        end
        if draw_strip(strip, riches_spot, column, view_left, view_top) then
            -- The riches are at the middle of the scene, so everything else is
            -- placed relative to them.
            for _, occluder in ipairs(strip.occluders) do
                occluder.model:SetTransform(direction(spot, occluder.translation), Vector3.new(occluder.yaw, 0, 0),
                    occluder.scale, 0)
            end
            strip.camera:SetPosition(from_spot_to_camera, 0)
            strip.camera:SetLookAt(Vector3.new(0, 0, 0), 0)
            strip.camera:SetYawPitchRoll(Vector3.new(0, 0, roll * roll_sign), 0)
            strip.camera:SetFOV(view_fov(), 0)
            use_camera(strip)
        end
    end
end

local function draw()
    if not (in_office and World.IsAvailable() and Camera.IsAvailable()) then
        for _, view in pairs(spot_views) do
            hide_view(view)
        end
        return
    end

    update_game_fov()
    for _, riches_spot in ipairs(riches_spots.spots) do
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
    local desk_position = CoordGrid.new(table.unpack(riches_spots.desk_tile)):ToCoordFine(true).position
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

-- EXPERIMENT: the loc with the given config name near a tile, if loaded.
---@param config_name string
---@param near CoordGrid
---@return LocEntity?
local function find_loc(config_name, near)
    for _, loc in ipairs(LocList.ByDistance(near, occluder_search_range, true)) do
        if loc.config.configName == config_name then
            return loc
        end
    end
    return nil
end

-- EXPERIMENT: where a loc's model origin is: the middle of the tiles it
-- covers, on the ground there. Worked out from its tile, as loc.position is
-- somewhere else in Death's office: x matched, but z was 40 tiles north,
-- likely where the office's instance is copied from.
---@param loc LocEntity
---@return Vector3? nil while the ground there hasn't loaded
local function loc_origin(loc)
    -- The middle of the loc's first tile, moved to the middle of all of them.
    local first_tile = loc.coordGrid:ToCoordFine(true).position
    local x = first_tile.x + (loc.width - 1) * tile_size / 2
    local z = first_tile.z + (loc.length - 1) * tile_size / 2
    local ground_height = World.GetGroundHeight(0, math.floor(x), math.floor(z))
    if ground_height <= 0 then
        return nil
    end
    return Vector3.new(x, ground_height, z)
end

-- EXPERIMENT: tries every way a component can be made see-through, as alpha
-- alone left the desk copy showing. Each is tried on its own, so one the game
-- refuses can't stop the others, and the ones that took are printed once.
local see_through_printed = false
---@param model table
local function make_see_through(model)
    local ways = {
        alpha = function() model.alpha = 0 end,
        colour = function() model.colour = Vector4.new(1, 1, 1, 0) end,
        rgba = function() model.rgba = 0xFFFFFF00 end,
    }
    local results = {}
    for _, name in ipairs({ "alpha", "colour", "rgba" }) do
        local took, error_message = pcall(ways[name])
        table.insert(results, name .. (took and " set" or (" refused: " .. tostring(error_message))))
    end
    if not see_through_printed then
        see_through_printed = true
        print("[Riches debug] see-through: " .. table.concat(results, ", "))
    end
end

-- EXPERIMENT: adds the models of the spot's occluder locs to each of its
-- strips' groups. The loc's config moves and scales its models: offset, then
-- scale, then the post offset, so the model's origin ends up at
-- origin + scale * offset + post offset. Prints what it found once, to
-- check the numbers.
---@param riches_spot RichesSpot
---@return boolean found Whether all of them were found
local function add_occluders(riches_spot)
    local view = spot_views[riches_spot]
    local near = CoordGrid.new(table.unpack(riches_spot.tile))
    local found_all = true
    for _, config_name in ipairs(riches_spot.occluders or {}) do
        local loc = find_loc(config_name, near)
        local origin = loc and loc_origin(loc)
        if not origin then
            found_all = false
        else
            local config = loc.config
            local scale, offset, post = config.modelScale, config.modelOffset, config.modelPostOffset
            local translation = Vector3.new(origin.x + scale.x * offset.x + post.x,
                origin.y + scale.y * offset.y + post.y, origin.z + scale.z * offset.z + post.z)
            local yaw = occluder_yaw_sign * loc.rotationType * math.pi / 2
            local model_ids = config:GetModelIDs(loc.shapeType)
            local function xyz(vector)
                return string.format("(%.2f, %.2f, %.2f)", vector.x, vector.y, vector.z)
            end
            local id_texts = {}
            for _, model_id in ipairs(model_ids) do
                table.insert(id_texts, tostring(model_id))
            end
            print(string.format("[Riches debug] occluder %s: models %s, tile %s, %s size %sx%s, at %s (position says %s) rotation %s",
                config_name, table.concat(id_texts, ", "), loc.coordGrid.localX, loc.coordGrid.localZ,
                loc.width, loc.length, xyz(origin), xyz(loc.position), tostring(loc.rotationType)))
            for _, model_id in ipairs(model_ids) do
                for _, strip in ipairs(view.strips) do
                    local model = ui.Model.new(strip.group)
                    model:SetSize(view_size, view_size)
                    model:SetModel(ui.ModelType.MODEL, model_id)
                    if not occluders_visible then
                        make_see_through(model)
                    end
                    table.insert(strip.occluders, { model = model, translation = translation, yaw = yaw, scale = scale })
                end
            end
        end
    end
    return found_all
end

-- EXPERIMENT: the spots whose occluders have been added.
---@type table<RichesSpot, boolean>
local occluders_added = {}

local function check_office()
    print_player_tile()
    player_tile = Player.GetEntity().coordGrid:ToCoordFine(true).position
    in_office = tiles_from_desk(player_tile) <= office_radius
    if in_office then
        for _, riches_spot in ipairs(riches_spots.spots) do
            if riches_spot.occluders and not occluders_added[riches_spot] then
                occluders_added[riches_spot] = add_occluders(riches_spot)
            end
        end
    end
end

function deaths_riches.start()
    if db.get_render_deaths_riches() == false then
        return
    end
    -- Already started, so its models are already there.
    if root then
        return
    end
    office_walls.show = db.get_show_office_walls()
    create_views()
    Event.Draw.Subscribe(subscription_name, draw)
    Event.ServerLogic.Subscribe(subscription_name, check_office)
    wall_measure.start()
end

function deaths_riches.stop()
    Event.Draw.Unsubscribe(subscription_name)
    Event.ServerLogic.Unsubscribe(subscription_name)
    wall_measure.stop()
    for _, view in pairs(spot_views) do
        for _, strip in ipairs(view.strips) do
            for _, model in ipairs(strip.models) do
                model:Destroy()
            end
            for _, occluder in ipairs(strip.occluders) do
                occluder.model:Destroy()
            end
            strip.group:Destroy()
            strip.layer:Destroy()
        end
    end
    spot_views = {}
    game_fov = default_fov
    fov_measured = false
    root = nil
    in_office = false
    player_tile = nil
    occluders_added = {}
end

return deaths_riches
