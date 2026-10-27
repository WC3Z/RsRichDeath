local db = require("src/database/db")
local assert_helpers = require("tests/helpers/assert")
local fake_persistent_db = require("tests/helpers/fake_persistent_db")

local tests = {}

function tests.renders_deaths_riches_until_turned_off()
    fake_persistent_db.install()

    assert_helpers.equal(db.get_render_deaths_riches(), true)
end

function tests.remembers_that_deaths_riches_were_turned_off()
    fake_persistent_db.install()

    db.set_render_deaths_riches(false)

    assert_helpers.equal(db.get_render_deaths_riches(), false)
end

function tests.hides_the_wall_outlines_until_turned_on()
    fake_persistent_db.install()

    assert_helpers.equal(db.get_show_office_walls(), false)
end

function tests.remembers_that_the_wall_outlines_were_turned_on()
    fake_persistent_db.install()

    db.set_show_office_walls(true)

    assert_helpers.equal(db.get_show_office_walls(), true)
end

function tests.hides_in_one_strip_until_changed()
    fake_persistent_db.install()

    assert_helpers.equal(db.get_hiding_strips(), 1)
end

function tests.remembers_how_many_strips_to_hide_in()
    fake_persistent_db.install()

    db.set_hiding_strips(4)

    assert_helpers.equal(db.get_hiding_strips(), 4)
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
