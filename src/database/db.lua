local Db = {}

local render_deaths_riches_key = "renderDeathRiches"
local death_cost_key = "deathCost"

-- Check if the player wants to render death's riches. If they haven't toggled the setting we default to true
function Db.render_deaths_riches()
    local saved = PersistentDB:GetBool(render_deaths_riches_key)
    if saved == nil then
        return true
    end
    return saved
end

function Db.get_death_cost()
    local saved = PersistentDB:GetInt(death_cost_key)
    if saved == nil then
        return 0
    end
    return saved
end

function Db.add_death_cost(cost)
    local currentCost = Db.get_death_cost()
    PersistentDB:SetInt(death_cost_key, currentCost + cost)
end

function Db.set_render_deaths_riches(selected)
    PersistentDB:SetBool(render_deaths_riches_key, selected)
end

return Db