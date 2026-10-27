-- Whether a straight line between two points in the world passes through a box
-- or a wall.
local line_of_sight = {}

local axes = { "x", "y", "z" }

-- Whether the line from one point to another passes through the box between
-- the corners min and max. Works by cutting the line down to the part that is
-- between the box's sides on each axis in turn; if nothing is left, it misses.
---@param from Vector3
---@param to Vector3
---@param min Vector3 The box's corner with the smallest x, y and z
---@param max Vector3 The box's corner with the largest x, y and z
---@return boolean
function line_of_sight.passes_through_box(from, to, min, max)
    -- How far along the line (0 at from, 1 at to) the part inside the box starts and ends.
    local enters, leaves = 0, 1
    for _, axis in ipairs(axes) do
        local start, change = from[axis], to[axis] - from[axis]
        if change == 0 then
            if start < min[axis] or start > max[axis] then
                return false
            end
        else
            local at_min = (min[axis] - start) / change
            local at_max = (max[axis] - start) / change
            enters = math.max(enters, math.min(at_min, at_max))
            leaves = math.min(leaves, math.max(at_min, at_max))
            if enters > leaves then
                return false
            end
        end
    end
    return true
end

---@param point Vector3
---@param min Vector3
---@param max Vector3
---@return boolean
function line_of_sight.is_inside_box(point, min, max)
    for _, axis in ipairs(axes) do
        if point[axis] < min[axis] or point[axis] > max[axis] then
            return false
        end
    end
    return true
end

-- The 2D cross product of two directions seen from above (x and z only).
local function cross_from_above(a_x, a_z, b_x, b_z)
    return a_x * b_z - a_z * b_x
end

-- Whether the line from one point to another passes through a thin, straight
-- wall standing between wall_start and wall_end (only their x and z are used),
-- from bottom up to its top. The top doesn't have to be level: top_at gives
-- its height at each point along the wall (0 at wall_start, 1 at wall_end).
-- Seen from above, the line has to cross the wall; then it passes through if
-- it's between the bottom and the top where it crosses. Touching the wall at
-- the line's very end (at to) doesn't count, so riches standing on a wall's
-- line aren't hidden by it. A wall can have openings, like doorways: is_open_at
-- tells whether there's one at a point on the wall, and the line goes through
-- those without passing through the wall.
---@param from Vector3
---@param to Vector3
---@param wall_start Vector3
---@param wall_end Vector3
---@param bottom number
---@param top_at fun(along_wall: number): number
---@param is_open_at? fun(along_wall: number, height: number): boolean
---@return boolean
function line_of_sight.passes_through_wall(from, to, wall_start, wall_end, bottom, top_at, is_open_at)
    local line_x, line_z = to.x - from.x, to.z - from.z
    local wall_x, wall_z = wall_end.x - wall_start.x, wall_end.z - wall_start.z
    local crossing = cross_from_above(line_x, line_z, wall_x, wall_z)
    if crossing == 0 then
        return false -- parallel, seen from above
    end

    local gap_x, gap_z = wall_start.x - from.x, wall_start.z - from.z
    -- How far along the line (0 at from, 1 at to) and along the wall (0 at its
    -- start, 1 at its end) the two cross.
    local along_line = cross_from_above(gap_x, gap_z, wall_x, wall_z) / crossing
    local along_wall = cross_from_above(gap_x, gap_z, line_x, line_z) / crossing
    if along_line < 0 or along_line >= 1 or along_wall < 0 or along_wall > 1 then
        return false
    end

    local height = from.y + (to.y - from.y) * along_line
    if height < bottom or height > top_at(along_wall) then
        return false
    end
    return not (is_open_at and is_open_at(along_wall, height))
end

return line_of_sight
