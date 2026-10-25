local deaths_riches = require("src/world/deaths_riches")
local db = require("src/database/db")
local assert_helpers = require("tests/helpers/assert")
local fake_event = require("tests/helpers/fake_event")
local fake_game = require("tests/helpers/fake_game")
local fake_persistent_db = require("tests/helpers/fake_persistent_db")

local tile_size = 512
local preload_frames = 30
local models_per_spot = 31
local all_model_count = 2 * models_per_spot

-- The spots, in the order their models are built.
local desk = { first_model = 1, position = fake_game.desk, height = 1150 }
local top_left_corner = { first_model = models_per_spot + 1, position = fake_game.top_left_corner, height = 0 }

-- Fresh fakes, with the riches stopped from any earlier test.
local function install()
    deaths_riches.stop()
    fake_persistent_db.install()
    fake_event.install()
    return fake_game.install()
end

local function draw(frames)
    for _ = 1, frames or 1 do
        Event.Draw.fire()
    end
end

local function tick()
    Event.ServerLogic.fire()
end

-- Started, preloaded, and with the player in Death's office.
local function start_in_office()
    local game = install()
    deaths_riches.start()
    draw(preload_frames)
    tick()
    return game
end

-- The spot's models that aren't hidden.
local function visible_at(game, spot)
    local visible = {}
    for index = spot.first_model, spot.first_model + models_per_spot - 1 do
        if game.models[index].hidden == false then
            table.insert(visible, game.models[index])
        end
    end
    return visible
end

