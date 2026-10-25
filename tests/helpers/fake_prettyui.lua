-- A fake prettyui global with just enough of SimpleView for the content view tests.
local fake_prettyui = {}

-- Like prettyui's AddText, takes either the text or { text = ..., tooltip = ... }.
-- The real one returns the game's ui.Text, which has no SetTooltip, so neither does this.
local function new_text(value)
    if type(value) == "table" then
        return { content = value.text, tooltip = value.tooltip }
    end
    return { content = value }
end

local SimpleView = {}
SimpleView.__index = SimpleView

function SimpleView:AddTitle(title)
    self.title = title
end

function SimpleView:AddText(value)
    local text = new_text(value)
    table.insert(self.texts, text)
    return text
end

-- Checkboxes are kept by value.
function SimpleView:AddCheckboxButton(buttons, options)
    self.checkboxes[buttons[1].value] = {
        text = buttons[1].text,
        selected = buttons[1].selected,
        on_change = options.onChange,
    }
end

function SimpleView:Destroy()
    self.destroyed = true
end

-- Installs the fake and returns a list that every created view is added to.
function fake_prettyui.install()
    local created = {}
    prettyui = {
        SimpleView = {
            new = function(parent, options)
                local view = setmetatable({
                    parent = parent, options = options, texts = {}, checkboxes = {},
                    content = { kind = "content" },
                }, SimpleView)
                table.insert(created, view)
                return view
            end,
        },
        -- Keeps the tooltip on the text it is bound to, as text.tooltip. The real
        -- tooltip is drawn in its parent, which has to be a game widget such as
        -- view.content, not a prettyui view.
        Tooltip = {
            bind = function(owner, target, parent, value)
                if getmetatable(parent) == SimpleView then
                    error("Tooltip.bind needs a game widget as parent (e.g. view.content), got a prettyui view", 2)
                end
                owner.fake_tooltip_target = target
                target.tooltip = value
            end,
            set = function(owner, value)
                owner.fake_tooltip_target.tooltip = value
                return true
            end,
        },
    }
    return created
end

return fake_prettyui
