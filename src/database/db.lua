local Db = {}

local render_deaths_riches_key = "renderDeathRiches"
local show_office_walls_key = "showOfficeWalls"
local hiding_strips_key = "hidingStrips"
local death_cost_key = "deathCost"

-- Get whether we should render death's riches or not
---@return boolean
function Db.get_render_deaths_riches()
    local saved = PersistentDB:GetBool(render_deaths_riches_key)
    if saved == nil then
        return true
    end
    return saved
end


-- Set whether we should render death's riches or not
---@param selected boolean
function Db.set_render_deaths_riches(selected)
    PersistentDB:SetBool(render_deaths_riches_key, selected)
end


-- Get whether the walls the riches hide behind are drawn, to check where they are
---@return boolean
function Db.get_show_office_walls()
    return PersistentDB:GetBool(show_office_walls_key) == true
end

-- Set whether the walls the riches hide behind are drawn
---@param selected boolean
function Db.set_show_office_walls(selected)
    PersistentDB:SetBool(show_office_walls_key, selected)
end


-- Get how many strips riches are hidden in at most (see RichesSpot's
-- strips). More looks better but costs frame rate; 1 until changed.
---@return integer
function Db.get_hiding_strips()
    return PersistentDB:GetInt(hiding_strips_key) or 1
end

-- Set how many strips riches are hidden in at most
---@param strips integer
function Db.set_hiding_strips(strips)
    PersistentDB:SetInt(hiding_strips_key, strips)
end


-- Gets the total death cost
---@return integer
function Db.get_death_cost()
    local saved = PersistentDB:GetInt(death_cost_key)
    if saved == nil then
        return 0
    end
    return saved
end

-- Adds deaths cost to the existing amount
---@param cost Integer
function Db.add_death_cost(cost)
    local currentCost = Db.get_death_cost()
    PersistentDB:SetInt(death_cost_key, currentCost + cost)
end

return Db
