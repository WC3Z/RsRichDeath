-- Draws Death's riches: a game model on a screen layer, moved every frame so it
-- looks like it stands in Death's office.
local deaths_riches = {}

local subscription_name = "deaths-riches-draw"

-- How big the model's component is on screen, in pixels.
local model_size = 400
-- How big the partyhat is drawn inside the model.
local hat_scale = 0.9

local root
local model
-- Where the riches stand in the world. Worked out on the first frame the world is available.
local spot

-- A model on its own always faces the camera, but an NPC whose body is
-- replaced by the item can be rotated, through the rotation of its model slot.
-- So the partyhat is put in an NPC's body slot again each time it turns.
---@param yaw   number Radians
---@param pitch number Radians
local function rotate(yaw, pitch)
    local body = ui.NPCCustomisation.new(true) -- true: customise the body, not the chat head
    body:SetModelSlot(0, id.Model.INV_PARTYHAT, hat_scale, Vector3.new(0, 0, 0), Vector3.new(pitch, yaw, 0))
    model.npcCustomisation = body
end

local function create_model()
    root = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)

    model = ui.Model.new(root)
    model:SetSize(model_size, model_size) -- a component without a size is invisible
    model:SetModel(ui.ModelType.NPC_MODEL, id.NPC.HANS) -- any NPC; the customisation replaces all of him
    model.viewDistance = 600
    rotate(0, 0)
end

-- Above Death's desk.
local function find_spot()
    local position = CoordGrid.new(0, 6, 10, 29, 38):ToCoordFine(true).position
    position.y = World.GetGroundHeight(0, position.x, position.z) + 1200
    return position
end

local function draw()
    if not spot then
        if not World.IsAvailable() then return end
        spot = find_spot()
    end

    local on_screen = ScreenConvert.Vector3ToScreen(spot)
    model.hidden = on_screen == nil
    if not on_screen then return end

    -- Centred on the spot.
    model:SetPos(math.floor(on_screen.x) - model_size // 2, math.floor(on_screen.y) - model_size // 2)

    -- Zooms the model out as the camera moves away, so it keeps the size it
    -- would have in the world.
    local to_camera = Camera.GetPosition() - spot
    model.viewDistance = math.floor(to_camera.length * model_size / root.width / hat_scale)

    -- Tilts the hat by how far the camera looks down on it. It doesn't turn as
    -- the camera goes around it (yaw 0), which a partyhat mostly hides.
    local camera_elevation = math.atan(to_camera.y, math.sqrt(to_camera.x ^ 2 + to_camera.z ^ 2))
    rotate(0, camera_elevation)
end

function deaths_riches.start()
    create_model()
    Event.Draw.Subscribe(subscription_name, draw)
end

function deaths_riches.stop()
    Event.Draw.Unsubscribe(subscription_name)
    if model then
        model:Destroy()
        model = nil
    end
    root = nil
    spot = nil
end

return deaths_riches
