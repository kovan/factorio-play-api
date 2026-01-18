-- Factorio Agent API
-- Provides file-based command interface for programmatic game control

local COMMAND_FILE = "agent-commands.txt"
local STATE_FILE = "agent-gamestate.json"
local RESPONSE_FILE = "agent-response.txt"

-- State tracking
local agent_state = {
    last_command_id = 0,
    walking_direction = nil,
    mining_target = nil,
    pending_responses = {},
    tick_counter = 0
}

-- Direction mappings
local DIRECTIONS = {
    north = defines.direction.north,
    northeast = defines.direction.northeast,
    east = defines.direction.east,
    southeast = defines.direction.southeast,
    south = defines.direction.south,
    southwest = defines.direction.southwest,
    west = defines.direction.west,
    northwest = defines.direction.northwest
}

local DIRECTION_VECTORS = {
    north = {x = 0, y = -1},
    northeast = {x = 1, y = -1},
    east = {x = 1, y = 0},
    southeast = {x = 1, y = 1},
    south = {x = 0, y = 1},
    southwest = {x = -1, y = 1},
    west = {x = -1, y = 0},
    northwest = {x = -1, y = -1}
}

-- Helper: Parse JSON-like simple format (key:value pairs)
local function parse_args(arg_string)
    if not arg_string or arg_string == "" then
        return {}
    end

    local args = {}
    for pair in string.gmatch(arg_string, "([^,]+)") do
        local key, value = string.match(pair, "([^=]+)=(.+)")
        if key and value then
            key = string.gsub(key, "^%s*(.-)%s*$", "%1")
            value = string.gsub(value, "^%s*(.-)%s*$", "%1")
            -- Try to convert to number
            local num = tonumber(value)
            if num then
                args[key] = num
            elseif value == "true" then
                args[key] = true
            elseif value == "false" then
                args[key] = false
            else
                args[key] = value
            end
        end
    end
    return args
end

-- Helper: Get player (assumes single player or first player)
local function get_player()
    return game.get_player(1)
end

-- Helper: Add response
local function add_response(cmd_id, status, message, data)
    table.insert(agent_state.pending_responses, {
        id = cmd_id,
        status = status,
        message = message,
        data = data,
        tick = game.tick
    })
end

-- Helper: Serialize to JSON
local function to_json(obj, indent)
    indent = indent or 0
    local t = type(obj)

    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return obj and "true" or "false"
    elseif t == "number" then
        if obj ~= obj then return "null" end -- NaN
        if obj == math.huge or obj == -math.huge then return "null" end
        return tostring(obj)
    elseif t == "string" then
        return string.format("%q", obj)
    elseif t == "table" then
        local is_array = #obj > 0 or next(obj) == nil
        local parts = {}

        if is_array then
            for i, v in ipairs(obj) do
                table.insert(parts, to_json(v, indent + 1))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(obj) do
                if type(k) == "string" then
                    table.insert(parts, string.format("%q", k) .. ":" .. to_json(v, indent + 1))
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

-- Command handlers
local cmd_handlers = {}

-- Movement: walk direction=north|south|east|west|stop [distance=N]
function cmd_handlers.walk(args)
    local player = get_player()
    if not player or not player.character then
        return false, "No player character"
    end

    local direction = args.direction or args[1]

    if direction == "stop" then
        agent_state.walking_direction = nil
        player.walking_state = {walking = false}
        return true, "Stopped walking"
    end

    if not DIRECTIONS[direction] then
        return false, "Invalid direction: " .. tostring(direction)
    end

    agent_state.walking_direction = direction
    player.walking_state = {walking = true, direction = DIRECTIONS[direction]}
    return true, "Walking " .. direction
end

-- Stop all actions
function cmd_handlers.stop(args)
    local player = get_player()
    if player and player.character then
        agent_state.walking_direction = nil
        agent_state.mining_target = nil
        player.walking_state = {walking = false}
        player.mining_state = {mining = false}
    end
    return true, "Stopped all actions"
end

