-- Fakes of the game globals that Death's riches use: Vector3, CoordGrid, the
-- model component, World, Camera, ScreenConvert and Player. Positions are in
-- fine coordinates, 512 per tile, like the game's.
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
-- 1920x1080 screen, and other points 1 pixel off per 100 fine units.
local function screen_point(point)
    return { x = 960 + (point.x - fake_game.desk.x) / 100, y = 500 + (point.z - fake_game.desk.z) / 100 }
end
fake_game.screen_point = screen_point

-- Installs the fakes. The returned table controls them:
--   models           every model created, in order
--   ground_height    what World.GetGroundHeight returns
--   camera           Camera.GetPosition()
--   to_screen(point)   what ScreenConvert.Vector3ToScreen returns for a point
--   converted        every point given to ScreenConvert.Vector3ToScreen
--   move_player(x, z)  puts the player at the given fine coordinates
function fake_game.install()
    local game = { models = {}, ground_height = 3328, to_screen = screen_point, converted = {} }
    game.camera = vector3(fake_game.desk.x, 3328 + 1150 + 3000, fake_game.desk.z + 3000)
    local player = coord_grid(fake_game.desk.x, fake_game.desk.z)

    function game.move_player(x, z)
        player = coord_grid(x, z)
    end

    Vector3 = { new = vector3 }
    CoordGrid = {
        new = function(plane, square_x, square_z, tile_x, tile_z)
            assert(plane == 0, "only plane 0 is faked")
            return coord_grid((square_x * 64 + tile_x) * tile_size + tile_size // 2,
                (square_z * 64 + tile_z) * tile_size + tile_size // 2)
        end,
    }
    -- Any id.Model name gives back the name, so a slot's item can be checked.
    id = { Component = {}, NPC = {}, Model = setmetatable({}, { __index = function(_, name) return name end }) }

    -- A model remembers its size, position, viewDistance, hidden and slot rotation.
    local function new_model(parent)
        local model = { parent = parent, destroyed = false }
        function model.SetSize(self, width, height) self.width, self.height = width, height end
        function model.SetPos(self, x, y) self.x, self.y = x, y end
        function model.SetModel() end
        function model.Destroy(self) self.destroyed = true end
        table.insert(game.models, model)
        return model
    end

    ui = {
        Interfaces = {
            GetComponent = function()
                return { width = 1920, height = 1080 }
            end,
        },
        Model = { new = new_model },
        ModelType = {},
        NPCCustomisation = {
            new = function()
                -- Keeps each slot's item, and the scale and rotation of the last one set.
                return {
                    items = {},
                    SetModelSlot = function(self, slot, item, scale, _, rotation)
                        self.items[slot] = item
                        self.scale, self.rotation = scale, rotation
                    end,
                }
            end,
        },
    }
    World = {
        IsAvailable = function() return true end,
        GetGroundHeight = function() return game.ground_height end,
    }
    Camera = { GetPosition = function() return game.camera end }
    ScreenConvert = {
        Vector3ToScreen = function(point)
            table.insert(game.converted, point)
            return game.to_screen(point)
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

-- How far a model's hat is tilted, in degrees, from its slot rotation.
function fake_game.tilt_of(model)
    return math.floor(-math.deg(model.npcCustomisation.rotation.y) + 0.5)
end

return fake_game
