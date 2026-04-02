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
    Room0 = crowd_crawl_dungeon:generate(Seed, 0, 1),
    {SpawnX, SpawnY} = maps:get(spawn, Room0, {2, 2}),
    {ok, #{
        phase => exploring,
        seed => Seed,
        floor => 1,
        room_index => 0,
        total_rooms_cleared => 0,
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
        equipment => #{weapon => none, armor => none, accessory => none},
        enemies => maps:get(enemies, Room0, []),
        features => maps:get(features, Room0, []),
        inventory => [],
        cleared_rooms => [],
        hero_player_id => undefined,
        vote_pending => none,
        vote_active => false,
        rooms_until_boss => ?ROOMS_PER_FLOOR,
        boss_modifier => none,
        is_boss_room => false,
        tick_count => 0,
        gold => 0,
        enemies_killed => 0,
        boons_collected => 0,
        start_time => erlang:system_time(second),
        smoke_bomb_active => false
    }}.

-spec join(binary(), map()) -> {ok, map()} | {error, term()}.
join(PlayerId, #{hero_player_id := undefined} = State) ->
    {ok, State#{hero_player_id => PlayerId}};
join(_PlayerId, State) ->
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
    {finished, build_run_result(~"defeat", State), State};
tick(#{phase := won} = State) ->
    {finished, build_run_result(~"victory", State), State};
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
        hero => sanitize_hero(maps:get(hero, State)),
        enemies => [sanitize_enemy(E) || E <- maps:get(enemies, State)],
        inventory => [maps:with([id, label, tarot, kind, rarity], B) || B <- maps:get(inventory, State)],
        equipment => sanitize_equipment(maps:get(equipment, State)),
        features => visible_features(maps:get(features, State)),
        rooms_cleared => maps:get(total_rooms_cleared, State),
        rooms_until_boss => maps:get(rooms_until_boss, State),
        is_boss_room => maps:get(is_boss_room, State),
        gold => maps:get(gold, State),
        enemies_killed => maps:get(enemies_killed, State),
        score => calculate_score(State),
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
    Equipment = maybe_equip(Boon, maps:get(equipment, State)),
    Collected = maps:get(boons_collected, State) + 1,
    {ok, State#{
        hero => Hero, inventory => Inventory, equipment => Equipment,
        boons_collected => Collected, vote_active => false, phase => exploring
    }};
vote_resolved(~"path_choice", #{winner := Winner}, State) when is_binary(Winner) ->
    enter_next_room(Winner, State#{vote_active => false});
vote_resolved(~"buff_nerf", #{winner := ~"buff"}, State) ->
    Hero = maps:get(hero, State),
    Hero1 = Hero#{attack => maps:get(attack, Hero) + 2},
    {ok, State#{hero => Hero1, vote_active => false, phase => exploring}};
vote_resolved(~"buff_nerf", #{winner := ~"nerf"}, State) ->
    {ok, State#{vote_active => false, phase => exploring}};
vote_resolved(~"boss_modifier", #{winner := Modifier}, State) when is_binary(Modifier) ->
    {ok, State#{boss_modifier => Modifier, vote_active => false, phase => exploring}};
vote_resolved(~"mercy_vote", #{winner := ~"revive"}, State) ->
    Hero = maps:get(hero, State),
    MaxHp = maps:get(max_hp, Hero),
    Hero1 = Hero#{hp => MaxHp div 2},
    {ok, State#{hero => Hero1, vote_active => false, phase => exploring}};
vote_resolved(~"mercy_vote", _, State) ->
    {ok, State#{vote_active => false}};
vote_resolved(_Template, _Result, State) ->
    {ok, State#{vote_active => false, phase => exploring}}.

%% --- Hero Input ---

-spec handle_hero_input(map(), map()) -> {ok, map()} | {error, term()}.
handle_hero_input(#{~"action" := ~"move", ~"direction" := Dir}, #{phase := Phase} = State) when
    Phase =:= exploring; Phase =:= combat
->
    handle_move(Dir, State);
handle_hero_input(#{~"action" := ~"attack"} = Input, #{phase := exploring, enemies := Enemies} = State) when
    length(Enemies) > 0
->
    handle_hero_input(Input, State#{phase => combat});
handle_hero_input(#{~"action" := ~"attack"} = Input, #{phase := combat} = State) ->
    Target = maps:get(~"target", Input, 0),
    handle_attack(Target, State);
handle_hero_input(#{~"action" := ~"dodge"}, #{phase := combat} = State) ->
    handle_dodge(State);
handle_hero_input(#{~"action" := ~"heal"}, #{phase := Phase} = State) when
    Phase =:= combat; Phase =:= exploring
->
    handle_heal_potion(State);
handle_hero_input(#{~"action" := ~"interact"}, #{phase := exploring} = State) ->
    handle_interact(State);
handle_hero_input(#{~"action" := ~"use", ~"item" := ItemId}, State) ->
    handle_use_item(ItemId, State);
handle_hero_input(_, State) ->
    {ok, State}.

-spec handle_move(binary(), map()) -> {ok, map()}.
handle_move(Dir, State) ->
    Hero = maps:get(hero, State),
    {Dx, Dy} = direction_delta(Dir),
    X = maps:get(x, Hero) + Dx,
    Y = maps:get(y, Hero) + Dy,
    Room = maps:get(current_room, State),
    case crowd_crawl_dungeon:walkable(Room, X, Y) of
        true ->
            Hero1 = Hero#{x => X, y => Y},
            State1 = State#{hero => Hero1},
            State2 = check_feature_trigger(X, Y, State1),
            State3 = check_door(X, Y, State2),
            State4 = check_enemy_aggro(State3),
            State5 = move_melee_enemies(State4),
            {ok, State5};
        false ->
            {ok, State}
    end.

-spec handle_attack(integer(), map()) -> {ok, map()}.
handle_attack(_TargetIdx, #{enemies := []} = State) ->
    {ok, State#{phase => exploring}};
handle_attack(TargetIdx, State) ->
    Enemies = maps:get(enemies, State),
    Hero = maps:get(hero, State),
    Idx = clamp(TargetIdx, 0, length(Enemies) - 1),
    {Target, OtherEnemies} = extract_at(Idx, Enemies),
    Atk = maps:get(attack, Hero),
    Dmg = max(1, Atk - maps:get(defense, Target, 0)),
    TargetHp = maps:get(hp, Target) - Dmg,
    {NewEnemies, Killed, ExtraGold, State1} = case TargetHp =< 0 of
        true ->
            SplitResult = maybe_boss_split(Target, OtherEnemies, maps:get(floor, State)),
            GoldDrop = enemy_gold_drop(Target, maps:get(floor, State)),
            {SplitResult, 1, GoldDrop, State};
        false ->
            {insert_at(Idx, Target#{hp => TargetHp}, OtherEnemies), 0, 0, State}
    end,
    State2 = State1#{
        enemies => NewEnemies,
        enemies_killed => maps:get(enemies_killed, State1) + Killed,
        gold => maps:get(gold, State1) + ExtraGold
    },
    State3 = enemy_counter_attack(NewEnemies, State2),
    case maps:get(phase, State3) of
        dead -> {ok, State3};
        _ ->
            case NewEnemies of
                [] -> trigger_room_clear(State3);
                _ -> {ok, State3}
            end
    end.

-spec handle_dodge(map()) -> {ok, map()}.
handle_dodge(State) ->
    Hero = maps:get(hero, State),
    Def = maps:get(defense, Hero),
    DodgeChance = min(80, 50 + Def),
    Roll = rand:uniform(100),
    case Roll =< DodgeChance of
        true ->
            {ok, State};
        false ->
            Enemies = maps:get(enemies, State),
            enemy_counter_attack(Enemies, State),
            {ok, State}
    end.

-spec handle_heal_potion(map()) -> {ok, map()} | {error, binary()}.
handle_heal_potion(State) ->
    Inventory = maps:get(inventory, State),
    case find_heal_potion(Inventory) of
        {ok, Potion, Rest} ->
            Hero = maps:get(hero, State),
            {heal, Amount} = maps:get(effect, Potion),
            Hp = min(maps:get(max_hp, Hero), maps:get(hp, Hero) + Amount),
            {ok, State#{hero => Hero#{hp => Hp}, inventory => Rest}};
        none ->
            {error, ~"no_heal_potion"}
    end.

-spec handle_interact(map()) -> {ok, map()}.
handle_interact(State) ->
    Hero = maps:get(hero, State),
    HX = trunc(maps:get(x, Hero)),
    HY = trunc(maps:get(y, Hero)),
    Features = maps:get(features, State),
    case find_interactable(HX, HY, Features) of
        {ok, Feature, Rest} ->
            interact_feature(Feature, Rest, State);
        none ->
            {ok, State}
    end.

-spec handle_use_item(binary(), map()) -> {ok, map()} | {error, binary()}.
handle_use_item(ItemId, State) ->
    Inventory = maps:get(inventory, State),
    case lists:splitwith(fun(I) -> maps:get(id, I) =/= ItemId end, Inventory) of
        {_, []} ->
            {error, ~"item_not_found"};
        {Before, [Item | After]} ->
            use_active_item(Item, Before ++ After, State)
    end.

%% --- Combat ---

-spec tick_combat(map()) -> {ok, map()}.
tick_combat(State) ->
    State1 = tick_boss_abilities(State),
    {ok, State1}.

-spec enemy_counter_attack([map()], map()) -> map().
enemy_counter_attack(Enemies, #{smoke_bomb_active := true} = State) ->
    State#{smoke_bomb_active => false, enemies => Enemies};
enemy_counter_attack(Enemies, State) ->
    Hero = maps:get(hero, State),
    Def = maps:get(defense, Hero),
    Darkness = maps:get(boss_modifier, State) =:= ~"darkness",
    BaseDmg = lists:sum([enemy_attack_dmg(E, Def) || E <- Enemies]),
    TotalDmg = case Darkness of
        true ->
            MissRoll = rand:uniform(100),
            case MissRoll =< 30 of true -> 0; false -> BaseDmg end;
        false ->
            BaseDmg
    end,
    HeroHp = maps:get(hp, Hero) - TotalDmg,
    case HeroHp =< 0 of
        true ->
            VoteConfig = crowd_crawl_votes:mercy(),
            State#{
                hero => Hero#{hp => 0},
                enemies => Enemies,
                phase => dead,
                vote_pending => VoteConfig
            };
        false ->
            State#{hero => Hero#{hp => HeroHp}, enemies => Enemies}
    end.

-spec enemy_attack_dmg(map(), integer()) -> integer().
enemy_attack_dmg(Enemy, HeroDef) ->
    Atk = maps:get(attack, Enemy, 3),
    AttacksPerTurn = maps:get(attacks_per_turn, Enemy, 1),
    Behavior = maps:get(behavior, Enemy, melee),
    BaseDmg = case Behavior of
        tank -> max(1, (Atk - HeroDef) div 2);
        _ -> max(1, Atk - HeroDef)
    end,
    IsBoss = maps:get(is_boss, Enemy, false),
    Ability = maps:get(boss_ability, Enemy, none),
    AbilityDmg = case {IsBoss, Ability} of
        {true, fire_breath} -> BaseDmg;
        {true, shadow_dodge} ->
            case rand:uniform(100) =< 50 of true -> BaseDmg; false -> 0 end;
        _ -> 0
    end,
    (BaseDmg + AbilityDmg) * AttacksPerTurn.

-spec tick_boss_abilities(map()) -> map().
tick_boss_abilities(#{enemies := Enemies} = State) ->
    case lists:search(fun(E) -> maps:get(is_boss, E, false) end, Enemies) of
        {value, Boss} ->
            maybe_summon_minions(Boss, State);
        false ->
            State
    end.

-spec maybe_summon_minions(map(), map()) -> map().
maybe_summon_minions(#{boss_ability := summon}, #{enemies := Enemies} = State) ->
    NonBoss = [E || E <- Enemies, maps:get(is_boss, E, false) =:= false],
    case length(NonBoss) < 3 of
        true ->
            Floor = maps:get(floor, State),
            Minion = #{
                name => ~"Skeleton Minion", hp => 15 + Floor * 3,
                attack => 4 + Floor, defense => 1,
                sprite => ~"skeleton", behavior => melee,
                x => 5 + rand:uniform(4), y => 2 + rand:uniform(4),
                id => erlang:unique_integer([positive]), is_boss => false
            },
            State#{enemies => Enemies ++ [Minion]};
        false ->
            State
    end;
maybe_summon_minions(_, State) ->
    State.

-spec maybe_boss_split(map(), [map()], pos_integer()) -> [map()].
maybe_boss_split(#{boss_ability := split, is_boss := true} = Boss, Others, Floor) ->
    Hp = max(20, maps:get(hp, Boss, 0) div 2),
    Atk = maps:get(attack, Boss) div 2,
    Copy1 = Boss#{
        hp => Hp, attack => Atk, name => ~"Hydra Head",
        id => erlang:unique_integer([positive]),
        boss_ability => none, is_boss => false,
        x => maps:get(x, Boss) - 1, y => maps:get(y, Boss)
    },
    Copy2 = Copy1#{
        id => erlang:unique_integer([positive]),
        x => maps:get(x, Boss) + 1
    },
    Scaled1 = crowd_crawl_enemies:scale_for_floor(Copy1, Floor),
    Scaled2 = crowd_crawl_enemies:scale_for_floor(Copy2, Floor),
    Others ++ [Scaled1, Scaled2];
maybe_boss_split(_, Others, _Floor) ->
    Others.

-spec move_melee_enemies(map()) -> map().
move_melee_enemies(#{enemies := Enemies, hero := Hero, phase := combat} = State) ->
    HX = maps:get(x, Hero),
    HY = maps:get(y, Hero),
    Moved = lists:map(fun(E) -> move_enemy_toward(E, HX, HY) end, Enemies),
    State#{enemies => Moved};
move_melee_enemies(State) ->
    State.

-spec move_enemy_toward(map(), float(), float()) -> map().
move_enemy_toward(#{behavior := melee, x := EX, y := EY} = Enemy, HX, HY) ->
    Dx = sign(HX - EX),
    Dy = sign(HY - EY),
    Enemy#{x => EX + Dx, y => EY + Dy};
move_enemy_toward(Enemy, _HX, _HY) ->
    Enemy.

-spec sign(number()) -> integer().
sign(N) when N > 0 -> 1;
sign(N) when N < 0 -> -1;
sign(_) -> 0.

%% --- Room Clear & Transitions ---

-spec trigger_room_clear(map()) -> {ok, map()}.
trigger_room_clear(#{rooms_until_boss := RUB} = State) ->
    RoomIdx = maps:get(room_index, State),
    Cleared = [RoomIdx | maps:get(cleared_rooms, State)],
    TotalCleared = maps:get(total_rooms_cleared, State) + 1,
    IsBossRoom = maps:get(is_boss_room, State),
    State1 = State#{cleared_rooms => Cleared, total_rooms_cleared => TotalCleared},
    State2 = maybe_boss_drop(IsBossRoom, State1),
    State3 = tick_buffs(State2),
    case IsBossRoom of
        true ->
            maybe_floor_transition(State3);
        false ->
            case RUB =< 1 of
                true ->
                    VoteConfig = crowd_crawl_votes:boss_modifier(),
                    {ok, State3#{
                        rooms_until_boss => ?ROOMS_PER_FLOOR,
                        phase => exploring,
                        vote_pending => VoteConfig
                    }};
                false ->
                    VoteConfig = crowd_crawl_votes:boon_pick(maps:get(seed, State3), RoomIdx),
                    {ok, State3#{
                        rooms_until_boss => RUB - 1,
                        phase => exploring,
                        vote_pending => VoteConfig
                    }}
            end
    end.

-spec maybe_floor_transition(map()) -> {ok, map()}.
maybe_floor_transition(State) ->
    Floor = maps:get(floor, State),
    NewFloor = Floor + 1,
    Hero = maps:get(hero, State),
    MaxHp = maps:get(max_hp, Hero),
    HealAmount = MaxHp div 4,
    HealedHp = min(MaxHp, maps:get(hp, Hero) + HealAmount),
    Hero1 = Hero#{hp => HealedHp},
    Seed = maps:get(seed, State),
    Room = crowd_crawl_dungeon:generate(Seed + NewFloor * 100, 0, NewFloor),
    {SpawnX, SpawnY} = maps:get(spawn, Room, {2, 2}),
    Hero2 = Hero1#{x => float(SpawnX), y => float(SpawnY)},
    {ok, State#{
        floor => NewFloor,
        room_index => 0,
        current_room => Room,
        enemies => maps:get(enemies, Room, []),
        features => maps:get(features, Room, []),
        hero => Hero2,
        is_boss_room => false,
        rooms_until_boss => ?ROOMS_PER_FLOOR,
        boss_modifier => none,
        phase => exploring
    }}.

-spec maybe_boss_drop(boolean(), map()) -> map().
maybe_boss_drop(true, State) ->
    Seed = maps:get(seed, State) + maps:get(floor, State) * 777,
    Boon = crowd_crawl_boons:legendary_drop(Seed),
    Hero = apply_boon(Boon, maps:get(hero, State)),
    Inventory = [Boon | maps:get(inventory, State)],
    Equipment = maybe_equip(Boon, maps:get(equipment, State)),
    Collected = maps:get(boons_collected, State) + 1,
    State#{hero => Hero, inventory => Inventory, equipment => Equipment, boons_collected => Collected};
maybe_boss_drop(false, State) ->
    State.

%% --- Room Transitions ---

-spec check_door(float(), float(), map()) -> map().
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

-spec check_enemy_aggro(map()) -> map().
check_enemy_aggro(#{phase := exploring, enemies := Enemies} = State) when length(Enemies) > 0 ->
    State#{phase => combat};
check_enemy_aggro(State) ->
    State.

-spec enter_next_room(binary(), map()) -> {ok, map()}.
enter_next_room(DoorId, State) ->
    Seed = maps:get(seed, State),
    Floor = maps:get(floor, State),
    RoomIdx = maps:get(room_index, State) + 1,
    DoorHash = erlang:phash2(DoorId),
    Room = crowd_crawl_dungeon:generate(Seed + DoorHash, RoomIdx, Floor),
    {SpawnX, SpawnY} = maps:get(spawn, Room, {2, 2}),
    Hero = maps:get(hero, State),
    IsBoss = maps:get(is_boss, Room, false),
    Enemies0 = maps:get(enemies, Room, []),
    Enemies = case IsBoss of
        true ->
            [Boss | Rest] = Enemies0,
            Modifier = maps:get(boss_modifier, State),
            {ModBoss, ExtraMinions} = crowd_crawl_enemies:apply_boss_modifier(Boss, Modifier),
            [ModBoss | Rest ++ ExtraMinions];
        false ->
            Enemies0
    end,
    {ok, State#{
        room_index => RoomIdx,
        current_room => Room,
        enemies => Enemies,
        features => maps:get(features, Room, []),
        hero => Hero#{x => float(SpawnX), y => float(SpawnY)},
        is_boss_room => IsBoss,
        phase => exploring,
        smoke_bomb_active => false
    }}.

%% --- Features ---

-spec check_feature_trigger(float(), float(), map()) -> map().
check_feature_trigger(X, Y, State) ->
    IX = trunc(X),
    IY = trunc(Y),
    Features = maps:get(features, State),
    check_feature_at(IX, IY, Features, [], State).

-spec check_feature_at(integer(), integer(), [map()], [map()], map()) -> map().
check_feature_at(_X, _Y, [], Acc, State) ->
    State#{features => lists:reverse(Acc)};
check_feature_at(X, Y, [#{type := trap, x := FX, y := FY, hidden := true, triggered := false} = F | Rest], Acc, State)
    when FX =:= X, FY =:= Y ->
    Dmg = 10 + rand:uniform(11),
    Hero = maps:get(hero, State),
    Hp = max(0, maps:get(hp, Hero) - Dmg),
    F1 = F#{hidden => false, triggered => true},
    State1 = State#{hero => Hero#{hp => Hp}},
    check_feature_at(X, Y, Rest, [F1 | Acc], State1);
check_feature_at(X, Y, [F | Rest], Acc, State) ->
    check_feature_at(X, Y, Rest, [F | Acc], State).

-spec find_interactable(integer(), integer(), [map()]) -> {ok, map(), [map()]} | none.
find_interactable(X, Y, Features) ->
    find_interactable(X, Y, Features, []).

-spec find_interactable(integer(), integer(), [map()], [map()]) -> {ok, map(), [map()]} | none.
find_interactable(_X, _Y, [], _Acc) ->
    none;
find_interactable(X, Y, [#{type := chest, x := FX, y := FY, opened := false} = F | Rest], Acc)
    when FX =:= X, FY =:= Y ->
    {ok, F, lists:reverse(Acc) ++ Rest};
find_interactable(X, Y, [#{type := fountain, x := FX, y := FY, used := false} = F | Rest], Acc)
    when FX =:= X, FY =:= Y ->
    {ok, F, lists:reverse(Acc) ++ Rest};
find_interactable(X, Y, [F | Rest], Acc) ->
    find_interactable(X, Y, Rest, [F | Acc]).

-spec interact_feature(map(), [map()], map()) -> {ok, map()}.
interact_feature(#{type := chest, loot_type := gold, floor := ChestFloor} = F, Rest, State) ->
    GoldAmount = (5 + rand:uniform(16)) * ChestFloor,
    Gold = maps:get(gold, State) + GoldAmount,
    {ok, State#{features => [F#{opened => true} | Rest], gold => Gold}};
interact_feature(#{type := chest, loot_type := item} = F, Rest, State) ->
    Seed = maps:get(seed, State) + maps:get(room_index, State) * 37,
    [Boon] = crowd_crawl_boons:random_by_rarity(Seed, 1),
    Hero = apply_boon(Boon, maps:get(hero, State)),
    Inventory = [Boon | maps:get(inventory, State)],
    Equipment = maybe_equip(Boon, maps:get(equipment, State)),
    Collected = maps:get(boons_collected, State) + 1,
    {ok, State#{
        features => [F#{opened => true} | Rest],
        hero => Hero, inventory => Inventory, equipment => Equipment,
        boons_collected => Collected
    }};
interact_feature(#{type := chest, loot_type := trap} = F, Rest, State) ->
    Dmg = 10 + rand:uniform(11),
    Hero = maps:get(hero, State),
    Hp = max(0, maps:get(hp, Hero) - Dmg),
    {ok, State#{features => [F#{opened => true} | Rest], hero => Hero#{hp => Hp}}};
interact_feature(#{type := fountain} = F, Rest, State) ->
    Hero = maps:get(hero, State),
    MaxHp = maps:get(max_hp, Hero),
    Hp = min(MaxHp, maps:get(hp, Hero) + MaxHp div 2),
    {ok, State#{features => [F#{used => true} | Rest], hero => Hero#{hp => Hp}}}.

%% --- Items ---

-spec use_active_item(map(), [map()], map()) -> {ok, map()} | {error, binary()}.
use_active_item(#{kind := active, effect := smoke_bomb}, NewInventory, State) ->
    {ok, State#{inventory => NewInventory, smoke_bomb_active => true}};
use_active_item(#{kind := active, effect := {heal, Amount}}, NewInventory, State) ->
    Hero = maps:get(hero, State),
    Hp = min(maps:get(max_hp, Hero), maps:get(hp, Hero) + Amount),
    {ok, State#{hero => Hero#{hp => Hp}, inventory => NewInventory}};
use_active_item(#{kind := active, effect := {rage, AtkBonus, Duration}}, NewInventory, State) ->
    Hero = maps:get(hero, State),
    Buffs = maps:get(buffs, Hero),
    NewBuff = #{type => rage, attack_bonus => AtkBonus, rooms_left => Duration},
    Hero1 = Hero#{
        attack => maps:get(attack, Hero) + AtkBonus,
        buffs => [NewBuff | Buffs]
    },
    {ok, State#{hero => Hero1, inventory => NewInventory}};
use_active_item(#{kind := passive}, _NewInventory, _State) ->
    {error, ~"not_active_item"};
use_active_item(_, _NewInventory, _State) ->
    {error, ~"unknown_item"}.

-spec find_heal_potion([map()]) -> {ok, map(), [map()]} | none.
find_heal_potion(Inventory) ->
    find_heal_potion(Inventory, []).

-spec find_heal_potion([map()], [map()]) -> {ok, map(), [map()]} | none.
find_heal_potion([], _Acc) ->
    none;
find_heal_potion([#{kind := active, effect := {heal, _}} = Item | Rest], Acc) ->
    {ok, Item, lists:reverse(Acc) ++ Rest};
find_heal_potion([Item | Rest], Acc) ->
    find_heal_potion(Rest, [Item | Acc]).

%% --- Boons & Equipment ---

-spec apply_boon(map(), map()) -> map().
apply_boon(#{kind := active}, Hero) ->
    Hero;
apply_boon(#{effect := {hp, Amount}}, Hero) ->
    Hp = min(maps:get(max_hp, Hero), maps:get(hp, Hero) + Amount),
    Hero#{hp => Hp};
apply_boon(#{effect := {heal, Amount}}, Hero) ->
    Hp = min(maps:get(max_hp, Hero), maps:get(hp, Hero) + Amount),
    Hero#{hp => Hp};
apply_boon(#{effect := {attack, Amount}}, Hero) ->
    Hero#{attack => maps:get(attack, Hero) + Amount};
apply_boon(#{effect := {defense, Amount}}, Hero) ->
    Hero#{defense => maps:get(defense, Hero) + Amount};
apply_boon(#{effect := {max_hp, Amount}}, Hero) ->
    MaxHp = maps:get(max_hp, Hero) + Amount,
    Hero#{max_hp => MaxHp, hp => maps:get(hp, Hero) + Amount};
apply_boon(#{effect := {multi, Effects}}, Hero) ->
    lists:foldl(fun({Stat, Amt}, H) -> apply_stat(Stat, Amt, H) end, Hero, Effects);
apply_boon(_, Hero) ->
    Hero.

-spec apply_stat(atom(), integer(), map()) -> map().
apply_stat(attack, Amount, Hero) ->
    Hero#{attack => maps:get(attack, Hero) + Amount};
apply_stat(defense, Amount, Hero) ->
    Hero#{defense => maps:get(defense, Hero) + Amount};
apply_stat(max_hp, Amount, Hero) ->
    MaxHp = maps:get(max_hp, Hero) + Amount,
    Hero#{max_hp => MaxHp, hp => maps:get(hp, Hero) + Amount};
apply_stat(hp, Amount, Hero) ->
    Hp = min(maps:get(max_hp, Hero), maps:get(hp, Hero) + Amount),
    Hero#{hp => Hp};
apply_stat(_, _, Hero) ->
    Hero.

-spec maybe_equip(map(), map()) -> map().
maybe_equip(#{slot := Slot} = _Boon, Equipment) when
    Slot =:= weapon; Slot =:= armor; Slot =:= accessory
->
    Equipment#{Slot => _Boon};
maybe_equip(_, Equipment) ->
    Equipment.

-spec tick_buffs(map()) -> map().
tick_buffs(State) ->
    Hero = maps:get(hero, State),
    Buffs = maps:get(buffs, Hero),
    {ActiveBuffs, ExpiredBuffs} = lists:partition(
        fun(#{rooms_left := RL}) -> RL > 1 end,
        Buffs
    ),
    Ticked = [B#{rooms_left => maps:get(rooms_left, B) - 1} || B <- ActiveBuffs],
    AtkLoss = lists:sum([maps:get(attack_bonus, B, 0) || B <- ExpiredBuffs]),
    Hero1 = Hero#{
        buffs => Ticked,
        attack => max(1, maps:get(attack, Hero) - AtkLoss)
    },
    State#{hero => Hero1}.

%% --- Scoring ---

-spec calculate_score(map()) -> integer().
calculate_score(State) ->
    FloorsCleared = maps:get(floor, State) - 1,
    RoomsCleared = maps:get(total_rooms_cleared, State),
    Killed = maps:get(enemies_killed, State),
    Gold = maps:get(gold, State),
    FloorsCleared * 100 + RoomsCleared * 10 + Killed * 5 + Gold.

-spec build_run_result(binary(), map()) -> map().
build_run_result(Status, State) ->
    Now = erlang:system_time(second),
    StartTime = maps:get(start_time, State),
    #{
        status => Status,
        score => calculate_score(State),
        run_stats => #{
            floors_cleared => maps:get(floor, State) - 1,
            rooms_cleared => maps:get(total_rooms_cleared, State),
            enemies_killed => maps:get(enemies_killed, State),
            gold_collected => maps:get(gold, State),
            time_survived => Now - StartTime,
            boons_collected => maps:get(boons_collected, State)
        }
    }.

%% --- Helpers ---

-spec direction_delta(binary()) -> {float(), float()}.
direction_delta(~"up") -> {0.0, -1.0};
direction_delta(~"down") -> {0.0, 1.0};
direction_delta(~"left") -> {-1.0, 0.0};
direction_delta(~"right") -> {1.0, 0.0};
direction_delta(_) -> {0.0, 0.0}.

-spec room_render_data(map()) -> map().
sanitize_hero(Hero) ->
    Base = maps:with([hp, max_hp, attack, defense, x, y], Hero),
    Buffs = [atom_to_binary(B) || B <- maps:get(buffs, Hero, []), is_atom(B)],
    Base#{buffs => Buffs}.

sanitize_enemy(E) ->
    Base = maps:without([boss_ability, darkness, attacks_per_turn], E),
    Behavior = maps:get(behavior, Base, melee),
    Base#{behavior => atom_to_binary(Behavior)}.

sanitize_equipment(Equipment) when is_map(Equipment) ->
    maps:map(
        fun(_Slot, none) -> ~"none";
           (_Slot, Item) when is_map(Item) -> maps:with([id, label, rarity], Item);
           (_Slot, V) -> V
        end,
        Equipment
    );
sanitize_equipment(_) -> #{}.

room_render_data(Room) ->
    maps:with([tiles, width, height, doors, type, features, is_boss], Room).

-spec visible_features([map()]) -> [map()].
visible_features(Features) ->
    [visible_feature(F) || F <- Features].

-spec visible_feature(map()) -> map().
visible_feature(#{type := trap, hidden := true} = _F) ->
    #{type => ~"unknown", x => -1, y => -1};
visible_feature(F) ->
    maps:without([loot_type, floor], F).

-spec enemy_gold_drop(map(), pos_integer()) -> integer().
enemy_gold_drop(Enemy, Floor) ->
    IsBoss = maps:get(is_boss, Enemy, false),
    Base = case IsBoss of
        true -> 10 + rand:uniform(20);
        false -> 1 + rand:uniform(10)
    end,
    Base * Floor.

-spec clamp(integer(), integer(), integer()) -> integer().
clamp(Val, Min, Max) ->
    max(Min, min(Max, Val)).

-spec extract_at(non_neg_integer(), [T]) -> {T, [T]} when T :: map().
extract_at(0, [H | T]) -> {H, T};
extract_at(N, [H | T]) ->
    {Item, Rest} = extract_at(N - 1, T),
    {Item, [H | Rest]}.

-spec insert_at(non_neg_integer(), T, [T]) -> [T] when T :: map().
insert_at(0, Item, List) -> [Item | List];
insert_at(N, Item, [H | T]) -> [H | insert_at(N - 1, Item, T)].
