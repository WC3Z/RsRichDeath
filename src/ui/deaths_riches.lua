-- Draws Death's riches: a game model on a screen layer, moved every frame so it
-- looks like it stands in Death's office.
local deaths_riches = {}

local subscription_name = "deaths-riches"

-- How big the model's component is on screen, in pixels.
local model_size = 400
-- How big the partyhat is drawn inside the model.
local hat_scale = 0.9
-- How much bigger than real life the riches look in the world.
local riches_size = 1.5

-- A place in the world where riches are drawn: its tile, and how far above
-- the ground there they float.
---@class RichesSpot
---@field tile CoordGrid
---@field height number

---@type RichesSpot
local desk = { tile = CoordGrid.new(0, 6, 10, 29, 38), height = 1150 }

-- The hat is tilted towards the camera in steps of this many degrees, from
-- level (0) to straight down (90).
local tilt_step = 3
local max_tilt = 90

-- Further than this from the spot, the camera can't be in Death's office, so
-- the hat is hidden. The camera was about 3,000-10,000 away in the office.
local max_camera_distance = 30000

local root
-- One model per tilt step, all loaded up front. Changing a model's tilt means
-- reloading it, which takes long enough to lag behind the camera, so instead
-- the model with the closest tilt is shown and the rest are hidden.
---@type table[]
local tilted_models = {}
-- The model from tilted_models that is shown, if any.
local shown_model
-- The riches are only drawn while Death is loaded, so they don't show up
-- elsewhere in the world.
local death_is_loaded = false
-- DEBUG: draws the riches whether Death is loaded or not, so testing doesn't
-- need leaving and re-entering the office after every reload.
local debug_ignore_death = true
-- Where the riches stand in the world. Worked out once the ground there has loaded.
local spot

-- A model on its own always faces the camera, but an NPC whose body is
-- replaced by the item can be rotated, through the rotation of its model slot.
-- In the slot's rotation, y is what tilts the hat towards the camera, and it
-- turns the other way from the camera (both found by testing).
---@param tilt number Degrees
local function create_tilted_model(tilt)
    local model = ui.Model.new(root)
    model:SetSize(model_size, model_size) -- a component without a size is invisible
    model:SetModel(ui.ModelType.NPC_MODEL, id.NPC.HANS) -- any NPC; the customisation replaces all of him
    model.viewDistance = 600
    model.hidden = true

    local body = ui.NPCCustomisation.new(true) -- true: customise the body, not the chat head
    body:SetModelSlot(0, id.Model.INV_PARTYHAT, hat_scale, Vector3.new(0, 0, 0), Vector3.new(0, -math.rad(tilt), 0))
    model.npcCustomisation = body
    return model
end

local function create_models()
    root = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    for tilt = 0, max_tilt, tilt_step do
        table.insert(tilted_models, create_tilted_model(tilt))
    end
end

-- The model whose tilt is closest to how far the camera looks down on the spot.
---@param camera_elevation number Radians
local function model_for(camera_elevation)
    local tilt = math.max(0, math.min(max_tilt, math.deg(camera_elevation)))
    return tilted_models[math.floor(tilt / tilt_step + 0.5) + 1]
end

local function show(model)
    if model == shown_model then return end
    if shown_model then shown_model.hidden = true end
    shown_model = model
    if shown_model then shown_model.hidden = false end
end

-- Where in the world the riches at the given spot are drawn. nil while the
-- ground there hasn't loaded yet, which happens on the first frames after
-- entering the office.
---@param riches_spot RichesSpot
---@return Vector3?
local function find_spot(riches_spot)
    local position = riches_spot.tile:ToCoordFine(true).position
    local ground_height = World.GetGroundHeight(0, position.x, position.z)
    if ground_height == 0 then
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

local function draw()
    if not death_is_loaded and not debug_ignore_death then
        show(nil)
        return
    end
    if not spot then
        if not World.IsAvailable() then return end
        spot = find_spot(desk)
        if not spot then return end
    end

    local to_camera = Camera.GetPosition() - spot
    local on_screen = ScreenConvert.Vector3ToScreen(spot)
    if to_camera.length > max_camera_distance or not is_on_screen(on_screen) then
        show(nil)
        return
    end

    local camera_elevation = math.atan(to_camera.y, math.sqrt(to_camera.x ^ 2 + to_camera.z ^ 2))
    local model = model_for(camera_elevation)

    -- Centred on the spot.
    model:SetPos(math.floor(on_screen.x) - model_size // 2, math.floor(on_screen.y) - model_size // 2)

    -- Zooms the model out as the camera moves away, so it keeps the size it
    -- would have in the world. Only set when it changes, in case setting it
    -- every frame stops the model from showing.
    local view_distance = math.floor(to_camera.length * model_size / root.width / hat_scale / riches_size)
    if view_distance ~= model.viewDistance then
        model.viewDistance = view_distance
    end

    show(model)
end

local function on_npc_added(event)
    if event.npcEntity.displayName == "Death" then
        death_is_loaded = true
    end
end

local function on_npc_removed(event)
    if event.npcEntity.displayName == "Death" then
        death_is_loaded = false
    end
end

function deaths_riches.start()
    create_models()
    Event.Draw.Subscribe(subscription_name, draw)
    Event.NPCEntityAdded.Subscribe(subscription_name, on_npc_added)
    Event.NPCEntityRemoved.Subscribe(subscription_name, on_npc_removed)
end

function deaths_riches.stop()
    Event.Draw.Unsubscribe(subscription_name)
    Event.NPCEntityAdded.Unsubscribe(subscription_name)
    Event.NPCEntityRemoved.Unsubscribe(subscription_name)
    for _, model in ipairs(tilted_models) do
        model:Destroy()
    end
    tilted_models = {}
    shown_model = nil
    root = nil
    death_is_loaded = false
    spot = nil
end

return deaths_riches
