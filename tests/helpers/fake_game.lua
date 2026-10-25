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

-- Where CoordGrid.new(0, 6, 10, 29, 38), Death's desk, is in fine coordinates.
fake_game.desk = { x = (6 * 64 + 29) * tile_size + tile_size // 2, z = (10 * 64 + 38) * tile_size + tile_size // 2 }

-- Installs the fakes. The returned table controls them:
--   models           every model created, in order
--   ground_height    what World.GetGroundHeight returns
--   camera           Camera.GetPosition()
--   on_screen        what ScreenConvert.Vector3ToScreen returns (nil for off screen)
--   converted        the last point given to ScreenConvert.Vector3ToScreen
--   move_player(x, z)  puts the player at the given fine coordinates
function fake_game.install()
    local game = { models = {}, ground_height = 3328, on_screen = { x = 960, y = 500 } }
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
    id = { Component = {}, NPC = {}, Model = {} }

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
                return {
                    SetModelSlot = function(self, _, _, _, _, rotation)
                        self.rotation = rotation
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
            game.converted = point
            return game.on_screen
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
