local deaths_riches = require("src/world/deaths_riches")
local db = require("src/database/db")
local assert_helpers = require("tests/helpers/assert")
local fake_event = require("tests/helpers/fake_event")
local fake_game = require("tests/helpers/fake_game")
local fake_persistent_db = require("tests/helpers/fake_persistent_db")
local office_walls = require("src/world/office_walls")

local tile_size = 512
local view_size = 800

-- The spots, in the order their groups are built. The spot beside Death comes
-- last, with two items (the plinth and the coins on it).
local desk = { index = 1, position = fake_game.desk, height = 1150 }
local top_left_corner = { index = 2, position = fake_game.top_left_corner, height = 0 }
local spot_count = 3
local model_count = 4

-- Fresh fakes, with the riches stopped from any earlier test, and no walls.
local function install()
    deaths_riches.stop()
    office_walls.boxes = {}
    office_walls.walls = {}
    office_walls.middle = { 30, 38 }
    office_walls.show = false
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

-- Each spot's group is in a layer of its own, which is what's moved and hidden.
local function layer_at(game, spot)
    return game.layers[spot.index]
end

local function visible_layers(game)
    local visible = {}
    for _, layer in ipairs(game.layers) do
        if layer.hidden == false then
            table.insert(visible, layer)
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

-- Makes ScreenConvert act like the game's camera on a 1920x1080 screen,
-- looking from game.camera at game.focus with the given vertical field of view.
local function project_like_camera(game, degrees)
    local scale = 540 / math.tan(math.rad(degrees) / 2)
    game.to_screen = function(point)
        local camera, focus = game.camera, game.focus
        local forward = Vector3.new(focus.x - camera.x, focus.y - camera.y, focus.z - camera.z)
        local length = forward.length
        forward = Vector3.new(forward.x / length, forward.y / length, forward.z / length)
        -- right = forward x up, and up = right x forward
        local right = Vector3.new(-forward.z, 0, forward.x)
        length = right.length
        right = Vector3.new(right.x / length, 0, right.z / length)
        local up = Vector3.new(right.y * forward.z - right.z * forward.y,
            right.z * forward.x - right.x * forward.z, right.x * forward.y - right.y * forward.x)
        local to_point = Vector3.new(point.x - camera.x, point.y - camera.y, point.z - camera.z)
        local function along(axis) return to_point.x * axis.x + to_point.y * axis.y + to_point.z * axis.z end
        local ahead = along(forward)
        -- Whole pixels, like the game gives.
        return { x = round(960 + along(right) / ahead * scale), y = round(540 - along(up) / ahead * scale) }
    end
end

-- The game camera looking straight ahead at the focus from the given distance
-- (3000 if not given), with the given vertical field of view.
local function project_with_fov(game, degrees, distance)
    game.camera = Vector3.new(fake_game.desk.x, 3328 + 1150, fake_game.desk.z + (distance or 3000))
    project_like_camera(game, degrees)
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