-- Mine at position: mine x=N y=N
function cmd_handlers.mine(args)
    local player = get_player()
    if not player or not player.character then
        return false, "No player character"
    end

    local x = args.x or args[1]
    local y = args.y or args[2]

    if not x or not y then
        return false, "Missing x or y coordinate"
    end

    local position = {x = tonumber(x), y = tonumber(y)}
    local entities = player.surface.find_entities_filtered{
        position = position,
        radius = 0.5
    }

    if #entities > 0 then
        local entity = entities[1]
        if player.can_reach_entity(entity) then
            player.mining_state = {mining = true, position = position}
            agent_state.mining_target = position
            return true, "Mining at " .. x .. "," .. y, {entity = entity.name}
        else
            return false, "Cannot reach entity at " .. x .. "," .. y
        end
    end

    -- Try mining resource
    local resources = player.surface.find_entities_filtered{
        position = position,
        radius = 1,
        type = "resource"
    }

    if #resources > 0 then
        player.mining_state = {mining = true, position = resources[1].position}
        agent_state.mining_target = resources[1].position
        return true, "Mining resource at " .. x .. "," .. y, {resource = resources[1].name}
    end

    return false, "Nothing to mine at " .. x .. "," .. y
end

-- Build/place entity: build name=entity-name x=N y=N [direction=north]
function cmd_handlers.build(args)
    local player = get_player()
    if not player or not player.character then
        return false, "No player character"
    end

    local name = args.name or args[1]
    local x = tonumber(args.x or args[2])
    local y = tonumber(args.y or args[3])
    local direction = DIRECTIONS[args.direction or "north"] or defines.direction.north

    if not name or not x or not y then
        return false, "Missing name, x, or y"
    end

    -- Check if player has the item
    local inventory = player.get_main_inventory()
    if not inventory then
        return false, "No inventory"
    end

    local item_name = name
    -- Some entities have different item names
    local item_count = inventory.get_item_count(item_name)

    if item_count == 0 then
        return false, "No " .. item_name .. " in inventory"
    end

    local position = {x = x, y = y}

    -- Check if we can place
    if player.surface.can_place_entity{
        name = name,
        position = position,
        direction = direction,
        force = player.force
    } then
        local entity = player.surface.create_entity{
            name = name,
            position = position,
            direction = direction,
            force = player.force,
            player = player
        }

        if entity then
            inventory.remove{name = item_name, count = 1}
            return true, "Built " .. name .. " at " .. x .. "," .. y, {entity_id = entity.unit_number}
        end
    end

    return false, "Cannot build " .. name .. " at " .. x .. "," .. y
end

-- Craft items: craft name=item-name [count=N]
function cmd_handlers.craft(args)
    local player = get_player()
    if not player then
        return false, "No player"
    end

    local name = args.name or args[1]
    local count = tonumber(args.count or args[2]) or 1

    if not name then
        return false, "Missing item name"
    end

    local crafted = player.begin_crafting{recipe = name, count = count}

    if crafted > 0 then
        return true, "Crafting " .. crafted .. "x " .. name
    else
        return false, "Cannot craft " .. name .. " (missing ingredients or recipe)"
    end
end

-- Research technology: research name=tech-name
function cmd_handlers.research(args)
    local player = get_player()
    if not player then
        return false, "No player"
    end

    local name = args.name or args[1]

    if not name then
        return false, "Missing technology name"
    end

    local tech = player.force.technologies[name]
    if not tech then
        return false, "Unknown technology: " .. name
    end

    if tech.researched then
        return false, "Technology already researched: " .. name
    end

    player.force.research_queue_enabled = true
    player.force.add_research(name)
    return true, "Added " .. name .. " to research queue"
end

-- Get inventory contents: inventory
function cmd_handlers.inventory(args)
    local player = get_player()
    if not player or not player.character then
        return false, "No player character"
    end

    local inventory = player.get_main_inventory()
    if not inventory then
        return false, "No inventory"
    end

    local contents = inventory.get_contents()
    return true, "Inventory retrieved", {contents = contents}
end

-- Pick up items: pickup x=N y=N
function cmd_handlers.pickup(args)
    local player = get_player()
    if not player or not player.character then
        return false, "No player character"
    end

    local x = tonumber(args.x or args[1])
    local y = tonumber(args.y or args[2])

    if not x or not y then
        return false, "Missing x or y coordinate"
    end

    local items = player.surface.find_entities_filtered{
        position = {x = x, y = y},
        radius = 2,
        type = "item-entity"
    }

    local picked = 0
    for _, item in pairs(items) do
        if player.can_reach_entity(item) then
            local inserted = player.insert(item.stack)
            if inserted > 0 then
                item.destroy()
                picked = picked + 1
            end
        end
    end

    return true, "Picked up " .. picked .. " items"
end

