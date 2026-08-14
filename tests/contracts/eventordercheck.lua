-- Broadcast recipients are snapshotted in tree order. Facts emitted by their
-- transitions join the FIFO tail, proving breadth-first delivery.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local Ping = Frog.event("proof.ping", function(event)
    assert(type(event.id) == "string", "ping id must be a string")
end)
local Pong = Frog.event("proof.pong", function(event)
    assert(type(event.listener) == "string", "pong listener must be a string")
end)

-- Records ordered event deliveries and optionally emits a nested fact.
local Listener = Frog.actor("OrderedListener", {
    initial = "idle",
    actions = {},
    reactions = {
        Frog.on(Ping) {
            transition = Frog.go("heard", {
                emit = Pong { listener = Frog.prop("id") },
            }),
        },
    },
    render = function(props, state)
        return Frog.Text {
            testId = "listener-" .. props.id,
            props.id .. ":" .. state,
        }
    end,
})
local ListenerA = Listener:address("ordered-a")
local ListenerB = Listener:address("ordered-b")

-- Observes the nested fact so breadth-first event order is externally visible.
local Watcher = Frog.actor("OrderedWatcher", {
    initial = function() return { order = {} } end,
    actions = {},
    reactions = {
        Frog.on(Pong) {
            transition = function(state, event)
                local order = {}
                for index, value in ipairs(state.order) do order[index] = value end
                order[#order + 1] = event.listener
                return { order = order }
            end,
        },
    },
    render = function(_, state)
        return Frog.Text {
            testId = "delivery-order",
            table.concat(state.order, ","),
        }
    end,
})
local WatcherAddress = Watcher:address("ordered-watcher")

function check.run()
    local reversed = false
    -- Reorders keyed listener instances without changing their semantic owners.
    local Root = Frog.component("OrderedEventStory", function()
        local listeners = reversed and {
            { key = "b", address = ListenerB, id = "b" },
            { key = "a", address = ListenerA, id = "a" },
        } or {
            { key = "a", address = ListenerA, id = "a" },
            { key = "b", address = ListenerB, id = "b" },
        }
        return Frog.Column {
            Frog.Button {
                testId = "publish-ping",
                onPress = function() Frog.emit(Ping { id = "one" }) end,
                Frog.Text "Publish",
            },
            Frog.each(listeners, function(listener)
                return Listener {
                    key = listener.key,
                    address = listener.address,
                    id = listener.id,
                }
            end),
            Watcher { address = WatcherAddress },
        }
    end)
    local host = support.host { width = 540, height = 960 }
    host:mount(Root {})
    -- Reorder the keyed listeners after mount. Delivery must follow the new
    -- committed tree, not the actors' original registration order.
    reversed = true
    host:render(Root {})
    local button = assert(support.find(host:tree(), "publish-ping"))
    local x, y = support.center(button)
    host:pointerDown(x, y, "mouse", 1)
    host:pointerUp(x, y, "mouse", 1)

    assert(assert(support.find(host:tree(), "delivery-order")).props.text
            == "b,a", "broadcast reactions did not run in tree order")
    local trace = host:messageTrace()
    assert(#trace == 3, "breadth-first proof expected exactly three facts")
    assert(trace[1].token == "proof.ping"
            and trace[2].token == "proof.pong"
            and trace[3].token == "proof.pong",
        "reaction facts were delivered recursively instead of breadth-first")
    assert(trace[1].recipients[1] == "ordered-b"
            and trace[1].recipients[2] == "ordered-a",
        "broadcast recipient snapshot ignored committed tree order")
    assert(trace[2].payload == nil and trace[3].payload == nil
            and trace[2].transitions[1].accepted
            and trace[2].transitions[1].changed
            and trace[3].transitions[1].accepted
            and trace[3].transitions[1].changed,
        "nested facts did not use the compact accepted/changed trace")
    assert(trace[2].transitions[1].from == nil
            and trace[2].transitions[1].to == nil,
        "compact event trace retained actor state")
    assert(not trace[1].reconciled and not trace[2].reconciled
            and trace[3].reconciled,
        "event batch reconciled before its FIFO queue drained")
    host:unmount()
end

return check
