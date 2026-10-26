local db = require("src/database/db")
local deaths_riches = require("src/world/deaths_riches")
local office_walls = require("src/world/office_walls")
local content_view = {}
local text
local view
local tooltip_owner

local subscription_name = "rich-death-content"

local billion = 1000000000
local million = 1000000
local thousand = 1000

-- 1234567 -> "1,234,567 gp"
-- Commas go every 3 digits counting from the right, so the digits are
-- reversed, a comma is added after every 3, and then they're reversed back.
-- That can leave a comma at the very front (",123"), which is removed.
---@param gp Integer
---@return string
local function format_gp(gp)
    local digits = tostring(math.floor(gp))
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (grouped:gsub("^,", "")) .. " gp"
end

-- Shortens the gp number the same way RuneScape's stack text does. The game
-- rounds down and switches unit only once the number reaches 10 of the next
-- one, E.G:
-- 99 999 => 99,999 gp
-- 100 000 => 100K
-- 9 999 999 => 9999K
-- 10 000 000 => 10M
-- 9 999 999 999 => 9999M
-- 10 000 000 000 => 10B
---@param gp Integer
---@return string
local function format_gp_short(gp)
    if gp >= 10 * billion then
        return math.floor(gp / billion) .. "B"
    elseif gp >= 10 * million then
        return math.floor(gp / million) .. "M"
    elseif gp >= 100 * thousand then
        return math.floor(gp / thousand) .. "K"
    end
    return format_gp(gp)
end

---@param deathCost Integer
function getTooltip(deathCost)
    local tooltip = deathCost >= 100 * thousand and format_gp(deathCost) or nil
    return tooltip
end

function content_view.start()
    Event.ContentLayerReady.Subscribe(subscription_name, function (event)
        -- This runs every time the page is opened, so throw away the old one first.
        if view then view:Destroy() end

        local parent = event.component
        view = prettyui.SimpleView.new(parent, {
            width = parent.width,
            height = parent.height,
            scrollable = true
        })
        tooltip_owner = {}

        view:AddTitle("Rich Death")

        local deathCost = db.get_death_cost()

        text = view:AddText("Total death cost: " .. format_gp_short(deathCost))
        local tooltip = getTooltip(deathCost)

        prettyui.Tooltip.bind(tooltip_owner, text, view.content, tooltip)

        view:AddCheckboxButton({
            {
                text = "Render Death's riches",
                value = "renderDeathRiches",
                selected = db.get_render_deaths_riches(),
                tooltip = nil
            }
        },
            {
                onChange = function (_, _, _, selected)
                    db.set_render_deaths_riches(selected)
                    if selected then
                        deaths_riches.start()
                    else
                        deaths_riches.stop()
                    end
                end
            })

        view:AddCheckboxButton({
            {
                text = "Show wall outlines",
                value = "showOfficeWalls",
                selected = db.get_show_office_walls(),
                tooltip = "Draws the walls Death's riches hide behind, to check where they are"
            }
        },
            {
                onChange = function (_, _, _, selected)
                    db.set_show_office_walls(selected)
                    office_walls.show = selected
                end
            })
    end)
end

-- Shows the latest cost if the page has been opened.
function content_view.refresh()
    if text then
        local deathCost = db.get_death_cost()
        local tooltip = getTooltip(deathCost)
        text.content = "Total death cost: " .. format_gp_short(deathCost)
        prettyui.Tooltip.set(tooltip_owner, tooltip)
    end
end

function content_view.stop()
    Event.ContentLayerReady.Unsubscribe(subscription_name)
    if view then
        view:Destroy()
        view = nil
        text = nil
        tooltip_owner = {}
    end
end

return content_view
