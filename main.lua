ExecuteConsoleCommand("ppr Rich-Death")
ExecuteConsoleCommand("ppe Rich-Death chatAccess")

local content_view = require("src/interface/content_view")
local death_cost_listener = require("src/tracker/death_cost_listener")
local deaths_riches =  require("src/ui/deaths_riches")
local event_logger = require("src/debug/event_logger") -- DEBUG

content_view.start()
death_cost_listener.start()
deaths_riches.start()
event_logger.start() -- DEBUG

function PluginShutdown()
    content_view.stop()
    death_cost_listener.stop()
    deaths_riches.stop()
    event_logger.stop() -- DEBUG
end