-- A fake Event global. Each event keeps its subscribers by name, and
-- fire calls every one of them.
local fake_event = {}

local function new_event()
    local event = { subscribers = {} }
    function event.Subscribe(name, callback) event.subscribers[name] = callback end
    function event.Unsubscribe(name) event.subscribers[name] = nil end
    function event.fire(payload)
        for _, callback in pairs(event.subscribers) do
            callback(payload)
        end
    end
    return event
end

-- Installs the fake Event and ChatType globals.
function fake_event.install()
    Event = {
        ChatMessage = new_event(),
        ContentLayerReady = new_event(),
    }
    ChatType = { GENERAL = "GENERAL", OTHER = "OTHER" }
end

return fake_event