-- Put items into entity: put x=N y=N item=name [count=N]
function cmd_handlers.put(args)
    local player = get_player()
    if not player or not player.character then
        return false, "No player character"
    end

    local x = tonumber(args.x or args[1])
    local y = tonumber(args.y or args[2])
    local item = args.item or args[3]
    local count = tonumber(args.count or args[4]) or 1

    if not x or not y or not item then
        return false, "Missing x, y, or item"
    end

    local entities = player.surface.find_entities_filtered{
        position = {x = x, y = y},
        radius = 0.5
    }

    for _, entity in pairs(entities) do
        if entity.get_inventory(defines.inventory.chest) or
           entity.get_inventory(defines.inventory.furnace_source) or
           entity.get_fuel_inventory() then

            local inv = entity.get_inventory(defines.inventory.chest) or
                       entity.get_inventory(defines.inventory.furnace_source) or
                       entity.get_fuel_inventory()

            if inv then
                local player_inv = player.get_main_inventory()
                local available = player_inv.get_item_count(item)
                local to_transfer = math.min(count, available)

                if to_transfer > 0 then
                    local inserted = inv.insert{name = item, count = to_transfer}
                    if inserted > 0 then
                        player_inv.remove{name = item, count = inserted}
                        return true, "Put " .. inserted .. "x " .. item .. " into entity"
                    end
                end
            end
        end
    end

    return false, "No valid container at " .. x .. "," .. y
end

-- Take items from entity: take x=N y=N [item=name] [count=N]
function cmd_handlers.take(args)
    local player = get_player()
    if not player or not player.character then
        return false, "No player character"
    end

    local x = tonumber(args.x or args[1])
    local y = tonumber(args.y or args[2])
    local item = args.item
    local count = tonumber(args.count) or 100

    if not x or not y then
        return false, "Missing x or y coordinate"
    end

    local entities = player.surface.find_entities_filtered{
        position = {x = x, y = y},
        radius = 0.5
    }

    local taken_total = 0
    for _, entity in pairs(entities) do
        local inventories = {
            entity.get_inventory(defines.inventory.chest),
            entity.get_inventory(defines.inventory.furnace_result),
            entity.get_output_inventory and entity.get_output_inventory()
        }

        for _, inv in pairs(inventories) do
            if inv then
                local contents = inv.get_contents()
                for item_name, item_count in pairs(contents) do
                    if not item or item_name == item then
                        local to_take = math.min(item_count, count - taken_total)
                        local inserted = player.insert{name = item_name, count = to_take}
                        if inserted > 0 then
                            inv.remove{name = item_name, count = inserted}
                            taken_total = taken_total + inserted
                        end
                    end
                end
            end
        end
    end

    return true, "Took " .. taken_total .. " items"
end

-- Rotate entity: rotate x=N y=N [reverse=true]
function cmd_handlers.rotate(args)
    local player = get_player()
    if not player then
        return false, "No player"
    end

    local x = tonumber(args.x or args[1])
    local y = tonumber(args.y or args[2])
    local reverse = args.reverse == true or args.reverse == "true"

    if not x or not y then
        return false, "Missing x or y coordinate"
    end

    local entities = player.surface.find_entities_filtered{
        position = {x = x, y = y},
        radius = 0.5
    }

    for _, entity in pairs(entities) do
        if entity.rotatable then
            if reverse then
                entity.rotate{reverse = true}
            else
                entity.rotate()
            end
            return true, "Rotated " .. entity.name
        end
    end

    return false, "No rotatable entity at " .. x .. "," .. y
end

-- Deconstruct/remove entity: deconstruct x=N y=N
function cmd_handlers.deconstruct(args)
    local player = get_player()
    if not player or not player.character then
        return false, "No player character"
    end

    local x = tonumber(args.x or args[1])
    local y = tonumber(args.y or args[2])

    if not x or not y then
        return false, "Missing x or y coordinate"
    end

    local entities = player.surface.find_entities_filtered{
        position = {x = x, y = y},
        radius = 0.5,
        force = player.force
    }

    for _, entity in pairs(entities) do
        if entity.name ~= "character" then
            entity.order_deconstruction(player.force, player)
            return true, "Marked " .. entity.name .. " for deconstruction"
        end
    end

    return false, "No entity to deconstruct at " .. x .. "," .. y
end

