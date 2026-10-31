local account_storage = require("src/database/account_storage")
local assert_helpers = require("tests/helpers/assert")

local tests = {}

-- Fakes the game globals account_storage reads, and returns the saved values,
-- the account to change, and the event handlers it subscribed.
local function install()
    local saved = {}
    local function get(_, key)
        return saved[key]
    end
    local function set(_, key, value)
        saved[key] = value
    end
    PersistentDB = { Get = get, Set = set, GetBool = get, SetBool = set, GetInt = get, SetInt = set }
    local account = { logged_in = false, granted = false, tracking_id = nil, name = nil }
    Player = {
        IsAvailable = function() return account.logged_in end,
        GetTrackingID = function() return account.tracking_id end,
        GetEntity = function()
            return account.name and { isValid = true, displayName = account.name } or nil
        end,
    }
    PluginPermissions = { trackingAccess = "trackingAccess" }
    Plugin = { HasPermission = function() return account.granted end }
    local handlers = {}
    local function event(name)
        return {
            Subscribe = function(_, handler) handlers[name] = handler end,
            Unsubscribe = function() handlers[name] = nil end,
        }
    end
    Event = { ServerLogic = event("tick"), GameStateChanged = event("state") }
    account_storage.stop()
    account_storage.start()
    return saved, account, handlers
end

function tests.reads_nothing_and_saves_nothing_before_logging_in()
    local saved = install()

    account_storage.set_int("casts", 3)

    assert_helpers.equal(account_storage.has_account(), false)
    assert_helpers.equal(account_storage.get_int("casts"), nil)
    assert_helpers.equal(next(saved), nil)
end

function tests.saves_under_the_display_name_without_the_tracking_permission()
    local saved, account, handlers = install()
    account.logged_in, account.name = true, "Zezima"
    handlers.tick()

    account_storage.set_int("casts", 3)
    account_storage.set_bool("ironBtw", false)

    assert_helpers.equal(saved["name.Zezima.casts"], 3)
    assert_helpers.equal(account_storage.get_int("casts"), 3)
    assert_helpers.equal(account_storage.get_bool("ironBtw"), false)
end

function tests.saves_under_the_tracking_id_once_it_arrives()
    local saved, account, handlers = install()
    account.logged_in, account.name, account.granted = true, "Zezima", true
    handlers.tick()
    assert_helpers.equal(account_storage.has_account(), false)

    account.tracking_id = 1234567890123
    handlers.tick()
    account_storage.set_int("casts", 3)

    assert_helpers.equal(saved["id.1234567890123.casts"], 3)
end

function tests.keeps_accounts_apart()
    local _, account, handlers = install()
    account.logged_in, account.name = true, "Zezima"
    handlers.tick()
    account_storage.set_int("casts", 3)

    account.name = "Woox"
    handlers.tick()

    assert_helpers.equal(account_storage.get_int("casts"), nil)
end

function tests.tells_listeners_when_the_account_changes()
    local _, account, handlers = install()
    local changes = 0
    account_storage.on_change(function() changes = changes + 1 end)

    account.logged_in, account.name = true, "Zezima"
    handlers.tick()
    handlers.tick()
    account.logged_in = false
    handlers.state()

    assert_helpers.equal(changes, 2)
    assert_helpers.equal(account_storage.has_account(), false)
end

return tests
