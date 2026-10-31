-- The game's plugin storage (PersistentDB), kept apart for each game account.
-- PersistentDB is shared by every account played on the computer, so each key
-- is saved with the account in front of it: the account's tracking id when
-- the plugin may read it ("id.123.key"), or else its display name
-- ("name.Zezima.key"). A display name changes when the player renames, so the
-- id is preferred.
--
-- Until an account is known, like on the login screen, reads give nothing
-- (so callers use their defaults) and writes are dropped. Call on_change to be
-- told when the account changes, to load its data.
local account_storage = {}

local subscription_name = "rich-death-account"

-- What goes in front of every key for the logged in account, or nil.
---@type string?
local prefix = nil
---@type fun()[]
local listeners = {}

-- The prefix for the account playing now, or nil when there's none yet. With
-- the tracking permission it waits for the id, which comes a few seconds
-- after logging in.
---@return string?
local function prefix_now()
    if not Player.IsAvailable() then
        return nil
    end
    if Plugin.HasPermission(PluginPermissions.trackingAccess) then
        local tracking_id = Player.GetTrackingID()
        return tracking_id and ("id." .. tostring(tracking_id) .. ".") or nil
    end
    local player = Player.GetEntity()
    local name = player and player.isValid and player.displayName
    if not name or name == "" then
        return nil
    end
    return "name." .. name .. "."
end

local function check_account()
    local now = prefix_now()
    if now == prefix then
        return
    end
    prefix = now
    for _, listener in ipairs(listeners) do
        listener()
    end
end

-- Whether an account is known, so its data can be read and written.
---@return boolean
function account_storage.has_account()
    return prefix ~= nil
end

-- Calls `listener` whenever the account changes: logging in, out or into
-- another account.
---@param listener fun()
function account_storage.on_change(listener)
    table.insert(listeners, listener)
end

---@param key string
---@return boolean?
function account_storage.get_bool(key)
    if not prefix then
        return nil
    end
    return PersistentDB:GetBool(prefix .. key)
end

---@param key string
---@param value boolean
function account_storage.set_bool(key, value)
    if prefix then
        PersistentDB:SetBool(prefix .. key, value)
    end
end

---@param key string
---@return integer?
function account_storage.get_int(key)
    if not prefix then
        return nil
    end
    return PersistentDB:GetInt(prefix .. key)
end

---@param key string
---@param value integer
function account_storage.set_int(key, value)
    if prefix then
        PersistentDB:SetInt(prefix .. key, value)
    end
end

---@param key string
---@return number?
function account_storage.get_float(key)
    if not prefix then
        return nil
    end
    return PersistentDB:GetFloat(prefix .. key)
end

---@param key string
---@param value number
function account_storage.set_float(key, value)
    if prefix then
        PersistentDB:SetFloat(prefix .. key, value)
    end
end

---@param key string
---@return string?
function account_storage.get_string(key)
    if not prefix then
        return nil
    end
    return PersistentDB:GetString(prefix .. key)
end

---@param key string
---@param value string
function account_storage.set_string(key, value)
    if prefix then
        PersistentDB:SetString(prefix .. key, value)
    end
end

function account_storage.start()
    -- Every game tick, as the tracking id arrives a while after logging in.
    Event.ServerLogic.Subscribe(subscription_name, check_account)
    -- Logging out stops the game ticks, so that's checked here.
    Event.GameStateChanged.Subscribe(subscription_name, check_account)
    check_account()
end

function account_storage.stop()
    Event.ServerLogic.Unsubscribe(subscription_name)
    Event.GameStateChanged.Unsubscribe(subscription_name)
    prefix = nil
    listeners = {}
end

return account_storage
