-- Unit tests for factorio-agent-api control.lua

package.path = package.path .. ";./?.lua"
local mocks = require("tests.mocks")

-- Simple test framework
local tests = {
    passed = 0,
    failed = 0,
    errors = {}
}

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "Assertion failed", tostring(expected), tostring(actual)))
    end
end

local function assert_true(value, msg)
    if not value then
        error(msg or "Expected true, got false")
    end
end

local function assert_false(value, msg)
    if value then
        error(msg or "Expected false, got true")
    end
end

local function assert_contains(str, substr, msg)
    if not string.find(str, substr, 1, true) then
        error(msg or string.format("String does not contain '%s'", substr))
    end
end

local function assert_not_nil(value, msg)
    if value == nil then
        error(msg or "Expected non-nil value")
    end
end

local current_env = nil

local function run_test(name, fn)
    io.write(string.format("  %-50s ", name))

    -- Setup mocks first (sets globals)
    local env = mocks.setup()
    current_env = env

    -- Load control.lua after setting up mocks
    local chunk, err = loadfile("control.lua")
    if not chunk then
        tests.failed = tests.failed + 1
        table.insert(tests.errors, {name = name, error = "Failed to load control.lua: " .. tostring(err)})
        print("FAIL (load)")
        mocks.teardown()
        return
    end

    local ok, load_err = pcall(chunk)
    if not ok then
        tests.failed = tests.failed + 1
        table.insert(tests.errors, {name = name, error = "Failed to execute control.lua: " .. tostring(load_err)})
        print("FAIL (exec)")
        mocks.teardown()
        return
    end

    -- Run the test
    local success, test_err = pcall(fn, env)
    if success then
        tests.passed = tests.passed + 1
        print("PASS")
    else
        tests.failed = tests.failed + 1
        table.insert(tests.errors, {name = name, error = test_err})
        print("FAIL")
    end

    mocks.teardown()
    current_env = nil
end

-- Test suites
print("\n=== Factorio Agent API Unit Tests ===\n")

print("Command Registration:")
run_test("agent command is registered", function(env)
    local cmds = env.get_registered_commands()
    assert_not_nil(cmds["agent"], "agent command should be registered")
end)

run_test("agent command has help text", function(env)
    local cmds = env.get_registered_commands()
    assert_not_nil(cmds["agent"].help, "agent command should have help text")
end)

print("\nEvent Handlers:")
run_test("on_tick handler is registered", function(env)
    local handlers = env.get_handlers()
    assert_not_nil(handlers[defines.events.on_tick], "on_tick handler should be registered")
end)

run_test("on_player_mined_entity handler is registered", function(env)
    local handlers = env.get_handlers()
    assert_not_nil(handlers[defines.events.on_player_mined_entity], "mining handler should be registered")
end)

run_test("on_research_finished handler is registered", function(env)
    local handlers = env.get_handlers()
    assert_not_nil(handlers[defines.events.on_research_finished], "research handler should be registered")
end)

run_test("on_player_died handler is registered", function(env)
    local handlers = env.get_handlers()
    assert_not_nil(handlers[defines.events.on_player_died], "player died handler should be registered")
end)

print("\nHelp Command:")
run_test("help command executes without error", function(env)
    env.call_command("agent", "help")
end)

run_test("help command writes response file", function(env)
    env.call_command("agent", "help")
    local files = env.get_files()
    assert_not_nil(files["agent-response.txt"], "Response file should be written")
end)

run_test("help command returns command list", function(env)
    env.call_command("agent", "help")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "commands", "Response should contain commands")
    assert_contains(response, "walk", "Response should list walk command")
    assert_contains(response, "build", "Response should list build command")
end)

print("\nWalk Command:")
run_test("walk north sets walking state", function(env)
    env.call_command("agent", "walk direction=north")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Walk command should succeed")
    assert_contains(response, "Walking", "Response should indicate walking")
end)

run_test("walk with all directions", function(env)
    local directions = {"north", "south", "east", "west", "northeast", "northwest", "southeast", "southwest"}
    for _, dir in ipairs(directions) do
        mocks.setup()
        loadfile("control.lua")()
        env = current_env
        env.call_command("agent", "walk direction=" .. dir)
        local files = env.get_files()
        local response = files["agent-response.txt"]
        assert_contains(response, "ok", "Walk " .. dir .. " should succeed")
    end
end)

run_test("walk stop command", function(env)
    env.call_command("agent", "walk direction=stop")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Stop should succeed")
    assert_contains(response, "Stopped", "Response should indicate stopped")
end)

run_test("walk invalid direction returns error", function(env)
    env.call_command("agent", "walk direction=invalid")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "error", "Invalid direction should return error")
end)

print("\nStop Command:")
run_test("stop command halts all actions", function(env)
    env.call_command("agent", "stop")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Stop should succeed")
    assert_contains(response, "Stopped", "Response should indicate stopped")
end)

print("\nStatus Command:")
run_test("status command returns player info", function(env)
    env.call_command("agent", "status")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Status should succeed")
    assert_contains(response, "position", "Response should contain position")
end)

run_test("status command includes health", function(env)
    env.call_command("agent", "status")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "health", "Response should contain health")
end)

print("\nInventory Command:")
run_test("inventory command returns contents", function(env)
    env.call_command("agent", "inventory")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Inventory should succeed")
    assert_contains(response, "contents", "Response should contain contents")
end)

