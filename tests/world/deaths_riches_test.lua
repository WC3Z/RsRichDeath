local deaths_riches = require("src/world/deaths_riches")
local db = require("src/database/db")
local assert_helpers = require("tests/helpers/assert")
local fake_event = require("tests/helpers/fake_event")
local fake_game = require("tests/helpers/fake_game")
local fake_persistent_db = require("tests/helpers/fake_persistent_db")

local tile_size = 512
local view_size = 800

-- The spots, in the order their groups are built (one item each).
local desk = { index = 1, position = fake_game.desk, height = 1150 }
local top_left_corner = { index = 2, position = fake_game.top_left_corner, height = 0 }

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

-- Started, and with the player in Death's office.
local function start_in_office()
    local game = install()
    deaths_riches.start()
    tick()
    return game
end

local function group_at(game, spot)
    return game.groups[spot.index]
end

local function camera_at(game, spot)
    return group_at(game, spot).active_camera
end

local function visible_groups(game)
    local visible = {}
    for _, group in ipairs(game.groups) do
        if group.hidden == false then
            table.insert(visible, group)
        end
    end
    return visible
end

-- Rounds to whole numbers, to compare angles worked out with floats.
local function round(number)
    return math.floor(number + 0.5)
end

-- The field of view a group gets when the game's is the given one: the same
-- view, cut down from the screen's 1080 pixel height to the group's.
local function view_fov(game_degrees)
    return 2 * math.deg(math.atan(math.tan(math.rad(game_degrees) / 2) * view_size / 1080))
end

-- Makes ScreenConvert act like a camera looking straight ahead along -z at
-- the focus, with the given vertical field of view: a point above the focus
-- shows higher up the 1080 pixel high screen the narrower the view.
local function project_with_fov(game, degrees)
    local half_height = 1080 / 2
    game.camera = Vector3.new(fake_game.desk.x, 3328 + 1150, fake_game.desk.z + 3000)
    game.to_screen = function(point)
        local up = point.y - game.focus.y
        local ahead = game.camera.z - point.z
        return { x = 960, y = half_height - up / ahead / math.tan(math.rad(degrees) / 2) * half_height }
    end
end

local tests = {}

