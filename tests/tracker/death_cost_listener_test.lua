local death_cost_listener = require("src/tracker/death_cost_listener")
local db = require("src/database/db")
local assert_helpers = require("tests/helpers/assert")
local fake_event = require("tests/helpers/fake_event")
local fake_persistent_db = require("tests/helpers/fake_persistent_db")

local function start()
    fake_persistent_db.install()
    fake_event.install()
    death_cost_listener.start()
end

local function chat(message, chat_type)
    Event.ChatMessage.fire({ chatType = chat_type or ChatType.GENERAL, chatMessage = message })
end

local tests = {}

function tests.adds_the_cost_paid_to_death()
    start()

    chat("You pay 800,000 coins and retrieve your items.")

    assert_helpers.equal(db.get_death_cost(), 800000)
end

function tests.reads_costs_without_separators()
    start()

    chat("You pay 500 coins and retrieve your items.")

    assert_helpers.equal(db.get_death_cost(), 500)
end

function tests.reads_a_lower_case_you()
    start()

    chat("you pay 1,250,000 coins and retrieve your items.")

    assert_helpers.equal(db.get_death_cost(), 1250000)
end

function tests.adds_up_each_death()
    start()

    chat("You pay 800,000 coins and retrieve your items.")
    chat("You pay 200,000 coins and retrieve your items.")

    assert_helpers.equal(db.get_death_cost(), 1000000)
end

function tests.ignores_other_messages()
    start()

    chat("You pay 800,000 coins for the item.")
    chat("Welcome to RuneScape.")

    assert_helpers.equal(db.get_death_cost(), 0)
end

function tests.ignores_other_chat_types()
    start()

    chat("You pay 800,000 coins and retrieve your items.", ChatType.OTHER)

    assert_helpers.equal(db.get_death_cost(), 0)
end

function tests.stops_counting_once_stopped()
    start()

    death_cost_listener.stop()
    chat("You pay 800,000 coins and retrieve your items.")

    assert_helpers.equal(db.get_death_cost(), 0)
end

return tests