-- Connect circuit wire: connect_wire x1=N y1=N x2=N y2=N [wire=red|green]
function cmd_handlers.connect_wire(args)
    local player = get_player()
    if not player then
        return false, "No player"
    end

    local x1 = tonumber(args.x1)
    local y1 = tonumber(args.y1)
    local x2 = tonumber(args.x2)
    local y2 = tonumber(args.y2)
    local wire_type = args.wire or "red"

    if not x1 or not y1 or not x2 or not y2 then
        return false, "Missing coordinates"
    end

    local wire = wire_type == "green" and defines.wire_type.green or defines.wire_type.red

    local e1 = player.surface.find_entities_filtered{position = {x = x1, y = y1}, radius = 0.5}
    local e2 = player.surface.find_entities_filtered{position = {x = x2, y = y2}, radius = 0.5}

    if #e1 > 0 and #e2 > 0 then
        e1[1].connect_neighbour{wire = wire, target_entity = e2[1]}
        return true, "Connected with " .. wire_type .. " wire"
    end

    return false, "Entities not found"
end

-- Set recipe for assembler: recipe x=N y=N name=recipe-name
function cmd_handlers.recipe(args)
    local player = get_player()
    if not player then
        return false, "No player"
    end

    local x = tonumber(args.x or args[1])
    local y = tonumber(args.y or args[2])
    local name = args.name or args[3]

    if not x or not y or not name then
        return false, "Missing x, y, or recipe name"
    end

    local entities = player.surface.find_entities_filtered{
        position = {x = x, y = y},
        radius = 0.5,
        type = {"assembling-machine", "furnace", "chemical-plant"}
    }

    for _, entity in pairs(entities) do
        if entity.set_recipe then
            local result = entity.set_recipe(name)
            if result then
                return true, "Set recipe to " .. name
            end
        end
    end

    return false, "Cannot set recipe at " .. x .. "," .. y
end

-- Copy settings: copy_settings from_x=N from_y=N to_x=N to_y=N
function cmd_handlers.copy_settings(args)
    local player = get_player()
    if not player then
        return false, "No player"
    end

    local from_x = tonumber(args.from_x)
    local from_y = tonumber(args.from_y)
    local to_x = tonumber(args.to_x)
    local to_y = tonumber(args.to_y)

    if not from_x or not from_y or not to_x or not to_y then
        return false, "Missing coordinates"
    end

    local from = player.surface.find_entities_filtered{position = {x = from_x, y = from_y}, radius = 0.5}
    local to = player.surface.find_entities_filtered{position = {x = to_x, y = to_y}, radius = 0.5}

    if #from > 0 and #to > 0 then
        to[1].copy_settings(from[1])
        return true, "Copied settings"
    end

    return false, "Entities not found"
end

-- Launch rocket: launch x=N y=N
function cmd_handlers.launch(args)
    local player = get_player()
    if not player then
        return false, "No player"
    end

    local x = tonumber(args.x or args[1])
    local y = tonumber(args.y or args[2])

    if not x or not y then
        return false, "Missing x or y coordinate"
    end

    local silos = player.surface.find_entities_filtered{
        position = {x = x, y = y},
        radius = 5,
        name = "rocket-silo"
    }

    for _, silo in pairs(silos) do
        if silo.rocket_parts == silo.prototype.rocket_parts_required then
            silo.launch_rocket()
            return true, "Launched rocket!"
        end
    end

    return false, "No ready rocket silo at " .. x .. "," .. y
end

-- Scan area: scan [radius=N]
function cmd_handlers.scan(args)
    local player = get_player()
    if not player or not player.character then
        return false, "No player character"
    end

    local radius = tonumber(args.radius or args[1]) or 20
    local pos = player.position

    local entities = player.surface.find_entities_filtered{
        area = {{pos.x - radius, pos.y - radius}, {pos.x + radius, pos.y + radius}}
    }

    local entity_list = {}
    for _, entity in pairs(entities) do
        if entity.name ~= "character" then
            table.insert(entity_list, {
                name = entity.name,
                type = entity.type,
                x = math.floor(entity.position.x * 10) / 10,
                y = math.floor(entity.position.y * 10) / 10,
                direction = entity.direction,
                health = entity.health,
                unit_number = entity.unit_number
            })
        end
    end

    return true, "Found " .. #entity_list .. " entities", {entities = entity_list}
end

