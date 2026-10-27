-- Fakes of the game globals that Death's riches use: Vector3, Vector4,
-- CoordGrid, the model and model group components, World, Camera,
-- ScreenConvert and Player. Positions are in fine coordinates, 512 per tile,
-- like the game's.
local fake_game = {}

local tile_size = 512

local Vector3Meta = {}
Vector3Meta.__index = function(vector, key)
    if key == "length" then
        return math.sqrt(vector.x ^ 2 + vector.y ^ 2 + vector.z ^ 2)
    end
end
Vector3Meta.__sub = function(a, b)
    return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, Vector3Meta)
end

local function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, Vector3Meta)
end

-- A tile at the given fine x and z, which ToCoordFine gives back as its middle.
local function coord_grid(x, z)
    return {
        localX = (x // tile_size) % 64,
        localZ = (z // tile_size) % 64,
        mapSquareX = x // tile_size // 64,
        mapSquareZ = z // tile_size // 64,
        ToCoordFine = function()
            return { position = vector3(x, 0, z) }
        end,
    }
end

-- The middle of a tile in map square (6, 10), in fine coordinates.
local function office_tile(tile_x, tile_z)
    return { x = (6 * 64 + tile_x) * tile_size + tile_size // 2, z = (10 * 64 + tile_z) * tile_size + tile_size // 2 }
end

-- Where the riches spots are, in fine coordinates.
fake_game.desk = office_tile(29, 38)
fake_game.top_left_corner = office_tile(26, 42)

-- Where a world point shows on screen: the desk in the middle of a
-- 1920x1080 screen, and other points 1 pixel off per 100 fine units. Height
-- makes no difference, so the field of view can't be measured from it.
local function screen_point(point)
    return { x = 960 + (point.x - fake_game.desk.x) / 100, y = 500 + (point.z - fake_game.desk.z) / 100 }
end
fake_game.screen_point = screen_point

-- Copies a fake camera's settings, like AddCamera does.
local function copy(camera)
    local result = {}
    for key, value in pairs(camera) do
        result[key] = value
    end
    return result
end

-- Installs the fakes. The returned table controls them:
--   root             the screen layer, with width and height
--   layers           every layer created, in order
--   groups           every model group created, in order
--   models           every model created, in order
--   ground_height    what World.GetGroundHeight returns
--   camera           Camera.GetPosition()
--   focus            Camera.GetFocusPosition()
--   to_screen(point)   what ScreenConvert.Vector3ToScreen returns for a point
--   move_player(x, z)  puts the player at the given fine coordinates
--   shapes           the settings of every ShapeList.Draw call
--   moved_to_front   every component MoveToFront was called on, in order
--   mouse            Mouse.GetPosition()
--   floor_at(point)    what ScreenConvert.ScreenToCoordFine returns for a screen point
--   locs             what LocList.ByDistance returns
function fake_game.install()
    local game = {
        root = { width = 1920, height = 1080 },
        layers = {},
        groups = {},
        models = {},
        ground_height = 3328,
        to_screen = screen_point,
        shapes = {},
        moved_to_front = {},
        floor_at = function() return nil end,
        locs = {},
    }
    game.camera = vector3(fake_game.desk.x, 3328 + 1150 + 3000, fake_game.desk.z + 3000)
    game.focus = vector3(fake_game.desk.x, 3328 + 1150, fake_game.desk.z)
    -- Two tiles south of the desk, so not on any riches' tile.
    local player = coord_grid(fake_game.desk.x, fake_game.desk.z - 2 * tile_size)

    function game.move_player(x, z)
        player = coord_grid(x, z)
    end

    Vector3 = { new = vector3 }
    Vector4 = {
        new = function(x, y, z, w)
            return { x = x, y = y, z = z, w = w }
        end,
    }
    CoordGrid = {
        new = function(plane, square_x, square_z, tile_x, tile_z)
            assert(plane == 0, "only plane 0 is faked")
            return coord_grid((square_x * 64 + tile_x) * tile_size + tile_size // 2,
                (square_z * 64 + tile_z) * tile_size + tile_size // 2)
        end,
    }
    -- Any id.Model name gives back the name, so a model's item can be checked.
    id = { Component = {}, Model = setmetatable({}, { __index = function(_, name) return name end }) }

    -- Size, position and Destroy, shared by models and model groups.
    local function new_component(parent)
        local component = { parent = parent, destroyed = false }
        function component.SetSize(self, width, height) self.width, self.height = width, height end
        function component.SetPos(self, x, y) self.x, self.y = x, y end
        function component.Destroy(self) self.destroyed = true end
        function component.MoveToFront(self) table.insert(game.moved_to_front, self) end
        return component
    end

    -- A model remembers its model and its last transform.
    local function new_model(parent)
        local model = new_component(parent)
        function model.SetModel(self, type, model_id) self.type, self.model_id = type, model_id end
        -- Keeps each rematerial slot as { source, replacement }.
        function model.SetRematerial(self, slot, source, replacement)
            self.rematerials = self.rematerials or {}
            self.rematerials[slot] = { source, replacement }
        end
        function model.SetTransform(self, position, rotation, scale, duration)
            self.transform = { position = position, rotation = rotation, scale = scale, duration = duration }
        end
        table.insert(game.models, model)
        return model
    end

    local function new_camera()
        return {
            SetPosition = function(self, position) self.position = position end,
            SetLookAt = function(self, target) self.lookAt = target end,
            SetFOV = function(self, fov) self.fov = fov end,
            SetYawPitchRoll = function(self, rotation) self.yawPitchRoll = rotation end,
            SetClipPlanes = function(self, near, far) self.nearPlane, self.farPlane = near, far end,
        }
    end

    -- A model group keeps copies of the cameras added to it, and which one is active.
    local function new_model_group(parent)
        local group = new_component(parent)
        group.cameras = {}
        group.cameras_added = 0
        function group.AddCamera(self, camera)
            self.cameras_added = self.cameras_added + 1
            self.cameras[self.cameras_added] = copy(camera)
            return self.cameras_added
        end
        function group.DeleteCamera(self, index) self.cameras[index] = nil end
        function group.SwitchCamera(self, index, transition)
            self.active_camera, self.transition = self.cameras[index], transition
            return self.active_camera ~= nil
        end
        table.insert(game.groups, group)
        return group
    end

    -- The docs call the camera ModelCamera, but the game has ModelCameraInfo.
    ui = {
        Interfaces = {
            GetComponent = function()
                return game.root
            end,
        },
        Model = { new = new_model },
        Layer = {
            new = function(parent)
                local layer = new_component(parent)
                table.insert(game.layers, layer)
                return layer
            end,
        },
        ModelType = { MODEL = "MODEL" },
        ModelGroup = { new = new_model_group },
        ModelCameraInfo = { new = new_camera },
        ModelCameraTransition = { NONE = "NONE" },
    }
    World = {
        IsAvailable = function() return true end,
        GetGroundHeight = function() return game.ground_height end,
    }
    Camera = {
        IsAvailable = function() return true end,
        GetPosition = function() return game.camera end,
        GetFocusPosition = function() return game.focus end,
    }
    ScreenConvert = {
        Vector3ToScreen = function(point)
            return game.to_screen(point)
        end,
        ScreenToCoordFine = function(point)
            return game.floor_at(point)
        end,
    }
    Mouse = { GetPosition = function() return game.mouse end }
    ModifierKey = { SHIFT = 1, CONTROL = 2 }
    GameKey = { H = 53, M = 70, N = 69 }
    ShapeList = {
        Draw = function(settings)
            table.insert(game.shapes, settings)
        end,
    }
    LocList = {
        ByDistance = function()
            return game.locs
        end,
    }
    Player = {
        GetEntity = function()
            return { coordGrid = player }
        end,
    }
    return game
end

-- The models that aren't hidden.
function fake_game.visible_models(game)
    local visible = {}
    for _, model in ipairs(game.models) do
        if model.hidden == false then
            table.insert(visible, model)
        end
    end
    return visible
end

return fake_game
