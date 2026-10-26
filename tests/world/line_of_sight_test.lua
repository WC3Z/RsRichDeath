local line_of_sight = require("src/world/line_of_sight")
local assert_helpers = require("tests/helpers/assert")

local function point(x, y, z)
    return { x = x, y = y, z = z }
end

-- A box 10 wide on each side, from (10, 0, 10) to (20, 10, 20).
local min = point(10, 0, 10)
local max = point(20, 10, 20)

local function passes(from, to)
    return line_of_sight.passes_through_box(from, to, min, max)
end

local tests = {}

function tests.a_line_straight_through_the_box_passes_through_it()
    assert_helpers.equal(passes(point(0, 5, 15), point(30, 5, 15)), true)
end

function tests.a_slanted_line_through_the_box_passes_through_it()
    assert_helpers.equal(passes(point(0, 0, 0), point(30, 10, 30)), true)
end

function tests.a_line_beside_the_box_misses_it()
    assert_helpers.equal(passes(point(0, 5, 25), point(30, 5, 25)), false)
end

function tests.a_line_over_the_box_misses_it()
    assert_helpers.equal(passes(point(0, 11, 15), point(30, 11, 15)), false)
end

function tests.a_line_that_ends_before_the_box_misses_it()
    assert_helpers.equal(passes(point(0, 5, 15), point(9, 5, 15)), false)
end

function tests.a_line_that_starts_after_the_box_misses_it()
    assert_helpers.equal(passes(point(21, 5, 15), point(30, 5, 15)), false)
end

function tests.a_line_that_only_clips_a_corner_passes_through_it()
    assert_helpers.equal(passes(point(5, 5, 15), point(15, 5, 5)), true)
end

function tests.a_line_along_an_axis_outside_the_box_misses_it()
    assert_helpers.equal(passes(point(15, 20, 15), point(15, 30, 15)), false)
end

function tests.a_line_ending_inside_the_box_passes_through_it()
    assert_helpers.equal(passes(point(0, 5, 15), point(15, 5, 15)), true)
end

function tests.tells_whether_a_point_is_inside_the_box()
    assert_helpers.equal(line_of_sight.is_inside_box(point(15, 5, 15), min, max), true)
    assert_helpers.equal(line_of_sight.is_inside_box(point(15, 11, 15), min, max), false)
    assert_helpers.equal(line_of_sight.is_inside_box(point(25, 5, 15), min, max), false)
end

-- A diagonal wall from (10, ?, 10) to (20, ?, 20), from 0 up to 10.
local wall_start = point(10, 0, 10)
local wall_end = point(20, 0, 20)

local function through_wall(from, to)
    return line_of_sight.passes_through_wall(from, to, wall_start, wall_end, 0, 10)
end

function tests.a_line_across_a_diagonal_wall_passes_through_it()
    assert_helpers.equal(through_wall(point(10, 5, 20), point(20, 5, 10)), true)
end

function tests.a_line_over_a_wall_misses_it()
    assert_helpers.equal(through_wall(point(10, 11, 20), point(20, 11, 10)), false)
end

function tests.a_line_that_climbs_over_a_wall_misses_it()
    -- Below the top at the start, but 12 high by the time it gets to the wall.
    assert_helpers.equal(through_wall(point(10, 4, 20), point(20, 20, 10)), false)
end

function tests.a_line_past_the_end_of_a_wall_misses_it()
    assert_helpers.equal(through_wall(point(20, 5, 30), point(30, 5, 20)), false)
end

function tests.a_line_that_stops_before_a_wall_misses_it()
    assert_helpers.equal(through_wall(point(10, 5, 20), point(14, 5, 16)), false)
end

function tests.a_line_alongside_a_wall_misses_it()
    assert_helpers.equal(through_wall(point(10, 5, 11), point(20, 5, 21)), false)
end

function tests.a_line_that_ends_on_a_wall_misses_it()
    assert_helpers.equal(through_wall(point(10, 5, 20), point(15, 5, 15)), false)
end

return tests
