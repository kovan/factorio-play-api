



A Factorio mod that provides a command-based API for programmatic game control.

## Installation

1. Copy the `factorio-agent-api` folder to your Factorio mods directory:
   - Windows: `%APPDATA%\Factorio\mods\`
   - Linux: `~/.factorio/mods/`
   - macOS: `~/Library/Application Support/factorio/mods/`

2. Enable the mod in Factorio's mod menu.

## Usage

### Example Session

```
/agent status
/agent find_resources type=iron-ore radius=100
/agent walk direction=east
/agent stop
/agent mine x=15 y=0
/agent inventory
/agent craft name=iron-gear-wheel count=10
/agent build name=stone-furnace x=5 y=5
/agent put x=5 y=5 item=coal count=25
/agent put x=5 y=5 item=iron-ore count=50
```


All commands are issued via the in-game console using `/agent <command> <args>`.

Arguments use `key=value` format, separated by commas.

## Output Files

The mod writes to `script-output/` folder:
- `agent-gamestate.json` - Game state updated every second
- `agent-response.txt` - Command responses

## Commands

### Movement

```
/agent walk direction=north|south|east|west|northeast|northwest|southeast|southwest
/agent walk direction=stop
/agent stop
```

### Mining

```
/agent mine x=10 y=20
```
Mines entity or resource at the specified position.

### Building

```
/agent build name=transport-belt x=10 y=20 direction=north
```
Places an entity from inventory. Direction is optional (default: north).

### Crafting

```
/agent craft name=iron-gear-wheel count=5
```
Queues crafting. Count is optional (default: 1).

### Inventory

```
/agent inventory
/agent pickup x=10 y=20
/agent put x=10 y=20 item=coal count=50
/agent take x=10 y=20 item=iron-plate count=100
```

### Entity Interaction

```
/agent rotate x=10 y=20 reverse=false
/agent deconstruct x=10 y=20
/agent recipe x=10 y=20 name=iron-gear-wheel
/agent copy_settings from_x=10 from_y=20 to_x=15 to_y=20
/agent connect_wire x1=10 y1=20 x2=15 y2=20 wire=red
```

### Research

```
/agent research name=automation
/agent current_research
/agent technologies filter=automation
```

### Scanning

```
/agent scan radius=30
/agent find_resources type=iron-ore radius=100
/agent status
```

### Utility

```
/agent recipes filter=iron
/agent chat message=Hello world
/agent help
/agent lua code=game.print('test')
```

### Rocket Launch

```
/agent launch x=10 y=20
```

## Game State Output

The `agent-gamestate.json` file contains:

```json
{
  "tick": 12345,
  "player": {
    "position": {"x": 0.5, "y": -3.2},
    "health": 250,
    "max_health": 250,
    "walking": "north",
    "mining": false
  },
  "crafting_queue_size": 2,
  "research": {
    "name": "automation",
    "progress": 0.45
  },
  "responses": [
    {
      "id": 1,
      "status": "ok",
      "message": "Walking north",
      "tick": 12340
    }
  ]
}
```

## Response Format

Command responses in `agent-response.txt`:

```json
[
  {
    "id": 1,
    "status": "ok",
    "message": "Built transport-belt at 10,20",
    "data": {"entity_id": 12345},
    "tick": 12340
  }
]
```

Status values: `ok`, `error`, `event`

## Events

The mod tracks and reports these events:
- Mining completion
- Crafting completion
- Research completion
- Player death
- Player damage

## Automation via RCON

For external automation, use Factorio's RCON:

1. Start Factorio with RCON enabled:
   ```
   factorio --start-server save.zip --rcon-port 27015 --rcon-password mypassword
   ```

2. Send commands via RCON:
   ```
   /agent walk direction=north
   ```

3. Read state from `script-output/agent-gamestate.json`

