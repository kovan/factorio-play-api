-- Mock Factorio API for unit testing

local mocks = {}

-- Store state that persists across function calls
mocks._state = {
    files = {},
    messages = {},
    handlers = {},
    registered_commands = {}
}

-- Mock defines (global constant)
mocks.defines = {
    direction = {
        north = 0,
        northeast = 1,
        east = 2,
        southeast = 3,
        south = 4,
        southwest = 5,
        west = 6,
        northwest = 7
    },
    inventory = {
        chest = 1,
        furnace_source = 2,
        furnace_result = 3
    },
    wire_type = {
        red = 1,
        green = 2
    },
    events = {
        on_tick = 1,
        on_player_mined_entity = 2,
        on_player_crafted_item = 3,
        on_research_finished = 4,
        on_player_died = 5,
        on_entity_damaged = 6
    }
}

-- Mock entity
function mocks.create_entity(name, position, opts)
    opts = opts or {}
    return {
        name = name,
        type = opts.type or "unknown",
        position = position,
        direction = opts.direction or 0,
        health = opts.health or 100,
        prototype = {max_health = 100},
        unit_number = opts.unit_number or math.random(10000),
        amount = opts.amount or 1000,
        rotatable = opts.rotatable ~= false,
        rotate = function(self, params)
            if params and params.reverse then
                self.direction = (self.direction - 1) % 8
            else
                self.direction = (self.direction + 1) % 8
            end
            return true
        end,
        order_deconstruction = function() return true end,
        set_recipe = function(self, recipe) self.recipe = recipe; return true end,
        copy_settings = function() return true end,
        connect_neighbour = function() return true end,
        get_inventory = function(inv_type)
            return mocks.create_inventory()
        end,
        get_fuel_inventory = function()
            return mocks.create_inventory()
        end,
        destroy = function() return true end,
        stack = {name = "iron-ore", count = 1}
    }
end

-- Mock inventory
function mocks.create_inventory(contents)
    contents = contents or {}
    local inv = {
        _contents = contents
    }

    -- Use closures to avoid self issues
    inv.get_contents = function()
        return contents
    end

    inv.get_item_count = function(item)
        return contents[item] or 0
    end

    inv.insert = function(item)
        local name = type(item) == "table" and item.name or item
        local count = type(item) == "table" and item.count or 1
        contents[name] = (contents[name] or 0) + count
        return count
    end

    inv.remove = function(item)
        local name = item.name
        local count = item.count
        local current = contents[name] or 0
        local removed = math.min(current, count)
        contents[name] = current - removed
        if contents[name] <= 0 then
            contents[name] = nil
        end
        return removed
    end

    return inv
end

-- Mock surface
function mocks.create_surface(ents)
    ents = ents or {}
    local surface = {
        _entities = ents,
        daytime = 0.5
    }

    surface.find_entities_filtered = function(filter)
        local results = {}
        for _, e in ipairs(ents) do
            local match = true
            if filter.name and e.name ~= filter.name then match = false end
            if filter.type and e.type ~= filter.type then match = false end
            if filter.position then
                local dx = math.abs(e.position.x - filter.position.x)
                local dy = math.abs(e.position.y - filter.position.y)
                local radius = filter.radius or 0.5
                if dx > radius or dy > radius then match = false end
            end
            if filter.area then
                local x, y = e.position.x, e.position.y
                if x < filter.area[1][1] or x > filter.area[2][1] or
                   y < filter.area[1][2] or y > filter.area[2][2] then
                    match = false
                end
            end
            if match then table.insert(results, e) end
        end
        return results
    end

    surface.can_place_entity = function(params)
        return true
    end

    surface.create_entity = function(params)
        local entity = mocks.create_entity(params.name, params.position, {
            direction = params.direction
        })
        table.insert(ents, entity)
        return entity
    end

    surface.get_pollution = function(position)
        return 0
    end

    return surface
end

-- Mock force
function mocks.create_force()
    local technologies = {
        automation = {name = "automation", researched = false, enabled = true, level = 1, research_unit_count = 10},
        logistics = {name = "logistics", researched = false, enabled = true, level = 1, research_unit_count = 20}
    }
    local recipes = {
        ["iron-gear-wheel"] = {name = "iron-gear-wheel", enabled = true, category = "crafting", energy = 0.5},
        ["transport-belt"] = {name = "transport-belt", enabled = true, category = "crafting", energy = 0.5}
    }

    local force = {
        technologies = technologies,
        recipes = recipes,
        current_research = nil,
        research_progress = 0,
        research_queue_enabled = false
    }

    force.add_research = function(name)
        force.current_research = technologies[name]
        return true
    end

    return force
end

-- Mock player
function mocks.create_player(opts)
    opts = opts or {}
    local inventory = mocks.create_inventory(opts.inventory or {["iron-plate"] = 100, ["transport-belt"] = 50})
    local surface = mocks.create_surface(opts.entities or {})
    local force = mocks.create_force()

    local player = {
        position = opts.position or {x = 0, y = 0},
        walking_state = {walking = false, direction = 0},
        mining_state = {mining = false},
        crafting_queue_size = opts.crafting_queue_size or 0,
        surface = surface,
        force = force,
        _inventory = inventory
    }

    -- Create character
    player.character = opts.character ~= false and {
        position = player.position,
        health = opts.health or 250,
        prototype = {max_health = 250}
    } or nil

    -- Use closures instead of self to handle both dot and colon calling conventions
    player.get_main_inventory = function()
        return inventory
    end

    player.can_reach_entity = function(entity)
        return true
    end

    player.insert = function(item)
        return inventory:insert(item)
    end

    player.begin_crafting = function(params)
        if not params then return 0 end
        return params.count or 1
    end

    return player
end

-- Setup all mocks as globals
function mocks.setup()
    -- Reset state
    mocks._state = {
        files = {},
        messages = {},
        handlers = {},
        registered_commands = {}
    }

    local player = mocks.create_player()

    -- Set up globals
    defines = mocks.defines

    -- Game object - note: Factorio uses game.get_player(id) not game:get_player(id)
    game = {
        tick = 1000,
        _player = player,
        get_player = function(id)
            return game._player
        end,
        print = function(msg)
            table.insert(mocks._state.messages, msg)
        end
    }

    -- Helpers object - note: helpers.write_file(filename, content, append) not helpers:write_file
    helpers = {
        write_file = function(filename, content, append)
            if append then
                mocks._state.files[filename] = (mocks._state.files[filename] or "") .. content
            else
                mocks._state.files[filename] = content
            end
        end
    }

    -- Script object
    script = {
        on_init = function(handler)
            mocks._state.handlers.on_init = handler
        end,
        on_load = function(handler)
            mocks._state.handlers.on_load = handler
        end,
        on_event = function(event_id, handler)
            mocks._state.handlers[event_id] = handler
        end
    }

    -- Commands object
    commands = {
        add_command = function(name, help, handler)
            mocks._state.registered_commands[name] = {help = help, handler = handler}
        end
    }

    return {
        player = player,
        game = game,
        helpers = helpers,
        script = script,
        commands = commands,
        get_files = function()
            return mocks._state.files
        end,
        get_handlers = function()
            return mocks._state.handlers
        end,
        get_registered_commands = function()
            return mocks._state.registered_commands
        end,
        call_command = function(name, parameter)
            local cmd = mocks._state.registered_commands[name]
            if cmd then
                cmd.handler({parameter = parameter})
            end
        end
    }
end

-- Teardown mocks
function mocks.teardown()
    defines = nil
    game = nil
    helpers = nil
    script = nil
    commands = nil
end

return mocks
