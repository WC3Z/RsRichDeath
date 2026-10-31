-- A fake PersistentDB global that keeps saved values in a plain table, with a
-- test account logged in, as everything is saved per account (see
-- account_storage.lua).
local account_storage = require("src/database/account_storage")

local fake_persistent_db = {}

-- What account_storage puts in front of every key for the test account.
fake_persistent_db.account_prefix = "name.Tester."

-- Fakes for the game globals account_storage reads to find the account.
local function install_logged_in_account()
    Player = {
        IsAvailable = function() return true end,
        GetTrackingID = function() return nil end,
        GetEntity = function() return { isValid = true, displayName = "Tester" } end,
    }
    PluginPermissions = { trackingAccess = "trackingAccess" }
    Plugin = { HasPermission = function() return false end }
    local function no_event()
        return { Subscribe = function() end, Unsubscribe = function() end }
    end
    Event = Event or {}
    Event.ServerLogic = Event.ServerLogic or no_event()
    Event.GameStateChanged = Event.GameStateChanged or no_event()
end

-- Installs the fake and returns the test account's saved values, by key
-- without the account in front, so tests can read and write them as the
-- plugin's code names them. Everything saved, account and all, is in `raw`.
---@return table stored
---@return table raw
function fake_persistent_db.install()
    local raw = {}
    local function get(_, key)
        return raw[key]
    end
    local function set(_, key, value)
        raw[key] = value
    end
    PersistentDB = {
        Get = get, Set = set,
        GetBool = get, SetBool = set,
        GetInt = get, SetInt = set,
        GetFloat = get, SetFloat = set,
        GetString = get, SetString = set,
    }
    install_logged_in_account()
    account_storage.stop()
    account_storage.start()
    local stored = setmetatable({}, {
        __index = function(_, key)
            return raw[fake_persistent_db.account_prefix .. key]
        end,
        __newindex = function(_, key, value)
            raw[fake_persistent_db.account_prefix .. key] = value
        end,
    })
    return stored, raw
end

return fake_persistent_db
