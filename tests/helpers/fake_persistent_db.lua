-- A fake PersistentDB global that keeps saved values in a plain table.
local fake_persistent_db = {}

-- Installs the fake and returns the table of saved values.
function fake_persistent_db.install()
    local stored = {}
    PersistentDB = {
        GetBool = function(_, key) return stored[key] end,
        SetBool = function(_, key, value) stored[key] = value end,
        GetInt = function(_, key) return stored[key] end,
        SetInt = function(_, key, value) stored[key] = value end,
    }
    return stored
end

return fake_persistent_db
