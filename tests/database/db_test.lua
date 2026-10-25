local db = require("src/database/db")
local assert_helpers = require("tests/helpers/assert")
local fake_persistent_db = require("tests/helpers/fake_persistent_db")

local tests = {}

function tests.renders_deaths_riches_until_turned_off()
    fake_persistent_db.install()

    assert_helpers.equal(db.render_deaths_riches(), true)
end

function tests.remembers_that_deaths_riches_were_turned_off()
    fake_persistent_db.install()

    db.set_render_deaths_riches(false)

    assert_helpers.equal(db.render_deaths_riches(), false)
end

function tests.death_cost_starts_at_zero()
    fake_persistent_db.install()

    assert_helpers.equal(db.get_death_cost(), 0)
end

function tests.adds_up_death_costs()
    fake_persistent_db.install()

    db.add_death_cost(800000)
    db.add_death_cost(50000)

    assert_helpers.equal(db.get_death_cost(), 850000)
end

return tests
