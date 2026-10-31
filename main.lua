ExecuteConsoleCommand("ppr Rich-Death")
ExecuteConsoleCommand("ppe Rich-Death chatAccess")
ExecuteConsoleCommand("ppe Rich-Death trackingAccess")

local account_storage = require("src/database/account_storage")
local content_view = require("src/interface/content_view")
local death_cost_listener = require("src/tracker/death_cost_listener")

account_storage.start()
content_view.start()
death_cost_listener.start()

function PluginShutdown()
    content_view.stop()
    death_cost_listener.stop()
    account_storage.stop()
end