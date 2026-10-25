local assert_helpers = {}

function assert_helpers.equal(actual, expected)
    if actual ~= expected then
        error("expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

return assert_helpers