-- Find resources: find_resources [type=iron-ore] [radius=N]
function cmd_handlers.find_resources(args)
    local player = get_player()
    if not player or not player.character then
        return false, "No player character"
    end

    local resource_type = args.type or args[1]
    local radius = tonumber(args.radius or args[2]) or 50
    local pos = player.position

    local filter = {
        area = {{pos.x - radius, pos.y - radius}, {pos.x + radius, pos.y + radius}},
        type = "resource"
    }

    if resource_type then
        filter.name = resource_type
    end

    local resources = player.surface.find_entities_filtered(filter)

    -- Group by type and find cluster centers
    local clusters = {}
    for _, res in pairs(resources) do
        if not clusters[res.name] then
            clusters[res.name] = {
                count = 0,
                total_x = 0,
                total_y = 0,
                total_amount = 0
            }
        end
        clusters[res.name].count = clusters[res.name].count + 1
        clusters[res.name].total_x = clusters[res.name].total_x + res.position.x
        clusters[res.name].total_y = clusters[res.name].total_y + res.position.y
        clusters[res.name].total_amount = clusters[res.name].total_amount + res.amount
    end

    local result = {}
    for name, data in pairs(clusters) do
        table.insert(result, {
            name = name,
            count = data.count,
            center_x = math.floor(data.total_x / data.count * 10) / 10,
            center_y = math.floor(data.total_y / data.count * 10) / 10,
            total_amount = data.total_amount
        })
    end

    return true, "Found " .. #result .. " resource types", {resources = result}
end

-- Get player status: status
function cmd_handlers.status(args)
    local player = get_player()
    if not player then
        return false, "No player"
    end

    local character = player.character
    local data = {
        position = character and {
            x = math.floor(character.position.x * 10) / 10,
            y = math.floor(character.position.y * 10) / 10
        } or nil,
        health = character and character.health or 0,
        max_health = character and character.prototype.max_health or 0,
        mining = agent_state.mining_target ~= nil,
        walking = agent_state.walking_direction ~= nil,
        walking_direction = agent_state.walking_direction,
        crafting_queue_size = player.crafting_queue_size,
        game_tick = game.tick,
        daytime = player.surface.daytime,
        pollution = character and player.surface.get_pollution(character.position) or 0
    }

    return true, "Status retrieved", data
end

-- Get recipes: recipes [filter=string]
function cmd_handlers.recipes(args)
    local player = get_player()
    if not player then
        return false, "No player"
    end

    local filter = args.filter or args[1]
    local recipes = {}

    for name, recipe in pairs(player.force.recipes) do
        if recipe.enabled then
            if not filter or string.find(name, filter) then
                table.insert(recipes, {
                    name = name,
                    category = recipe.category,
                    energy = recipe.energy
                })
            end
        end
    end

    return true, "Found " .. #recipes .. " recipes", {recipes = recipes}
end

-- Get technologies: technologies [filter=string]
function cmd_handlers.technologies(args)
    local player = get_player()
    if not player then
        return false, "No player"
    end

    local filter = args.filter or args[1]
    local techs = {}

    for name, tech in pairs(player.force.technologies) do
        if not filter or string.find(name, filter) then
            table.insert(techs, {
                name = name,
                researched = tech.researched,
                enabled = tech.enabled,
                level = tech.level,
                research_unit_count = tech.research_unit_count
            })
        end
    end

    return true, "Found " .. #techs .. " technologies", {technologies = techs}
end

-- Get current research: current_research
function cmd_handlers.current_research(args)
    local player = get_player()
    if not player then
        return false, "No player"
    end

    local research = player.force.current_research
    if research then
        return true, "Researching " .. research.name, {
            name = research.name,
            progress = player.force.research_progress,
            level = research.level
        }
    end

    return true, "No active research", {name = nil}
end

-- Chat/print message: chat message=text
function cmd_handlers.chat(args)
    local message = args.message or args[1]
    if message then
        game.print("[Agent] " .. message)
        return true, "Message sent"
    end
    return false, "No message provided"
end

-- Run Lua code (admin only, for advanced automation): lua code=string
function cmd_handlers.lua(args)
    local code = args.code or args[1]
    if not code then
        return false, "No code provided"
    end

    local func, err = load(code, "claude-command", "t", {
        game = game,
        defines = defines,
        script = script,
        math = math,
        string = string,
        table = table,
        pairs = pairs,
        ipairs = ipairs,
        tonumber = tonumber,
        tostring = tostring,
        type = type
    })

    if not func then
        return false, "Syntax error: " .. tostring(err)
    end

    local ok, result = pcall(func)
    if ok then
        return true, "Code executed", {result = tostring(result)}
    else
        return false, "Runtime error: " .. tostring(result)
    end
end

-- Help: list all commands
function cmd_handlers.help(args)
    local cmd_list = {}
    for name, _ in pairs(cmd_handlers) do
        table.insert(cmd_list, name)
    end
    table.sort(cmd_list)
    return true, "Available commands", {commands = cmd_list}
