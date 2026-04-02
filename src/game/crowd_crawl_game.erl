-module(crowd_crawl_game).
-behaviour(asobi_match).

-export([init/1, join/2, leave/2, handle_input/3, tick/1, get_state/2]).
-export([vote_requested/1, vote_started/1, vote_resolved/3]).

-define(ROOMS_PER_FLOOR, 5).
-define(HERO_START_HP, 100).
-define(HERO_START_ATK, 10).
-define(HERO_START_DEF, 5).

-spec init(map()) -> {ok, map()}.
init(Config) ->
    Seed = maps:get(seed, Config, erlang:unique_integer([positive])),
    Room0 = crowd_crawl_dungeon:generate(Seed, 0),
    {SpawnX, SpawnY} = maps:get(spawn, Room0, {2, 2}),
    {ok, #{
        phase => exploring,
        seed => Seed,
        floor => 1,
        room_index => 0,
        current_room => Room0,
        hero => #{
            hp => ?HERO_START_HP,
            max_hp => ?HERO_START_HP,
            attack => ?HERO_START_ATK,
            defense => ?HERO_START_DEF,
            buffs => [],
            x => float(SpawnX),
            y => float(SpawnY)
        },
        enemies => maps:get(enemies, Room0, []),
        inventory => [],
        cleared_rooms => [],
        hero_player_id => undefined,
        vote_pending => none,
        vote_active => false,
        rooms_until_boss => ?ROOMS_PER_FLOOR,
        boss_modifier => none,
        tick_count => 0
    }}.

