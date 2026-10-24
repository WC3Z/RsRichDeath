local db = require("src/database/db")
local death_cost_listener = {}

local var_subscription_name = "death-cost-paid"

function death_cost_listener.start()
    -- I have yet to find a more elegant way of figuring out when you paid death than to read the chat logs
    Event.ChatMessage.Subscribe(var_subscription_name, function (chatMessageEvent)
        if chatMessageEvent.chatType == ChatType.GENERAL then
            local message = chatMessageEvent.chatMessage
            -- Check if the message contains "you pay X coins and retrieve your items
            local amount = message:match("[Yy]ou pay ([%d,]+) coins and retrieve your items")

            if amount then
                -- cost will contain "," at some point, E.G 800,000
                local cost = tonumber((amount:gsub(",", "")))
                db.add_death_cost(cost)
            end
        end
    end)
end

function death_cost_listener.stop()
    Event.ChatMessage.Unsubscribe(var_subscription_name)
end

return death_cost_listener
