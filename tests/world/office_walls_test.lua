local assert_helpers = require("tests/helpers/assert")

local module_name = "src/world/office_walls"

-- The walls as written in the file. Other tests replace office_walls.walls
-- with their own, so this loads a fresh copy and then puts the shared one back.
local function walls_in_the_file()
    local shared = package.loaded[module_name]
    package.loaded[module_name] = nil
    local fresh = require(module_name)
    package.loaded[module_name] = shared
    return fresh.walls
end

local tests = {}

-- Each wall goes west to east (x grows), or, if it runs more north-south than
-- east-west, north to south (z shrinks).
function tests.walls_go_west_to_east_or_north_to_south()
    local walls = walls_in_the_file()
    for index, wall in ipairs(walls) do
        local east = wall.to[1] - wall.from[1]
        local south = wall.from[2] - wall.to[2]
        local goes_the_right_way
        if math.abs(east) >= math.abs(south) then
            goes_the_right_way = east > 0
        else
            goes_the_right_way = south > 0
        end
        if not goes_the_right_way then
            error(string.format("wall %d, from { %s, %s } to { %s, %s }, goes the wrong way",
                index, wall.from[1], wall.from[2], wall.to[1], wall.to[2]))
        end
    end
    assert_helpers.equal(#walls > 0, true)
end

return tests
