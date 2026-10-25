local db = require("src/database/db")

-- Draws Death's riches: game models on a screen layer, moved every frame so
-- they look like they stand in Death's office.
local deaths_riches = {}

local subscription_name = "deaths-riches"

-- How big each model's component is on screen, in pixels.
local model_size = 400
-- How much bigger than real life the riches look in the world.
local riches_size = 1.5

-- A place in the world where riches are drawn. The tile and the items are kept
-- as plain values (the arguments for CoordGrid.new, and names in id.Model),
-- so nothing from the game is needed until the riches are drawn.
---@class RichesSpot
---@field tile integer[] Arguments for CoordGrid.new
---@field height number How far above the ground there the riches float
---@field items string[] The riches' models, as names in id.Model, drawn together
---@field item_scale number How big the items are drawn inside their model

---@type RichesSpot
local desk = { tile = { 0, 6, 10, 29, 38 }, height = 1150, items = { "INV_PARTYHAT" }, item_scale = 1 }
-- Only inventory models for now: furniture models are oriented differently and
-- didn't tilt right with the camera, whatever the settings.
---@type RichesSpot
local top_left_corner = { tile = { 0, 6, 10, 26, 42 }, height = 0, items = { "INV_GOLDPEICES_10000" }, item_scale = 1 }

---@type RichesSpot[]
local riches_spots = { desk, top_left_corner }

-- The middle of the spot's tile, in fine coordinates.
---@param riches_spot RichesSpot
---@return Vector3
local function tile_position(riches_spot)
    return CoordGrid.new(table.unpack(riches_spot.tile)):ToCoordFine(true).position
end

-- The riches are tilted towards the camera in steps of this many degrees,
-- from level (0) to straight down (90).
-- TODO: the riches don't turn as the camera goes around them, so they always
-- show the same side, which is easy to spot on the coin pile. What was tried:
-- the slot's x axis turns them around the vertical, but together with the tilt
-- on y it leans them sideways (the game applies the axes in another order); a
-- model per tilt and direction is too many models; ui.Model:SetTransform
-- doesn't change what's drawn.
local tilt_step = 3
local max_tilt = 90

-- Further than this from a spot, the camera can't be in Death's office, so its
-- riches are hidden. The camera was about 3,000-10,000 away in the office.
local max_camera_distance = 30000

-- The player counts as in Death's office within this many tiles of his desk.
-- The furthest point in the office is about 28 tiles away.
local office_radius = 40
-- Fine coordinates per tile.
local tile_size = 512

local root
-- For each spot, one model per tilt step, all loaded up front. Changing a
-- model's tilt means reloading it, which takes long enough to lag behind the
-- camera, so instead the model with the closest tilt is shown and the rest are
-- hidden.
---@type table<RichesSpot, table[]>
local tilted_models = {}
-- The model shown for each spot, if any.
---@type table<RichesSpot, table>
local shown_models = {}
-- A model only loads once it's shown, and flickers while it does. So at start
-- every model is shown out of sight for this many frames (about half a second
-- was enough in testing) to load them before they're needed. Off screen
-- doesn't count as shown, so they're shown 1x1 pixel in the corner instead.
local preload_frames = 30
local preload_frames_left = 0
-- The riches are only drawn while the player is in Death's office, so they
-- don't show up elsewhere in the world. Checked once per game tick.
local in_office = false

-- A model on its own always faces the camera, but an NPC whose body is
-- replaced by the items can be rotated, through the rotation of its model
-- slots. Each item goes in its own slot.
-- In the slots' rotation, y is what tilts the items towards the camera, and it
-- turns the other way from the camera (both found by testing).
---@param riches_spot RichesSpot
---@param tilt number Degrees
local function create_tilted_model(riches_spot, tilt)
    local model = ui.Model.new(root)
    model:SetSize(model_size, model_size) -- a component without a size is invisible
    model:SetModel(ui.ModelType.NPC_MODEL, id.NPC.HANS) -- any NPC; the customisation replaces all of him
    model.viewDistance = 600
    model.hidden = true

    local body = ui.NPCCustomisation.new(true) -- true: customise the body, not the chat head
    for slot, item in ipairs(riches_spot.items) do
        body:SetModelSlot(slot - 1, id.Model[item], riches_spot.item_scale, Vector3.new(0, 0, 0),
            Vector3.new(0, -math.rad(tilt), 0))
    end
    model.npcCustomisation = body
    return model
end

local function create_models()
    root = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    for _, riches_spot in ipairs(riches_spots) do
        tilted_models[riches_spot] = {}
        for tilt = 0, max_tilt, tilt_step do
            table.insert(tilted_models[riches_spot], create_tilted_model(riches_spot, tilt))
        end
    end
end

---@param action fun(model: table)
local function for_each_model(action)
    for _, models in pairs(tilted_models) do
        for _, model in ipairs(models) do
            action(model)
        end
    end
