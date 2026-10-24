ExecuteConsoleCommand("ppr Rich-Death")
ExecuteConsoleCommand("ppe Rich-Death chatAccess")

local content_view = require("src/interface/content_view")
local death_cost_listener = require("src/tracker/death_cost_listener")

content_view.start()

function PluginShutdown()
    content_view.stop()
    death_cost_listener.stop()
end

death_cost_listener.start()
