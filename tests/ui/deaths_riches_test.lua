local deaths_riches = require("src/ui/deaths_riches")
local db = require("src/database/db")
local assert_helpers = require("tests/helpers/assert")
local fake_event = require("tests/helpers/fake_event")
local fake_game = require("tests/helpers/fake_game")
local fake_persistent_db = require("tests/helpers/fake_persistent_db")

local tile_size = 512
local preload_frames = 30

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

-- The one model that's shown, failing if there isn't exactly one.
local function shown_model(game)
    local visible = fake_game.visible_models(game)
    assert_helpers.equal(#visible, 1)
    return visible[1]
end

-- Puts the camera this far from the riches, this many degrees above them.
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

function tests.builds_a_model_for_every_three_degrees_of_tilt()
    local game = install()

    deaths_riches.start()

    assert_helpers.equal(#game.models, 31)
    assert_helpers.equal(fake_game.tilt_of(game.models[1]), 0)
    assert_helpers.equal(fake_game.tilt_of(game.models[2]), 3)
    assert_helpers.equal(fake_game.tilt_of(game.models[31]), 90)
end

function tests.loads_every_model_tiny_in_the_corner_first()
    local game = install()

    deaths_riches.start()
    draw(preload_frames - 1)

    assert_helpers.equal(#fake_game.visible_models(game), 31)
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
    assert_helpers.equal(game.models[1].width, 400)
end

function tests.shows_nothing_before_the_office_has_been_checked()
    local game = install()
    deaths_riches.start()

    draw(preload_frames + 1)

    assert_helpers.equal(#fake_game.visible_models(game), 0)
end

function tests.shows_one_model_centred_on_the_desk_in_the_office()
    local game = start_in_office()

    draw()

    local model = shown_model(game)
    assert_helpers.equal(model.x, 960 - 200)
    assert_helpers.equal(model.y, 500 - 200)
end

function tests.draws_the_riches_above_the_ground_under_the_desk()
    local game = start_in_office()

    draw()

    assert_helpers.equal(game.converted.x, fake_game.desk.x)
    assert_helpers.equal(game.converted.z, fake_game.desk.z)
    assert_helpers.equal(game.converted.y, 3328 + 1150)
end

function tests.waits_for_the_ground_under_the_desk_to_load()
    local game = start_in_office()

    game.ground_height = 0
    draw()
    assert_helpers.equal(#fake_game.visible_models(game), 0)

    game.ground_height = -1
    draw()
    assert_helpers.equal(#fake_game.visible_models(game), 0)

    game.ground_height = 3328
    draw()
    shown_model(game)
end

function tests.counts_as_in_the_office_up_to_forty_tiles_from_the_desk()
    local game = start_in_office()

    game.move_player(fake_game.desk.x + 40 * tile_size, fake_game.desk.z)
    tick()
    draw()
    shown_model(game)

    game.move_player(fake_game.desk.x + 41 * tile_size, fake_game.desk.z)
    tick()
    draw()
    assert_helpers.equal(#fake_game.visible_models(game), 0)
end

function tests.hides_the_riches_when_their_spot_is_off_screen()
    local cases = { false, { x = -1, y = 500 }, { x = 1921, y = 500 }, { x = 960, y = -1 }, { x = 960, y = 1081 } }
    for _, on_screen in ipairs(cases) do
        local game = start_in_office()
        game.on_screen = on_screen or nil

        draw()

        assert_helpers.equal(#fake_game.visible_models(game), 0)
    end
end

function tests.hides_the_riches_when_the_camera_is_far_away()
    local game = start_in_office()
    camera_at(game, 30001, 45)

    draw()

    assert_helpers.equal(#fake_game.visible_models(game), 0)
end

function tests.tilts_the_hat_by_how_far_the_camera_looks_down()
    local cases = { { 0, 0 }, { 10, 9 }, { 44, 45 }, { 90, 90 } }
    for _, case in ipairs(cases) do
        local game = start_in_office()
        camera_at(game, 3000, case[1])

        draw()

        assert_helpers.equal(fake_game.tilt_of(shown_model(game)), case[2])
    end
end

function tests.never_tilts_further_than_straight_down_or_level()
    local game = start_in_office()
    camera_at(game, 3000, -20)

    draw()

    assert_helpers.equal(fake_game.tilt_of(shown_model(game)), 0)
end

function tests.switches_models_as_the_camera_moves()
    local game = start_in_office()
    camera_at(game, 3000, 0)
    draw()
    local level = shown_model(game)

    camera_at(game, 3000, 90)
    draw()

    assert_helpers.equal(level.hidden, true)
    assert_helpers.equal(fake_game.tilt_of(shown_model(game)), 90)
end

function tests.zooms_out_as_the_camera_moves_away()
    local game = start_in_office()

    camera_at(game, 3000, 45)
    draw()
    local near = shown_model(game).viewDistance

    camera_at(game, 6000, 45)
    draw()
    local far = shown_model(game).viewDistance

    assert_helpers.equal(near, math.floor(3000 * 400 / 1920 / 0.9 / 1.5))
    assert_helpers.equal(far, math.floor(6000 * 400 / 1920 / 0.9 / 1.5))
end

function tests.starting_again_while_running_changes_nothing()
    local game = start_in_office()

    deaths_riches.start()
    draw()

    assert_helpers.equal(#game.models, 31)
    shown_model(game)
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

    assert_helpers.equal(#game.models, 62)
    shown_model(game)
end

return tests
