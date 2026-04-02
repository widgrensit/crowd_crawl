# Crowd Crawl

Audience-driven roguelike dungeon crawler built on [Asobi](https://github.com/widgrensit/asobi).

A hero explores procedurally generated dungeons while the crowd votes on what happens next — boon picks, path choices, boss modifiers, and mercy votes using tarot-themed cards.

## Features

- **7 room types** with procedural generation (seeded)
- **Turn-based combat** with target selection, dodge, heal, and item use
- **25 boons** across 3 rarities (common/rare/legendary) with equipment slots
- **5 boss types** with unique abilities (Dragon, Lich, Golem, Shadow, Hydra)
- **Room exploration** — chests, hidden traps, healing fountains
- **Floor progression** with difficulty scaling (+20% per floor)
- **Permadeath** with scoring and run statistics
- **Voting system** — tarot card votes for boons, paths, boss modifiers, mercy

## Quick Start

### Prerequisites

- Erlang/OTP 28+
- rebar3
- Docker (for PostgreSQL)

### Run

```bash
# Start PostgreSQL
docker compose up -d

# Compile and start
rebar3 compile
rebar3 shell
```

The server starts on `http://localhost:8083`.

### Run the Flame Client

See [crowd_crawl_client](https://github.com/widgrensit/crowd_crawl_client).

```bash
git clone https://github.com/widgrensit/crowd_crawl_client.git
cd crowd_crawl_client
flutter pub get
flutter run -d linux   # or: flutter run -d chrome
```

### Controls

| Key | Action |
|-----|--------|
| WASD / Arrows | Move |
| Space | Attack targeted enemy |
| 1-5 | Target specific enemy |
| Tab | Cycle target |
| E | Interact (chests, fountains) |
| H | Use heal potion |
| Q | Dodge |

## Architecture

Crowd Crawl is a game built **on** Asobi — it depends on `asobi` as a library and uses its match server, WebSocket handler, voting system, auth, and economy.

```
crowd_crawl (Erlang/Nova)
├── crowd_crawl_game.erl      — asobi_match behaviour (game logic)
├── crowd_crawl_dungeon.erl   — procedural room generation
├── crowd_crawl_enemies.erl   — 10 enemy types + 5 bosses
├── crowd_crawl_boons.erl     — 25 items with rarity/equipment
├── crowd_crawl_votes.erl     — vote config builders
└── crowd_crawl_match_controller.erl — match creation endpoint
```

## Configuration

Edit `config/dev_sys.config` for:
- `game_modes` — register game module
- `vote_templates` — configure vote timing/methods
- `rate_limits` — request throttling
- `kura` — database connection (port 5433 by default)

## License

Apache-2.0
