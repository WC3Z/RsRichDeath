-- Run from the repository root: lua tests/run.lua
package.path = "./?.lua;" .. package.path

local test_files = {
    "tests/database/db_test",
    "tests/tracker/death_cost_listener_test",
    "tests/interface/content_view_test",
    "tests/world/deaths_riches_test",
    "tests/world/line_of_sight_test",
    "tests/world/wall_measure_test",
}

local passed, failed = 0, 0
for _, module_name in ipairs(test_files) do
    for test_name, test in pairs(require(module_name)) do
        local ok, err = pcall(test)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            print("FAIL " .. module_name .. " > " .. test_name .. "\n    " .. tostring(err))
        end
    end
end

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then
    os.exit(1)
end