-- The one model shown at the spot, failing if there isn't exactly one.
local function shown_at(game, spot)
    local visible = visible_at(game, spot)
    assert_helpers.equal(#visible, 1)
    return visible[1]
end

-- Puts the camera this far from the desk's riches, this many degrees above them.
local function camera_at(game, distance, degrees_up)
    local up = math.rad(degrees_up)
    game.camera = Vector3.new(
        fake_game.desk.x,
        3328 + 1150 + distance * math.sin(up),
        fake_game.desk.z + distance * math.cos(up)
    )
end

local tests = {}

function tests.does_nothing_when_turned_off()
    local game = install()
    db.set_render_deaths_riches(false)

    deaths_riches.start()

    assert_helpers.equal(#game.models, 0)
    assert_helpers.equal(next(Event.Draw.subscribers), nil)
end

function tests.builds_a_model_for_every_three_degrees_of_tilt_at_each_spot()
    local game = install()

    deaths_riches.start()

    assert_helpers.equal(#game.models, all_model_count)
    for _, spot in ipairs({ desk, top_left_corner }) do
        assert_helpers.equal(fake_game.tilt_of(game.models[spot.first_model]), 0)
        assert_helpers.equal(fake_game.tilt_of(game.models[spot.first_model + 1]), 3)
        assert_helpers.equal(fake_game.tilt_of(game.models[spot.first_model + 30]), 90)
    end
end

function tests.puts_each_of_a_spots_items_in_its_own_slot()
    local game = install()

    deaths_riches.start()

    local desk_slots = game.models[desk.first_model].npcCustomisation
    assert_helpers.equal(desk_slots.items[0], "INV_PARTYHAT")
    assert_helpers.equal(desk_slots.items[1], nil)
    assert_helpers.equal(desk_slots.scale, 1)

    local corner_slots = game.models[top_left_corner.first_model].npcCustomisation
    assert_helpers.equal(corner_slots.items[0], "INV_GOLDPEICES_10000")
    assert_helpers.equal(corner_slots.items[1], nil)
end

function tests.loads_every_model_tiny_in_the_corner_first()
    local game = install()

    deaths_riches.start()
    draw(preload_frames - 1)

    assert_helpers.equal(#fake_game.visible_models(game), all_model_count)
    for _, model in ipairs(game.models) do
        assert_helpers.equal(model.width, 1)
        assert_helpers.equal(model.x, 0)
        assert_helpers.equal(model.y, 0)
        assert_helpers.equal(model.viewDistance, 100000)
    end
end

function tests.hides_the_models_again_after_loading_them()
    local game = install()

    deaths_riches.start()
    draw(preload_frames)

    assert_helpers.equal(#fake_game.visible_models(game), 0)
    for _, model in ipairs(game.models) do
        assert_helpers.equal(model.width, 400)
    end
end

function tests.shows_nothing_before_the_office_has_been_checked()
    local game = install()
    deaths_riches.start()

    draw(preload_frames + 1)

    assert_helpers.equal(#fake_game.visible_models(game), 0)
end

function tests.shows_one_model_centred_on_each_spot_in_the_office()
    local game = start_in_office()

    draw()

    for _, spot in ipairs({ desk, top_left_corner }) do
        local on_screen = fake_game.screen_point(spot.position)
        local model = shown_at(game, spot)
        assert_helpers.equal(model.x, math.floor(on_screen.x) - 200)
        assert_helpers.equal(model.y, math.floor(on_screen.y) - 200)
    end
end

function tests.draws_each_spots_riches_at_its_own_height_above_the_ground()
    local game = start_in_office()

    draw()

    assert_helpers.equal(#game.converted, 2)
    for index, spot in ipairs({ desk, top_left_corner }) do
        assert_helpers.equal(game.converted[index].x, spot.position.x)
        assert_helpers.equal(game.converted[index].z, spot.position.z)
        assert_helpers.equal(game.converted[index].y, 3328 + spot.height)
    end
end

function tests.waits_for_the_ground_under_the_spots_to_load()
    local game = start_in_office()

    game.ground_height = 0
    draw()
    assert_helpers.equal(#fake_game.visible_models(game), 0)

    game.ground_height = -1
    draw()
    assert_helpers.equal(#fake_game.visible_models(game), 0)

    game.ground_height = 3328
    draw()
    shown_at(game, desk)
    shown_at(game, top_left_corner)
end

function tests.counts_as_in_the_office_up_to_forty_tiles_from_the_desk()
    local game = start_in_office()

    game.move_player(fake_game.desk.x + 40 * tile_size, fake_game.desk.z)
    tick()
    draw()
    shown_at(game, desk)

    game.move_player(fake_game.desk.x + 41 * tile_size, fake_game.desk.z)
    tick()
    draw()
    assert_helpers.equal(#fake_game.visible_models(game), 0)
end

function tests.hides_riches_whose_spot_is_off_screen()
    local cases = { false, { x = -1, y = 500 }, { x = 1921, y = 500 }, { x = 960, y = -1 }, { x = 960, y = 1081 } }
    for _, off_screen in ipairs(cases) do
        local game = start_in_office()
        game.to_screen = function(point)
            if point.x == fake_game.desk.x and point.z == fake_game.desk.z then
                return off_screen or nil
            end
            return fake_game.screen_point(point)
        end

        draw()

        assert_helpers.equal(#visible_at(game, desk), 0)
        shown_at(game, top_left_corner)
    end
end

function tests.hides_the_riches_when_the_camera_is_far_away()
    local game = start_in_office()
    camera_at(game, 40000, 45)

    draw()

    assert_helpers.equal(#fake_game.visible_models(game), 0)
end

function tests.tilts_the_riches_by_how_far_the_camera_looks_down()
    local cases = { { 0, 0 }, { 10, 9 }, { 44, 45 }, { 90, 90 } }
    for _, case in ipairs(cases) do
        local game = start_in_office()
        camera_at(game, 3000, case[1])

        draw()

        assert_helpers.equal(fake_game.tilt_of(shown_at(game, desk)), case[2])
    end
end

function tests.never_tilts_further_than_level()
    local game = start_in_office()
    camera_at(game, 3000, -20)

    draw()

    assert_helpers.equal(fake_game.tilt_of(shown_at(game, desk)), 0)
end

function tests.switches_models_as_the_camera_moves()
    local game = start_in_office()
    camera_at(game, 3000, 0)
    draw()
    local level = shown_at(game, desk)

    camera_at(game, 3000, 90)
    draw()

    assert_helpers.equal(level.hidden, true)
    assert_helpers.equal(fake_game.tilt_of(shown_at(game, desk)), 90)
end

function tests.zooms_out_as_the_camera_moves_away()
    local game = start_in_office()

    camera_at(game, 3000, 45)
    draw()
    local near = shown_at(game, desk).viewDistance

    camera_at(game, 6000, 45)
    draw()
    local far = shown_at(game, desk).viewDistance

    assert_helpers.equal(near, math.floor(3000 * 400 / 1920 / 1 / 1.5))
    assert_helpers.equal(far, math.floor(6000 * 400 / 1920 / 1 / 1.5))
end

function tests.starting_again_while_running_changes_nothing()
    local game = start_in_office()

    deaths_riches.start()
    draw()

    assert_helpers.equal(#game.models, all_model_count)
    shown_at(game, desk)
end

function tests.stop_removes_the_models_and_stops_listening()
    local game = start_in_office()

    deaths_riches.stop()

    for _, model in ipairs(game.models) do
        assert_helpers.equal(model.destroyed, true)
    end
    assert_helpers.equal(next(Event.Draw.subscribers), nil)
    assert_helpers.equal(next(Event.ServerLogic.subscribers), nil)
end

function tests.can_start_again_after_stopping()
    local game = start_in_office()
    deaths_riches.stop()

    deaths_riches.start()
    draw(preload_frames)
    tick()
    draw()

    assert_helpers.equal(#game.models, 2 * all_model_count)
    assert_helpers.equal(#fake_game.visible_models(game), 2)
end

return tests
