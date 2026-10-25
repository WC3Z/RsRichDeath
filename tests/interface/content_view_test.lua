local content_view = require("src/interface/content_view")
local deaths_riches = require("src/world/deaths_riches")
local db = require("src/database/db")
local assert_helpers = require("tests/helpers/assert")
local fake_event = require("tests/helpers/fake_event")
local fake_game = require("tests/helpers/fake_game")
local fake_persistent_db = require("tests/helpers/fake_persistent_db")
local fake_prettyui = require("tests/helpers/fake_prettyui")

-- Starts the content view on fresh fakes, with the given death cost saved.
---@return table created Every view the content view has made
local function start(death_cost)
    content_view.stop()
    deaths_riches.stop()
    fake_persistent_db.install()
    fake_event.install()
    fake_game.install()
    local created = fake_prettyui.install()
    if death_cost then
        db.add_death_cost(death_cost)
    end
    content_view.start()
    return created
end

local function open_page()
    Event.ContentLayerReady.fire({ component = { width = 300, height = 400 } })
end

-- The total shown on the newest page.
local function shown_total(created)
    return created[#created].texts[1].content
end

local tests = {}

function tests.does_not_make_the_page_before_it_is_opened()
    local created = start()

    assert_helpers.equal(#created, 0)
end

function tests.shows_the_title_and_total()
    local created = start(4530)

    open_page()

    assert_helpers.equal(created[1].title, "Rich Death")
    assert_helpers.equal(shown_total(created), "Total death cost: 4,530 gp")
end

function tests.fills_the_page_it_is_opened_in()
    local created = start()

    open_page()

    assert_helpers.equal(created[1].options.width, 300)
    assert_helpers.equal(created[1].options.height, 400)
end

function tests.shows_the_total_in_full_below_100k()
    local created = start(99999)

    open_page()

    assert_helpers.equal(shown_total(created), "Total death cost: 99,999 gp")
end

function tests.shortens_the_total_like_the_game()
    local cases = {
        { 100000, "100K" },
        { 9999999, "9999K" },
        { 10000000, "10M" },
        { 2147483647, "2147M" },
        { 9999999999, "9999M" },
        { 10000000000, "10B" },
        { 12345678901, "12B" },
    }
    for _, case in ipairs(cases) do
        local created = start(case[1])

        open_page()

        assert_helpers.equal(shown_total(created), "Total death cost: " .. case[2])
    end
end

function tests.shows_the_full_total_in_a_tooltip_when_shortened()
    local created = start(1234567)

    open_page()

    assert_helpers.equal(created[1].texts[1].tooltip, "1,234,567 gp")
end

function tests.has_no_tooltip_when_the_total_is_shown_in_full()
    local created = start(4530)

    open_page()

    assert_helpers.equal(created[1].texts[1].tooltip, nil)
end

function tests.refresh_shows_the_new_total()
    local created = start(1000)
    open_page()

    db.add_death_cost(500)
    content_view.refresh()

    assert_helpers.equal(shown_total(created), "Total death cost: 1,500 gp")
end

function tests.refresh_does_nothing_before_the_page_is_opened()
    start()

    content_view.refresh()
end

function tests.reopening_the_page_replaces_the_old_one()
    local created = start()
    open_page()

    open_page()

    assert_helpers.equal(#created, 2)
    assert_helpers.equal(created[1].destroyed, true)
    assert_helpers.equal(created[2].destroyed, nil)
end

function tests.checkbox_shows_and_saves_the_render_setting()
    local created = start()
    open_page()
    local checkbox = created[1].checkboxes.renderDeathRiches

    assert_helpers.equal(checkbox.selected, true)
    checkbox.on_change(nil, nil, nil, false)

    assert_helpers.equal(db.get_render_deaths_riches(), false)
end

function tests.unticking_the_checkbox_stops_the_riches()
    local created = start()
    deaths_riches.start()
    open_page()

    created[1].checkboxes.renderDeathRiches.on_change(nil, nil, nil, false)

    assert_helpers.equal(next(Event.Draw.subscribers), nil)
end

function tests.ticking_the_checkbox_starts_the_riches()
    local created = start()
    db.set_render_deaths_riches(false)
    open_page()

    created[1].checkboxes.renderDeathRiches.on_change(nil, nil, nil, true)

    assert_helpers.equal(db.get_render_deaths_riches(), true)
    assert_helpers.equal(type(Event.Draw.subscribers["deaths-riches"]), "function")
end

function tests.stop_removes_the_page_and_stops_listening()
    local created = start()
    open_page()

    content_view.stop()
    open_page()

    assert_helpers.equal(created[1].destroyed, true)
    assert_helpers.equal(#created, 1)
end

return tests
