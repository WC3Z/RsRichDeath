local db = require("src/database/db")


local content_view = {}
local text
local view

local subscription_name = "rich-death-content"

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

        view:AddTitle("Rich Death")

        text = view:AddText("Total death cost: " .. db.get_death_cost())
        view:AddCheckboxButton({
            {
                text = "Render Death's riches",
                value = "renderDeathRiches",
                selected = db.render_deaths_riches(),
                tooltip = nil
            }
        },
            {
                onChange = function (_, _, _, selected)
                    db.set_render_deaths_riches(selected)
                end
            })
    end)
end

-- Shows the latest cost if the page has been opened.
function content_view.refresh()
    if text then
        text.content = "Total death cost: " .. db.get_death_cost()
    end
end

function content_view.stop()
    Event.ContentLayerReady.Unsubscribe(subscription_name)
    if view then
        view:Destroy()
        view = nil
        text = nil
    end
end

return content_view