print("\nCraft Command:")
run_test("craft command queues crafting", function(env)
    env.call_command("agent", "craft name=iron-gear-wheel count=5")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Craft should succeed")
    assert_contains(response, "Crafting", "Response should indicate crafting")
end)

run_test("craft command with default count", function(env)
    env.call_command("agent", "craft name=iron-gear-wheel")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Craft with default count should succeed")
end)

run_test("craft command without name fails", function(env)
    env.call_command("agent", "craft count=5")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "error", "Craft without name should fail")
end)

print("\nResearch Command:")
run_test("research command adds to queue", function(env)
    env.call_command("agent", "research name=automation")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Research should succeed")
end)

run_test("research unknown tech fails", function(env)
    env.call_command("agent", "research name=unknown_tech")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "error", "Unknown tech should fail")
end)

run_test("current_research command", function(env)
    env.call_command("agent", "current_research")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Current research should succeed")
end)

print("\nRecipes Command:")
run_test("recipes command lists recipes", function(env)
    env.call_command("agent", "recipes")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Recipes should succeed")
    assert_contains(response, "recipes", "Response should contain recipes")
end)

run_test("recipes command with filter", function(env)
    env.call_command("agent", "recipes filter=iron")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Filtered recipes should succeed")
end)

print("\nTechnologies Command:")
run_test("technologies command lists techs", function(env)
    env.call_command("agent", "technologies")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Technologies should succeed")
    assert_contains(response, "technologies", "Response should contain technologies")
end)

print("\nChat Command:")
run_test("chat command prints message", function(env)
    env.call_command("agent", "chat message=Hello")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Chat should succeed")
end)

run_test("chat command without message fails", function(env)
    env.call_command("agent", "chat")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "error", "Chat without message should fail")
end)

print("\nScan Command:")
run_test("scan command works with empty area", function(env)
    env.call_command("agent", "scan radius=10")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "ok", "Scan should succeed")
    assert_contains(response, "entities", "Response should contain entities")
end)

print("\nMine Command:")
run_test("mine command without coordinates fails", function(env)
    env.call_command("agent", "mine")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "error", "Mine without coords should fail")
end)

run_test("mine command at empty location", function(env)
    env.call_command("agent", "mine x=100 y=100")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    -- Should fail because nothing to mine
    assert_contains(response, "error", "Mining empty location should fail")
end)

print("\nBuild Command:")
run_test("build command without name fails", function(env)
    env.call_command("agent", "build x=10 y=10")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "error", "Build without name should fail")
end)

run_test("build command without coordinates fails", function(env)
    env.call_command("agent", "build name=transport-belt")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "error", "Build without coords should fail")
end)

print("\nRotate Command:")
run_test("rotate command without coordinates fails", function(env)
    env.call_command("agent", "rotate")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "error", "Rotate without coords should fail")
end)

print("\nDeconstruct Command:")
run_test("deconstruct command without coordinates fails", function(env)
    env.call_command("agent", "deconstruct")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "error", "Deconstruct without coords should fail")
end)

print("\nUnknown Command:")
run_test("unknown command returns error", function(env)
    env.call_command("agent", "nonexistent_command arg=value")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, "error", "Unknown command should return error")
    assert_contains(response, "Unknown command", "Should say unknown command")
end)

print("\nEmpty/Invalid Input:")
run_test("empty parameter shows usage (no crash)", function(env)
    -- This should not crash, just print usage
    env.call_command("agent", "")
end)

run_test("nil parameter shows usage (no crash)", function(env)
    env.call_command("agent", nil)
end)

print("\nOn-Tick Handler:")
run_test("on_tick handler runs without error", function(env)
    local handlers = env.get_handlers()
    local handler = handlers[defines.events.on_tick]
    assert_not_nil(handler, "on_tick handler should exist")
    -- Run a few ticks
    for i = 1, 10 do
        handler({tick = i})
    end
end)

run_test("on_tick writes state after 60 ticks", function(env)
    local handlers = env.get_handlers()
    local handler = handlers[defines.events.on_tick]
    -- Run 60 ticks
    for i = 1, 60 do
        handler({tick = i})
    end
    local files = env.get_files()
    assert_not_nil(files["agent-gamestate.json"], "Game state should be written after 60 ticks")
end)

print("\nResponse Format:")
run_test("response contains id field", function(env)
    env.call_command("agent", "help")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, '"id":', "Response should contain id field")
end)

run_test("response contains status field", function(env)
    env.call_command("agent", "help")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, '"status":', "Response should contain status field")
end)

run_test("response contains tick field", function(env)
    env.call_command("agent", "help")
    local files = env.get_files()
    local response = files["agent-response.txt"]
    assert_contains(response, '"tick":', "Response should contain tick field")
end)

-- Print summary
print("\n=== Test Summary ===")
print(string.format("Passed: %d", tests.passed))
print(string.format("Failed: %d", tests.failed))
print(string.format("Total:  %d", tests.passed + tests.failed))

if #tests.errors > 0 then
    print("\nFailed Tests:")
    for _, err in ipairs(tests.errors) do
        print(string.format("  %s:", err.name))
        print(string.format("    %s", err.error))
    end
end

print("")

-- Exit with appropriate code
if tests.failed > 0 then
    os.exit(1)
else
    print("All tests passed!")
    os.exit(0)
end
