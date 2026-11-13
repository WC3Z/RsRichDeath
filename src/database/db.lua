-- The player's settings and death cost, saved for each game account (see
-- account_storage).
local storage = require("src/database/account_storage")

local Db = {}

local render_deaths_riches_key = "renderDeathRiches"
local death_cost_key = "deathCost"
local death_count_key = "deathCount"

-- Get whether we should render death's riches or not
---@return boolean
function Db.get_render_deaths_riches()
    local saved = storage.get_bool(render_deaths_riches_key)
    if saved == nil then
        return true
    end
    return saved
end


-- Set whether we should render death's riches or not
---@param selected boolean
function Db.set_render_deaths_riches(selected)
    storage.set_bool(render_deaths_riches_key, selected)
end


-- Gets the total death cost
---@return integer
function Db.get_death_cost()
    local saved = storage.get_int(death_cost_key)
    if saved == nil then
        return 0
    end
    return saved
end

-- Adds deaths cost to the existing amount
---@param cost Integer
function Db.add_death_cost(cost)
    local currentCost = Db.get_death_cost()
    storage.set_int(death_cost_key, currentCost + cost)
end

function Db.get_death_count()
    local saved = storage.get_int(death_count_key)
    if saved == nil then
        return 0
    end
    return saved
end

-- Adds deaths cost to the existing amount
---@param cost Integer
function Db.increment_death_count()
    local deathCount = Db.get_death_count()
    storage.set_int(death_count_key, deathCount + 1)
end

return Db