end

local function start_preload()
    for_each_model(function (model)
        model:SetSize(1, 1)
        model:SetPos(0, 0)
        -- The model isn't cut off at its size, so it's also zoomed far out to
        -- make the item too small to notice.
        model.viewDistance = 100000
        model.hidden = false
    end)
    preload_frames_left = preload_frames
end

-- Counts down the preload, and hides the models again once it's done.
---@return boolean preloading true while the models are still loading
local function continue_preload()
    if preload_frames_left == 0 then
        return false
    end
    preload_frames_left = preload_frames_left - 1
    if preload_frames_left == 0 then
        for_each_model(function (model)
            model.hidden = true
            model:SetSize(model_size, model_size)
        end)
    end
    return true
end

-- The spot's model whose tilt is closest to how far the camera looks down on it.
---@param riches_spot RichesSpot
---@param camera_elevation number Radians
local function model_for(riches_spot, camera_elevation)
    local tilt = math.max(0, math.min(max_tilt, math.deg(camera_elevation)))
    return tilted_models[riches_spot][math.floor(tilt / tilt_step + 0.5) + 1]
end

---@param riches_spot RichesSpot
---@param model? table The model to show at the spot, or nil to show none
local function show(riches_spot, model)
    local shown_model = shown_models[riches_spot]
    if model == shown_model then return end
    if shown_model then shown_model.hidden = true end
    shown_models[riches_spot] = model
    if model then model.hidden = false end
end

-- Where in the world the riches at the given spot are drawn. nil while the
-- ground there hasn't loaded yet, which shows as a height of 0 or -1 for the
-- first frames after entering the office. Worked out every frame, so the
-- right height is picked up as soon as it's there.
---@param riches_spot RichesSpot
---@return Vector3?
local function find_spot(riches_spot)
    local position = tile_position(riches_spot)
    local ground_height = World.GetGroundHeight(0, position.x, position.z)
    if ground_height <= 0 then
        return nil
    end
    position.y = ground_height + riches_spot.height
    return position
end

-- ScreenConvert can also give a point far outside the screen instead of nil,
-- e.g. while the camera hasn't settled after loading.
local function is_on_screen(point)
    return point ~= nil
        and point.x >= 0 and point.x <= root.width
        and point.y >= 0 and point.y <= root.height
end

---@param riches_spot RichesSpot
local function draw_spot(riches_spot)
    local spot = find_spot(riches_spot)
    if not spot then
        show(riches_spot, nil)
        return
    end

    local to_camera = Camera.GetPosition() - spot
    local on_screen = ScreenConvert.Vector3ToScreen(spot)
    if to_camera.length > max_camera_distance or not is_on_screen(on_screen) then
        show(riches_spot, nil)
        return
    end

    local camera_elevation = math.atan(to_camera.y, math.sqrt(to_camera.x ^ 2 + to_camera.z ^ 2))
    local model = model_for(riches_spot, camera_elevation)

    -- Centred on the spot.
    model:SetPos(math.floor(on_screen.x) - model_size // 2, math.floor(on_screen.y) - model_size // 2)

    -- Zooms the model out as the camera moves away, so it keeps the size it
    -- would have in the world. Only set when it changes, in case setting it
    -- every frame stops the model from showing.
    local view_distance = math.floor(to_camera.length * model_size / root.width / riches_spot.item_scale / riches_size)
    if view_distance ~= model.viewDistance then
        model.viewDistance = view_distance
    end

    show(riches_spot, model)
end

local function draw()
    if continue_preload() then return end
    for _, riches_spot in ipairs(riches_spots) do
        if in_office and World.IsAvailable() then
            draw_spot(riches_spot)
        else
            show(riches_spot, nil)
        end
    end
end

-- How many tiles the player is from Death's desk, ignoring height.
---@return number
local function tiles_from_desk()
    local player = Player.GetEntity().coordGrid:ToCoordFine(true).position
    local desk_position = tile_position(desk)
    return math.sqrt((player.x - desk_position.x) ^ 2 + (player.z - desk_position.z) ^ 2) / tile_size
end

local function check_office()
    in_office = tiles_from_desk() <= office_radius
end

function deaths_riches.start()
    if db.get_render_deaths_riches() == false then
        return
    end
    -- Already started, so its models are already there.
    if next(tilted_models) then
        return
    end
    create_models()
    start_preload()
    Event.Draw.Subscribe(subscription_name, draw)
    Event.ServerLogic.Subscribe(subscription_name, check_office)
end

function deaths_riches.stop()
    Event.Draw.Unsubscribe(subscription_name)
    Event.ServerLogic.Unsubscribe(subscription_name)
    for_each_model(function (model)
        model:Destroy()
    end)
    tilted_models = {}
    shown_models = {}
    preload_frames_left = 0
    root = nil
    in_office = false
end

return deaths_riches