function tests.builds_a_model_group_in_a_layer_per_spot()
    local game = install()

    deaths_riches.start()

    assert_helpers.equal(#game.groups, spot_count)
    assert_helpers.equal(#game.layers, spot_count)
    for index, group in ipairs(game.groups) do
        local layer = game.layers[index]
        assert_helpers.equal(layer.parent, game.root)
        assert_helpers.equal(group.parent, layer)
        assert_helpers.equal(group.x, 0)
        assert_helpers.equal(group.y, 0)
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

    assert_helpers.equal(#game.models, model_count)
    assert_helpers.equal(game.models[1].model_id, "INV_PARTYHAT")
    assert_helpers.equal(game.models[2].model_id, "INV_GOLDPEICES_10000")
    assert_helpers.equal(game.models[3].model_id, "HUMAN_FURNITURE_GOLD_PILE_PLINTH")
    assert_helpers.equal(game.models[4].model_id, "HUMAN_FURNITURE_GOLD_PILE_COINS_HUGE")
    -- Each spot's items are in its own group, and both of the last spot's in its group.
    local groups = { game.groups[1], game.groups[2], game.groups[3], game.groups[3] }
    for index, model in ipairs(game.models) do
        assert_helpers.equal(model.parent, groups[index])
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

    assert_helpers.equal(#visible_layers(game), 0)
end

function tests.centres_each_spots_layer_on_the_spot()
    local game = start_in_office()

    draw()

    for _, spot in ipairs({ desk, top_left_corner }) do
        local on_screen = fake_game.screen_point(spot.position)
        local layer = layer_at(game, spot)
        assert_helpers.equal(layer.hidden, false)
        assert_helpers.equal(layer.x, math.floor(on_screen.x) - view_size // 2)
        assert_helpers.equal(layer.y, math.floor(on_screen.y) - view_size // 2)
        assert_helpers.equal(layer.height, view_size)
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

-- Puts the game camera nearly straight above the focus (at the desk), a
-- little towards the given side, looking down at it.
local function look_down_from(game, side_x, side_z)
    game.camera = Vector3.new(game.focus.x + side_x, game.focus.y + 5000, game.focus.z + side_z)
end

local function roll_at(game, spot)
    return math.deg(camera_at(game, spot).yawPitchRoll.z)
end

function tests.does_not_roll_a_camera_that_looks_the_same_way_as_the_games()
    local game = start_in_office()

    draw()

    -- The game's camera looks straight at the desk's riches.
    assert_helpers.equal(round(roll_at(game, desk)), 0)
end

function tests.rolls_to_turn_with_the_game_camera_when_looking_down()
    local game = start_in_office()

    look_down_from(game, 0, 10)
    draw()
    local facing_north = roll_at(game, top_left_corner)
    look_down_from(game, 10, 0)
    draw()
    local facing_west = roll_at(game, top_left_corner)

    -- A quarter turn of the game's camera turns the riches about a quarter
    -- turn too. Not exactly, since the corner is seen at an angle.
    local turned = math.abs(facing_west - facing_north) % 360
    assert_helpers.equal(turned > 80 and turned < 100, true)
end

function tests.items_face_the_same_way_unless_turned()
    local game = install()

    deaths_riches.start()

    for _, model in ipairs(game.models) do
        assert_helpers.equal(model.transform.rotation.x, 0)
    end
end

function tests.measures_the_same_field_of_view_when_looking_down()
    local game = start_in_office()
    look_down_from(game, 0, 10)
    project_like_camera(game, 60)

    draw()

    assert_helpers.equal(round(camera_at(game, desk).fov), round(view_fov(60)))
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

function tests.measures_the_field_of_view_with_the_camera_close()
    local game = start_in_office()
    project_with_fov(game, 60, 300)

    draw()

    assert_helpers.equal(round(camera_at(game, desk).fov), round(view_fov(60)))
end

function tests.ignores_measurements_where_the_point_beside_the_focus_is_off_screen()
    local game = start_in_office()
    project_with_fov(game, 45)
    draw()

    local projection = game.to_screen
    game.to_screen = function(point)
        local on_screen = projection(point)
        if point.x ~= game.focus.x then
            on_screen.x = -100
        end
        return on_screen
    end
    draw()

    assert_helpers.equal(round(camera_at(game, desk).fov), round(view_fov(45)))
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
    assert_helpers.equal(#visible_layers(game), 0)

    game.ground_height = -1
    draw()
    assert_helpers.equal(#visible_layers(game), 0)

    game.ground_height = 3328
    draw()
    assert_helpers.equal(#visible_layers(game), spot_count)
end

function tests.counts_as_in_the_office_up_to_forty_tiles_from_the_desk()
    local game = start_in_office()

    game.move_player(fake_game.desk.x + 40 * tile_size, fake_game.desk.z)
    tick()
    draw()
    assert_helpers.equal(#visible_layers(game), spot_count)

    game.move_player(fake_game.desk.x + 41 * tile_size, fake_game.desk.z)
    tick()
    draw()
    assert_helpers.equal(#visible_layers(game), 0)
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

        assert_helpers.equal(layer_at(game, desk).hidden, true)
        assert_helpers.equal(layer_at(game, top_left_corner).hidden, false)
    end
end

function tests.hides_the_riches_when_the_camera_is_far_away()
    local game = start_in_office()
    game.camera = Vector3.new(fake_game.desk.x, 3328, fake_game.desk.z + 40000)

    draw()

    assert_helpers.equal(#visible_layers(game), 0)
end

-- A wall two to three tiles north of the desk, as high as the camera's line
-- to the desk's riches is there (the camera is 3000 north and 3000 up).
local wall_north_of_desk = { from = { 29, 40 }, to = { 29, 41 }, height = 4000 }

function tests.hides_riches_on_the_tile_the_player_stands_on()
    local game = start_in_office()

    game.move_player(fake_game.top_left_corner.x, fake_game.top_left_corner.z)
    tick()
    draw()

    assert_helpers.equal(layer_at(game, top_left_corner).hidden, true)
    assert_helpers.equal(layer_at(game, desk).hidden, false)
end

function tests.shows_the_riches_again_when_the_player_steps_off()
    local game = start_in_office()
    game.move_player(fake_game.top_left_corner.x, fake_game.top_left_corner.z)
    tick()
    draw()

    game.move_player(fake_game.top_left_corner.x + tile_size, fake_game.top_left_corner.z)
    tick()
    draw()

    assert_helpers.equal(layer_at(game, top_left_corner).hidden, false)
end

function tests.hides_riches_behind_a_wall()
    local game = start_in_office()
    office_walls.boxes = { wall_north_of_desk }

    draw()

    assert_helpers.equal(layer_at(game, desk).hidden, true)
    assert_helpers.equal(layer_at(game, top_left_corner).hidden, false)
end

function tests.shows_riches_the_camera_sees_over_a_wall()
    local game = start_in_office()
    office_walls.boxes = { { from = { 29, 40 }, to = { 29, 41 }, height = 1000 } }

    draw()

    assert_helpers.equal(layer_at(game, desk).hidden, false)
end

function tests.a_wall_the_riches_stand_in_doesnt_hide_them()
    local game = start_in_office()
    office_walls.boxes = { { from = { 28, 37 }, to = { 30, 39 }, height = 2000 } }

    draw()

    assert_helpers.equal(layer_at(game, desk).hidden, false)
end

function tests.ignores_walls_whose_ground_hasnt_loaded()
    local game = start_in_office()
    office_walls.boxes = { wall_north_of_desk }
    draw()

    -- The riches wait for their own ground too, so only the walls' ground is faked away.
    local loaded = World.GetGroundHeight
    World.GetGroundHeight = function(level, x, z)
        if z > fake_game.desk.z + 512 and z < fake_game.desk.z + 4 * 512 then
            return 0
        end
        return loaded(level, x, z)
    end
    draw()

    assert_helpers.equal(layer_at(game, desk).hidden, false)
end

-- A diagonal wall crossing the camera's line to the desk's riches about three
-- tiles north of the desk, as high as that line is there.
local diagonal_wall = { from = { 28, 40 }, to = { 30, 42 }, height = 4000 }

function tests.hides_riches_behind_a_diagonal_wall()
    local game = start_in_office()
    office_walls.walls = { diagonal_wall }

    draw()

    assert_helpers.equal(layer_at(game, desk).hidden, true)
    assert_helpers.equal(layer_at(game, top_left_corner).hidden, false)
end

function tests.shows_riches_the_camera_sees_over_a_diagonal_wall()
    local game = start_in_office()
    office_walls.walls = { { from = { 28, 40 }, to = { 30, 42 }, height = 1000 } }

    draw()

    assert_helpers.equal(layer_at(game, desk).hidden, false)
end

-- The hoard beside Death, which is 1800 tall. A one-tile box just in front of
-- it on the camera's side, as high as the desk, is in the way of its bottom
-- but not of its top.
local beside_death = { index = 3 }
local desk_high_box = { from = { 31, 41 }, to = { 31, 41 }, height = 1100 }

function tests.cuts_off_riches_where_they_go_behind_a_low_wall()
    local game = start_in_office()
    project_like_camera(game, 60)
    office_walls.boxes = { desk_high_box }

    draw()

    local layer = layer_at(game, beside_death)
    assert_helpers.equal(layer.hidden, false)
    -- The riches' bottom is in the middle of the layer, so only rows above it show.
    assert_helpers.equal(layer.height > 0 and layer.height < view_size // 2, true)
end

function tests.hides_riches_that_are_behind_a_wall_all_the_way_up()
    local game = start_in_office()
    project_like_camera(game, 60)
    office_walls.boxes = { { from = { 31, 41 }, to = { 31, 41 }, height = 4000 } }

    draw()

    assert_helpers.equal(layer_at(game, beside_death).hidden, true)
end

function tests.shows_riches_whole_when_nothing_is_in_the_way()
    local game = start_in_office()
    project_like_camera(game, 60)

    draw()

    local layer = layer_at(game, beside_death)
    assert_helpers.equal(layer.hidden, false)
    assert_helpers.equal(layer.height, view_size)
end

function tests.draws_a_wall_as_a_panel_when_asked_to()
    local game = start_in_office()
    office_walls.walls = { diagonal_wall }
    office_walls.show = true

    draw()

    assert_helpers.equal(#game.shapes, 1)
    local corners = game.shapes[1].shapePositions
    local function middle(square, tile) return (square * 64 + tile) * tile_size + tile_size // 2 end
    assert_helpers.equal(corners[1].x, middle(6, 28))
    assert_helpers.equal(corners[1].y, 3328)
    assert_helpers.equal(corners[1].z, middle(10, 40))
    assert_helpers.equal(corners[3].x, middle(6, 30))
    assert_helpers.equal(corners[3].y, 3328 + 4000)
    assert_helpers.equal(corners[3].z, middle(10, 42))
end

function tests.places_walls_between_tiles_for_fractions()
    local game = start_in_office()
    office_walls.walls = { { from = { 28.5, 40 }, to = { 30, 41.25 }, height = 4000 } }
    office_walls.show = true

    draw()

    local corners = game.shapes[1].shapePositions
    local function middle(square, tile) return (square * 64 + tile) * tile_size + tile_size // 2 end
    assert_helpers.equal(corners[1].x, middle(6, 28) + tile_size / 2)
    assert_helpers.equal(corners[1].z, middle(10, 40))
    assert_helpers.equal(corners[2].x, middle(6, 30))
    assert_helpers.equal(corners[2].z, middle(10, 41) + tile_size / 4)
end

function tests.hides_riches_behind_a_wall_with_a_sloped_top()
    local game = start_in_office()
    -- The camera's line to the desk crosses this wall in its middle, where
    -- its top is halfway between 4000 and 0.
    office_walls.walls = { { from = { 28, 40, 4000 }, to = { 30, 42, 0 } } }
    draw()
    local low_middle = layer_at(game, desk).hidden

    office_walls.walls = { { from = { 28, 40, 8000 }, to = { 30, 42, 4000 } } }
    draw()
    local high_middle = layer_at(game, desk).hidden

    assert_helpers.equal(low_middle, false)
    assert_helpers.equal(high_middle, true)
end

function tests.draws_a_sloped_top_from_its_ends_heights()
    local game = start_in_office()
    office_walls.walls = { { from = { 28, 40, 3000 }, to = { 30, 42, 1000 }, height = 9999 } }
    office_walls.show = true

    draw()

    local corners = game.shapes[1].shapePositions
    assert_helpers.equal(corners[3].y, 3328 + 1000)
    assert_helpers.equal(corners[4].y, 3328 + 3000)
end

function tests.hides_riches_behind_the_top_of_an_arched_wall()
    local game = start_in_office()
    -- The camera's line to the desk crosses this wall in its middle, about
    -- 2700 above the ground: over the ends' 1000, but under the arch's peak.
    office_walls.walls = { { from = { 28, 40 }, to = { 30, 42 }, height = 1000 } }
    draw()
    local without_arch = layer_at(game, desk).hidden

    office_walls.walls = { { from = { 28, 40 }, to = { 30, 42 }, height = 1000, arch = 4000 } }
    draw()
    local with_arch = layer_at(game, desk).hidden

    assert_helpers.equal(without_arch, false)
    assert_helpers.equal(with_arch, true)
end

function tests.draws_an_arched_top_through_its_peak()
    local game = start_in_office()
    office_walls.walls = { { from = { 28, 40 }, to = { 30, 42 }, height = 1000, arch = 4000 } }
    office_walls.show = true

    draw()

    local corners = game.shapes[1].shapePositions
    -- The 2 bottom corners, then 13 points along the top from end to start.
    assert_helpers.equal(#corners, 15)
    assert_helpers.equal(corners[3].y, 3328 + 1000)
    assert_helpers.equal(round(corners[9].y), 3328 + 4000)
    assert_helpers.equal(corners[15].y, 3328 + 1000)
    -- Pointed: a quarter of the way along, it's lower than a round arch
    -- (which would be at sqrt(0.75) of the way up), as it rises into a point.
    local quarter_up = (corners[6].y - 3328 - 1000) / 3000
    assert_helpers.equal(quarter_up > 0.7 and quarter_up < math.sqrt(0.75), true)
end

function tests.moves_walls_and_boxes_down_by_a_negative_offset()
    local game = start_in_office()
    office_walls.walls = { { from = { 28, 40 }, to = { 30, 42 }, height = 4000, offset = -500 } }
    office_walls.boxes = { { from = { 29, 40 }, to = { 29, 41 }, height = 4000, offset = -500 } }
    office_walls.show = true

    draw()

    local box = game.shapes[1].shapePositions
    assert_helpers.equal(box[1].y, 3328 - 500)
    assert_helpers.equal(box[7].y, 3328 - 500 + 4000)
    local wall = game.shapes[2].shapePositions
    assert_helpers.equal(wall[1].y, 3328 - 500)
    assert_helpers.equal(wall[3].y, 3328 - 500 + 4000)
end

function tests.a_lowered_wall_no_longer_hides_what_its_old_top_did()
    local game = start_in_office()
    -- The camera's line to the desk crosses this wall about 2700 up, so it
    -- hides the desk at 3000 high, but not once moved 500 down.
    office_walls.walls = { { from = { 28, 40 }, to = { 30, 42 }, height = 3000 } }
    draw()
    local before = layer_at(game, desk).hidden

    office_walls.walls = { { from = { 28, 40 }, to = { 30, 42 }, height = 3000, offset = -500 } }
    draw()
    local lowered = layer_at(game, desk).hidden

    assert_helpers.equal(before, true)
    assert_helpers.equal(lowered, false)
end

function tests.the_far_face_of_a_thick_wall_hides_riches_too()
    local game = start_in_office()
    -- The camera's line to the desk crosses the mapped line about 2700 up, so
    -- a 2500 high thin wall doesn't hide the desk. Made thick towards the
    -- desk, its other face is where the line has dropped lower, under 2500.
    office_walls.walls = { { from = { 28, 40 }, to = { 30, 42 }, height = 2500 } }
    draw()
    local thin = layer_at(game, desk).hidden

    office_walls.walls = { { from = { 28, 40 }, to = { 30, 42 }, height = 2500, thickness = -512 } }
    draw()
    local thick = layer_at(game, desk).hidden

    assert_helpers.equal(thin, false)
    assert_helpers.equal(thick, true)
end

function tests.thick_walls_grow_away_from_the_offices_middle()
    local game = start_in_office()
    -- A diagonal wall north-west of the middle (30, 38): away from the middle
    -- is towards -x and +z.
    office_walls.walls = { { from = { 28, 40 }, to = { 30, 42 }, height = 2500, thickness = 512 } }
    office_walls.show = true

    draw()

    -- The mapped face, the far face, and the lines joining them.
    assert_helpers.equal(#game.shapes, 3)
    local mapped, far = game.shapes[1].shapePositions, game.shapes[2].shapePositions
    local shift = 512 / math.sqrt(2)
    assert_helpers.equal(round(far[1].x), round(mapped[1].x - shift))
    assert_helpers.equal(round(far[1].z), round(mapped[1].z + shift))
    assert_helpers.equal(#game.shapes[3].shapeLines, 8)
end

function tests.thin_walls_have_one_face()
    local game = start_in_office()
    office_walls.walls = { { from = { 28, 40 }, to = { 30, 42 }, height = 2500 } }
    office_walls.show = true

    draw()

    assert_helpers.equal(#game.shapes, 1)
end

function tests.draws_the_walls_when_asked_to()
    local game = start_in_office()
    office_walls.boxes = { wall_north_of_desk }
    office_walls.show = true

    draw()

    assert_helpers.equal(#game.shapes, 1)
    local corners = game.shapes[1].shapePositions
    local first_tile_start = (6 * 64 + 29) * tile_size
    assert_helpers.equal(corners[1].x, first_tile_start)
    assert_helpers.equal(corners[1].y, 3328)
    assert_helpers.equal(corners[1].z, (10 * 64 + 40) * tile_size)
    assert_helpers.equal(corners[7].x, first_tile_start + tile_size)
    assert_helpers.equal(corners[7].y, 3328 + 4000)
    assert_helpers.equal(corners[7].z, (10 * 64 + 42) * tile_size)
    assert_helpers.equal(#game.shapes[1].shapeLines, 24)
end

function tests.shows_the_walls_if_that_was_saved()
    local game = install()
    db.set_show_office_walls(true)
    office_walls.boxes = { wall_north_of_desk }

    deaths_riches.start()
    tick()
    draw()

    assert_helpers.equal(#game.shapes, 1)
end

function tests.doesnt_draw_the_walls_unless_asked_to()
    local game = start_in_office()
    office_walls.boxes = { wall_north_of_desk }

    draw()

    assert_helpers.equal(#game.shapes, 0)
end

function tests.starting_again_while_running_changes_nothing()
    local game = start_in_office()

    deaths_riches.start()
    draw()

    assert_helpers.equal(#game.groups, spot_count)
    assert_helpers.equal(#game.models, model_count)
end

function tests.stop_removes_the_groups_and_models_and_stops_listening()
    local game = start_in_office()

    deaths_riches.stop()

    for _, group in ipairs(game.groups) do
        assert_helpers.equal(group.destroyed, true)
    end
    for _, layer in ipairs(game.layers) do
        assert_helpers.equal(layer.destroyed, true)
    end
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
    tick()
    draw()

    assert_helpers.equal(#game.groups, 2 * spot_count)
    assert_helpers.equal(#visible_layers(game), spot_count)
end

return tests
