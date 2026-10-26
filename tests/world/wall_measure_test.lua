local wall_measure = require("src/world/wall_measure")
local office_walls = require("src/world/office_walls")
local assert_helpers = require("tests/helpers/assert")
local fake_event = require("tests/helpers/fake_event")
local fake_game = require("tests/helpers/fake_game")

local tile_size = 512

-- The middle of a tile in map square (6, 10), plus a fraction of a tile.
local function fine_x(tile) return (6 * 64 + tile) * tile_size + tile_size // 2 end
local function fine_z(tile) return (10 * 64 + tile) * tile_size + tile_size // 2 end

-- Fresh fakes with the tool started and the wall outlines on.
local function install()
    wall_measure.stop()
    fake_event.install()
    local game = fake_game.install()
    office_walls.show = true
    wall_measure.start()
    return game
end

-- Runs the action and returns what it printed. print is put back even if
-- the action fails, so the test runner can still report it.
local function prints_from(action)
    local printed = {}
    local real_print = print
    print = function(text) table.insert(printed, text) end
    local ok, error_message = pcall(action)
    print = real_print
    if not ok then
        error(error_message, 0)
    end
    return printed
end

local function press(key, modifiers, is_repeat)
    Event.KeyDown.fire({ gameKey = key, modifiers = modifiers or ModifierKey.SHIFT, isRepeat = is_repeat or false })
end

-- Puts the floor under the mouse at the given fine x and z.
local function floor_under_mouse(game, x, z)
    game.mouse = { x = 100, y = 100 }
    game.floor_at = function()
        return { position = Vector3.new(x, 0, z) }
    end
end

local tests = {}

function tests.tile_numbers_are_whole_in_a_tiles_middle()
    assert_helpers.equal(wall_measure.tile_number(fine_x(23), 6), 23)
    assert_helpers.equal(wall_measure.tile_number(fine_x(23) + tile_size / 2, 6), 23.5)
    assert_helpers.equal(wall_measure.tile_number(fine_z(40) - tile_size / 4, 10), 39.75)
end

function tests.shift_m_prints_the_tile_under_the_mouse()
    local game = install()
    floor_under_mouse(game, fine_x(23) + tile_size / 4, fine_z(40) + tile_size / 2)

    local printed = prints_from(function() press(GameKey.M) end)

    assert_helpers.equal(printed[1], "[Riches debug] mouse at { 23.25, 40.50 }")
end

function tests.says_so_when_there_is_no_ground_under_the_mouse()
    local game = install()
    game.mouse = { x = 100, y = 100 }

    local printed = prints_from(function() press(GameKey.M) end)

    assert_helpers.equal(printed[1], "[Riches debug] no ground under the mouse")
end

function tests.does_nothing_while_the_wall_outlines_are_off()
    local game = install()
    floor_under_mouse(game, fine_x(23), fine_z(40))
    office_walls.show = false

    local printed = prints_from(function() press(GameKey.M) end)

    assert_helpers.equal(#printed, 0)
end

function tests.needs_shift_and_ignores_held_keys()
    local game = install()
    floor_under_mouse(game, fine_x(23), fine_z(40))

    local printed = prints_from(function()
        press(GameKey.M, 0)
        press(GameKey.M, ModifierKey.SHIFT, true)
    end)

    assert_helpers.equal(#printed, 0)
end

function tests.shift_h_prints_the_height_of_the_mouse_above_the_last_point()
    local game = install()
    floor_under_mouse(game, fine_x(23), fine_z(40))
    prints_from(function() press(GameKey.M) end)
    -- Points are drawn 1 pixel further up the screen per 10 fine units higher.
    game.to_screen = function(point) return { x = 100, y = 1000 - point.y / 10 } end
    game.mouse = { x = 100, y = 1000 - (3328 + 2000) / 10 }

    local printed = prints_from(function() press(GameKey.H) end)

    assert_helpers.equal(printed[1], "[Riches debug] height 2000 above the last point")
end

function tests.shift_h_asks_for_a_point_first()
    local game = install()
    game.mouse = { x = 100, y = 100 }

    local printed = prints_from(function() press(GameKey.H) end)

    assert_helpers.equal(printed[1], "[Riches debug] measure a point on the floor with Shift+M first")
end

function tests.shift_h_says_so_when_the_mouse_is_below_the_point()
    local game = install()
    floor_under_mouse(game, fine_x(23), fine_z(40))
    prints_from(function() press(GameKey.M) end)
    game.to_screen = function(point) return { x = 100, y = 1000 - point.y / 10 } end
    game.mouse = { x = 100, y = 1000 }

    local printed = prints_from(function() press(GameKey.H) end)

    assert_helpers.equal(printed[1], "[Riches debug] the mouse isn't above the last point, between 0 and 10000")
end

function tests.stop_stops_listening_for_keys()
    install()

    wall_measure.stop()

    assert_helpers.equal(next(Event.KeyDown.subscribers), nil)
end

return tests