-spec join(binary(), map()) -> {ok, map()} | {error, term()}.
join(PlayerId, #{hero_player_id := undefined} = State) ->
    {ok, State#{hero_player_id => PlayerId}};
join(_PlayerId, State) ->
    %% Audience member — joins match but doesn't control hero
    {ok, State}.

-spec leave(binary(), map()) -> {ok, map()}.
leave(PlayerId, #{hero_player_id := PlayerId} = State) ->
    {ok, State#{phase => dead}};
leave(_PlayerId, State) ->
    {ok, State}.

-spec handle_input(binary(), map(), map()) -> {ok, map()} | {error, term()}.
handle_input(PlayerId, Input, #{hero_player_id := HeroId} = State) when PlayerId =:= HeroId ->
    handle_hero_input(Input, State);
handle_input(_PlayerId, _Input, _State) ->
    {error, not_hero}.

-spec tick(map()) -> {ok, map()} | {finished, map(), map()}.
tick(#{phase := dead, vote_active := false, vote_pending := none} = State) ->
    {finished, #{status => ~"defeat", floor => maps:get(floor, State)}, State};
tick(#{phase := won} = State) ->
    {finished, #{status => ~"victory", floor => maps:get(floor, State)}, State};
tick(#{phase := voting} = State) ->
    {ok, State};
tick(#{phase := combat} = State) ->
    tick_combat(State);
tick(#{phase := exploring, enemies := Enemies, tick_count := TC} = State) when length(Enemies) > 0 ->
    {ok, State#{phase => combat, tick_count => TC + 1}};
tick(#{phase := exploring, tick_count := TC} = State) ->
    {ok, State#{tick_count => TC + 1}}.

-spec get_state(binary(), map()) -> map().
get_state(_PlayerId, State) ->
    #{
        phase => maps:get(phase, State),
        floor => maps:get(floor, State),
        room_index => maps:get(room_index, State),
        room => room_render_data(maps:get(current_room, State)),
        hero => maps:get(hero, State),
        enemies => maps:get(enemies, State),
        inventory => [maps:with([id, label, tarot], B) || B <- maps:get(inventory, State)],
        rooms_cleared => length(maps:get(cleared_rooms, State)),
        rooms_until_boss => maps:get(rooms_until_boss, State),
        vote_active => maps:get(vote_active, State)
    }.

-spec vote_requested(map()) -> {ok, map()} | none.
vote_requested(#{vote_pending := none}) -> none;
vote_requested(#{vote_active := true}) -> none;
vote_requested(#{vote_pending := VoteConfig}) -> {ok, VoteConfig}.

-spec vote_started(map()) -> map().
vote_started(State) ->
    State#{vote_pending => none, vote_active => true, phase => voting}.

-spec vote_resolved(binary(), map(), map()) -> {ok, map()}.
vote_resolved(~"boon_pick", #{winner := Winner}, State) when is_binary(Winner) ->
    Boon = crowd_crawl_boons:get(Winner),
    Hero = apply_boon(Boon, maps:get(hero, State)),
    Inventory = [Boon | maps:get(inventory, State)],
    {ok, State#{hero => Hero, inventory => Inventory, vote_active => false, phase => exploring}};
vote_resolved(~"path_choice", #{winner := Winner}, State) when is_binary(Winner) ->
    enter_next_room(Winner, State#{vote_active => false});
vote_resolved(~"buff_nerf", #{winner := ~"buff"}, State) ->
    Hero = maps:get(hero, State),
    Hero1 = Hero#{attack => maps:get(attack, Hero) + 2},
    {ok, State#{hero => Hero1, vote_active => false, phase => exploring}};
vote_resolved(~"buff_nerf", #{winner := ~"nerf"}, State) ->
    %% Nerf: next room enemies get +50% HP (handled in dungeon generation)
    {ok, State#{vote_active => false, phase => exploring}};
vote_resolved(~"boss_modifier", #{winner := Modifier}, State) when is_binary(Modifier) ->
    {ok, State#{boss_modifier => Modifier, vote_active => false, phase => exploring}};
vote_resolved(~"mercy_vote", #{winner := ~"revive"}, State) ->
    Hero = maps:get(hero, State),
    MaxHp = maps:get(max_hp, Hero),
    Hero1 = Hero#{hp => MaxHp div 2},
    {ok, State#{hero => Hero1, vote_active => false, phase => exploring}};
vote_resolved(~"mercy_vote", _, State) ->
    %% No supermajority or voted to let hero die
    {ok, State#{vote_active => false}};
vote_resolved(_Template, _Result, State) ->
    {ok, State#{vote_active => false, phase => exploring}}.

%% --- Hero Input ---

handle_hero_input(#{~"action" := ~"move", ~"direction" := Dir}, #{phase := Phase} = State) when
    Phase =:= exploring; Phase =:= combat
->
    Hero = maps:get(hero, State),
    {Dx, Dy} = direction_delta(Dir),
    X = maps:get(x, Hero) + Dx,
    Y = maps:get(y, Hero) + Dy,
    Room = maps:get(current_room, State),
    case crowd_crawl_dungeon:walkable(Room, X, Y) of
        true ->
            Hero1 = Hero#{x => X, y => Y},
            State1 = State#{hero => Hero1},
            State2 = check_door(X, Y, State1),
            State3 = check_enemy_aggro(State2),
            {ok, State3};
        false ->
            {ok, State}
    end;
handle_hero_input(#{~"action" := ~"attack"}, #{phase := exploring, enemies := Enemies} = State) when
    length(Enemies) > 0
->
    handle_hero_input(#{~"action" => ~"attack"}, State#{phase => combat});
handle_hero_input(#{~"action" := ~"attack"}, #{phase := combat, enemies := Enemies} = State) ->
    case Enemies of
        [] ->
            {ok, State#{phase => exploring}};
        [Target | Rest] ->
            Hero = maps:get(hero, State),
            %% Hero attacks first enemy
            Atk = maps:get(attack, Hero),
            Dmg = max(1, Atk - maps:get(defense, Target, 0)),
            TargetHp = maps:get(hp, Target) - Dmg,
            NewEnemies = case TargetHp =< 0 of
                true -> Rest;
                false -> [Target#{hp => TargetHp} | Rest]
            end,
            %% Surviving enemies counter-attack
            Def = maps:get(defense, Hero),
            CounterDmg = lists:sum([max(1, maps:get(attack, E, 3) - Def) || E <- NewEnemies]),
            HeroHp = maps:get(hp, Hero) - CounterDmg,
            case HeroHp =< 0 of
                true ->
                    VoteConfig = crowd_crawl_votes:mercy(),
                    {ok, State#{
                        hero => Hero#{hp => 0},
                        enemies => NewEnemies,
                        phase => dead,
                        vote_pending => VoteConfig
                    }};
                false ->
                    State1 = State#{hero => Hero#{hp => HeroHp}, enemies => NewEnemies},
                    %% Check if all enemies dead
                    case NewEnemies of
                        [] -> trigger_room_clear(State1);
                        _ -> {ok, State1}
                    end
            end
    end;
handle_hero_input(_, State) ->
    {ok, State}.

%% --- Combat ---

tick_combat(State) ->
    %% Turn-based: tick just keeps the match alive. Damage happens in handle_hero_input.
    {ok, State}.

trigger_room_clear(#{rooms_until_boss := RUB} = State) ->
    RoomIdx = maps:get(room_index, State),
    Cleared = [RoomIdx | maps:get(cleared_rooms, State)],
    case RUB =< 1 of
        true ->
            VoteConfig = crowd_crawl_votes:boss_modifier(),
            {ok, State#{
                cleared_rooms => Cleared,
                rooms_until_boss => ?ROOMS_PER_FLOOR,
                phase => exploring,
                vote_pending => VoteConfig
            }};
        false ->
            VoteConfig = crowd_crawl_votes:boon_pick(maps:get(seed, State), RoomIdx),
            {ok, State#{
                cleared_rooms => Cleared,
                rooms_until_boss => RUB - 1,
                phase => exploring,
                vote_pending => VoteConfig
            }}
    end.

%% --- Room Transitions ---

check_door(X, Y, State) ->
    Room = maps:get(current_room, State),
    case crowd_crawl_dungeon:door_at(Room, X, Y) of
        false ->
            State;
        {door, Doors} when length(Doors) > 1 ->
            VoteConfig = crowd_crawl_votes:path_choice(Doors),
            State#{vote_pending => VoteConfig};
        {door, [Door]} ->
            case enter_next_room(maps:get(id, Door), State) of
                {ok, S} -> S
            end
    end.

check_enemy_aggro(#{phase := exploring, enemies := Enemies} = State) when length(Enemies) > 0 ->
    State#{phase => combat};
check_enemy_aggro(State) ->
    State.

enter_next_room(DoorId, State) ->
    Seed = maps:get(seed, State),
    RoomIdx = maps:get(room_index, State) + 1,
    DoorHash = erlang:phash2(DoorId),
    Room = crowd_crawl_dungeon:generate(Seed + DoorHash, RoomIdx),
    {SpawnX, SpawnY} = maps:get(spawn, Room, {2, 2}),
    Hero = maps:get(hero, State),
    {ok, State#{
        room_index => RoomIdx,
        current_room => Room,
        enemies => maps:get(enemies, Room, []),
        hero => Hero#{x => float(SpawnX), y => float(SpawnY)},
        phase => exploring
    }}.

%% --- Helpers ---

direction_delta(~"up") -> {0.0, -1.0};
direction_delta(~"down") -> {0.0, 1.0};
direction_delta(~"left") -> {-1.0, 0.0};
direction_delta(~"right") -> {1.0, 0.0};
direction_delta(_) -> {0.0, 0.0}.

apply_boon(#{effect := {hp, Amount}}, Hero) ->
    Hp = min(maps:get(max_hp, Hero), maps:get(hp, Hero) + Amount),
    Hero#{hp => Hp};
apply_boon(#{effect := {attack, Amount}}, Hero) ->
    Hero#{attack => maps:get(attack, Hero) + Amount};
apply_boon(#{effect := {defense, Amount}}, Hero) ->
    Hero#{defense => maps:get(defense, Hero) + Amount};
apply_boon(#{effect := {max_hp, Amount}}, Hero) ->
    MaxHp = maps:get(max_hp, Hero) + Amount,
    Hero#{max_hp => MaxHp, hp => maps:get(hp, Hero) + Amount};
apply_boon(_, Hero) ->
    Hero.

room_render_data(Room) ->
    maps:with([tiles, width, height, doors, type], Room).