end

-- Parse and execute a command line
local function execute_command(line, cmd_id)
    local cmd, arg_string = string.match(line, "^([%w_]+)%s*(.*)")

    if not cmd then
        add_response(cmd_id, "error", "Invalid command format")
        return
    end

    cmd = string.lower(cmd)

    if not cmd_handlers[cmd] then
        add_response(cmd_id, "error", "Unknown command: " .. cmd)
        return
    end

    local args = parse_args(arg_string)
    local ok, err = pcall(function()
        local success, message, data = cmd_handlers[cmd](args)
        add_response(cmd_id, success and "ok" or "error", message, data)
    end)

    if not ok then
        add_response(cmd_id, "error", "Command failed: " .. tostring(err))
    end
end

-- Read commands from file
local function read_commands()
    -- Commands are passed via RCON or console
    -- File reading is limited in Factorio, so we use a different approach
    -- Commands can be sent via: /claude walk direction=north
end

-- Write game state to file
local function write_game_state()
    local player = get_player()
    if not player then return end

    local character = player.character
    local state = {
        tick = game.tick,
        player = {
            position = character and {
                x = math.floor(character.position.x * 100) / 100,
                y = math.floor(character.position.y * 100) / 100
            } or nil,
            health = character and character.health or 0,
            max_health = character and character.prototype.max_health or 0,
            walking = agent_state.walking_direction,
            mining = agent_state.mining_target ~= nil
        },
        crafting_queue_size = player.crafting_queue_size,
        research = player.force.current_research and {
            name = player.force.current_research.name,
            progress = player.force.research_progress
        } or nil,
        responses = agent_state.pending_responses
    }

    -- Write state
    helpers.write_file(STATE_FILE, to_json(state) .. "\n", false)

    -- Clear pending responses after writing
    agent_state.pending_responses = {}
end

-- Write responses only
local function write_responses()
    if #agent_state.pending_responses > 0 then
        local response_text = to_json(agent_state.pending_responses) .. "\n"
        helpers.write_file(RESPONSE_FILE, response_text, false)
        agent_state.pending_responses = {}
    end
end

script.on_init(function()
    -- Initialize state
end)

script.on_load(function()
    -- Restore state on load
end)

-- Register unified console command
commands.add_command("agent", "Agent API - use: /agent <command> <args>", function(event)
    if not event.parameter or event.parameter == "" then
        game.print("Usage: /agent <command> <args>")
        game.print("Commands: walk, stop, mine, build, craft, research, inventory, scan, status, help")
        return
    end

    agent_state.last_command_id = agent_state.last_command_id + 1
    execute_command(event.parameter, agent_state.last_command_id)
    write_responses()
end)

-- Per-tick updates
script.on_event(defines.events.on_tick, function(event)
    agent_state.tick_counter = agent_state.tick_counter + 1

    -- Maintain walking state
    local player = get_player()
    if player and player.character and agent_state.walking_direction then
        player.walking_state = {
            walking = true,
            direction = DIRECTIONS[agent_state.walking_direction]
        }
    end

    -- Write state periodically (every 60 ticks = 1 second)
    if agent_state.tick_counter % 60 == 0 then
        write_game_state()
    end
end)

-- Handle mining completion
script.on_event(defines.events.on_player_mined_entity, function(event)
    if agent_state.mining_target then
        agent_state.mining_target = nil
        add_response(0, "event", "Mining complete", {entity = event.entity.name})
    end
end)

-- Handle crafting completion
script.on_event(defines.events.on_player_crafted_item, function(event)
    add_response(0, "event", "Crafted item", {item = event.item_stack.name, count = event.item_stack.count})
end)

-- Handle research completion
script.on_event(defines.events.on_research_finished, function(event)
    add_response(0, "event", "Research complete", {technology = event.research.name})
    write_responses()
end)

-- Handle player death
script.on_event(defines.events.on_player_died, function(event)
    agent_state.walking_direction = nil
    agent_state.mining_target = nil
    add_response(0, "event", "Player died", {cause = event.cause and event.cause.name or "unknown"})
    write_responses()
end)

-- Handle entity damage (for combat awareness)
script.on_event(defines.events.on_entity_damaged, function(event)
    local player = get_player()
    if player and player.character and event.entity == player.character then
        add_response(0, "event", "Player damaged", {
            damage = event.final_damage_amount,
            source = event.cause and event.cause.name or "unknown",
            health = player.character.health
        })
    end
end)