function tests.does_nothing_when_turned_off()
    local game = install()
    db.set_render_deaths_riches(false)

    deaths_riches.start()

    assert_helpers.equal(#game.groups, 0)
    assert_helpers.equal(#game.models, 0)
    assert_helpers.equal(next(Event.Draw.subscribers), nil)
end

function tests.builds_a_model_group_per_spot()
    local game = install()

    deaths_riches.start()

    assert_helpers.equal(#game.groups, 2)
    for _, group in ipairs(game.groups) do
        assert_helpers.equal(group.parent, game.root)
        assert_helpers.equal(group.width, view_size)
        assert_helpers.equal(group.height, view_size)
    end
end

function tests.the_groups_cameras_are_see_through_and_look_at_a_target()
    local game = install()

    deaths_riches.start()

    for _, group in ipairs(game.groups) do
        assert_helpers.equal(group.active_camera.clearColour.w, 0)
        assert_helpers.equal(group.active_camera.useLookAt, true)
        assert_helpers.equal(group.transition, "NONE")
    end
end

function tests.puts_each_spots_items_in_the_middle_of_its_group()
    local game = install()

    deaths_riches.start()

    assert_helpers.equal(#game.models, 2)
    assert_helpers.equal(game.models[desk.index].model_id, "INV_PARTYHAT")
    assert_helpers.equal(game.models[top_left_corner.index].model_id, "INV_GOLDPEICES_10000")
    for index, model in ipairs(game.models) do
        assert_helpers.equal(model.parent, game.groups[index])
        assert_helpers.equal(model.type, "MODEL")
        assert_helpers.equal(model.width, view_size)
        assert_helpers.equal(model.transform.position.x, 0)
        assert_helpers.equal(model.transform.position.y, 0)
        assert_helpers.equal(model.transform.position.z, 0)
        assert_helpers.equal(model.transform.scale.x, 1.5)
    end
end

function tests.shows_nothing_before_the_office_has_been_checked()
    local game = install()
    deaths_riches.start()

    draw()

    assert_helpers.equal(#visible_groups(game), 0)
end

function tests.centres_each_spots_group_on_the_spot()
    local game = start_in_office()

    draw()

    for _, spot in ipairs({ desk, top_left_corner }) do
        local on_screen = fake_game.screen_point(spot.position)
        local group = group_at(game, spot)
        assert_helpers.equal(group.hidden, false)
        assert_helpers.equal(group.x, math.floor(on_screen.x) - view_size // 2)
        assert_helpers.equal(group.y, math.floor(on_screen.y) - view_size // 2)
    end
end

function tests.each_group_sees_its_riches_from_where_the_game_camera_is()
    local game = start_in_office()

    draw()

    for _, spot in ipairs({ desk, top_left_corner }) do
        local camera = camera_at(game, spot)
        assert_helpers.equal(camera.position.x, game.camera.x - spot.position.x)
        assert_helpers.equal(camera.position.y, game.camera.y - (3328 + spot.height))
        assert_helpers.equal(camera.position.z, game.camera.z - spot.position.z)
        assert_helpers.equal(camera.lookAt.x, 0)
        assert_helpers.equal(camera.lookAt.y, 0)
        assert_helpers.equal(camera.lookAt.z, 0)
    end
end

function tests.swaps_the_groups_camera_instead_of_adding_more()
    local game = start_in_office()

    draw(3)

    for _, group in ipairs(game.groups) do
        local cameras = 0
        for _ in pairs(group.cameras) do
            cameras = cameras + 1
        end
        assert_helpers.equal(cameras, 1)
    end
end

function tests.narrows_the_games_measured_field_of_view_to_the_group()
    for _, degrees in ipairs({ 45, 60, 75 }) do
        local game = start_in_office()
        project_with_fov(game, degrees)

        draw()

        assert_helpers.equal(round(camera_at(game, desk).fov), round(view_fov(degrees)))
    end
end

function tests.eases_into_later_field_of_view_measurements()
    local game = start_in_office()
    project_with_fov(game, 60)
    draw()

    project_with_fov(game, 80)
    draw()
    local first_step = camera_at(game, desk).fov
    draw(200)
    local settled = camera_at(game, desk).fov

    assert_helpers.equal(round(first_step), round(view_fov(61)))
    assert_helpers.equal(round(settled), round(view_fov(80)))
end

function tests.keeps_the_last_field_of_view_when_it_cant_be_measured()
    local game = start_in_office()
    project_with_fov(game, 45)
    draw()

    -- Only the focus and the point above it are off screen, so the corner's
    -- riches (below the focus) still show.
    game.to_screen = function(point)
        if point.y >= game.focus.y then
            return nil
        end
        return fake_game.screen_point(point)
    end
    draw()

    assert_helpers.equal(round(camera_at(game, top_left_corner).fov), round(view_fov(45)))
end

function tests.waits_for_the_ground_under_the_spots_to_load()
    local game = start_in_office()

    game.ground_height = 0
    draw()
    assert_helpers.equal(#visible_groups(game), 0)

    game.ground_height = -1
    draw()
    assert_helpers.equal(#visible_groups(game), 0)

    game.ground_height = 3328
    draw()
    assert_helpers.equal(#visible_groups(game), 2)
end

function tests.counts_as_in_the_office_up_to_forty_tiles_from_the_desk()
    local game = start_in_office()

    game.move_player(fake_game.desk.x + 40 * tile_size, fake_game.desk.z)
    tick()
    draw()
    assert_helpers.equal(#visible_groups(game), 2)

    game.move_player(fake_game.desk.x + 41 * tile_size, fake_game.desk.z)
    tick()
    draw()
    assert_helpers.equal(#visible_groups(game), 0)
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

        assert_helpers.equal(group_at(game, desk).hidden, true)
        assert_helpers.equal(group_at(game, top_left_corner).hidden, false)
    end
end

function tests.hides_the_riches_when_the_camera_is_far_away()
    local game = start_in_office()
    game.camera = Vector3.new(fake_game.desk.x, 3328, fake_game.desk.z + 40000)

    draw()

    assert_helpers.equal(#visible_groups(game), 0)
end

function tests.starting_again_while_running_changes_nothing()
    local game = start_in_office()

    deaths_riches.start()
    draw()

    assert_helpers.equal(#game.groups, 2)
    assert_helpers.equal(#game.models, 2)
end

function tests.stop_removes_the_groups_and_models_and_stops_listening()
    local game = start_in_office()

    deaths_riches.stop()

    for _, component in ipairs({ game.groups[1], game.groups[2], game.models[1], game.models[2] }) do
        assert_helpers.equal(component.destroyed, true)
    end
    assert_helpers.equal(next(Event.Draw.subscribers), nil)
    assert_helpers.equal(next(Event.ServerLogic.subscribers), nil)
end

function tests.can_start_again_after_stopping()
    local game = start_in_office()
    deaths_riches.stop()

    deaths_riches.start()
    tick()
    draw()

    assert_helpers.equal(#game.groups, 4)
    assert_helpers.equal(#visible_groups(game), 2)
end

return tests
