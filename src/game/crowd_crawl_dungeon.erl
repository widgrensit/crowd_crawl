-module(crowd_crawl_dungeon).

-export([generate/3, walkable/3, door_at/3]).

-spec generate(integer(), integer(), pos_integer()) -> map().
generate(Seed, RoomIdx, Floor) ->
    S = rand:seed_s(exsss, {Seed, Seed * 7 + RoomIdx, Seed * 13 + RoomIdx * 3}),
    IsBoss = is_boss_room(RoomIdx),
    {Type, S1} = pick_room_type(S, IsBoss),
    {Tiles, Width, Height, S2} = generate_tiles(Type, S1),
    {Doors, S3} = generate_doors(Type, Width, Height, S2),
    {Enemies, S4} = generate_enemies(S3, RoomIdx, Floor, IsBoss),
    {Features, _S5} = generate_features(S4, Tiles, Width, Height, Floor, IsBoss),
    SpawnPos = find_floor_tile(Tiles, Width, Height, 2, 2),
    #{
        type => Type,
        tiles => Tiles,
        width => Width,
        height => Height,
        doors => Doors,
        enemies => Enemies,
        features => Features,
        room_index => RoomIdx,
        spawn => SpawnPos,
        is_boss => IsBoss
    }.

-spec walkable(map(), float(), float()) -> boolean().
walkable(#{tiles := Tiles, width := W, height := H, doors := Doors}, X, Y) ->
    IX = trunc(X),
    IY = trunc(Y),
    InBounds = IX >= 0 andalso IX < W andalso IY >= 0 andalso IY < H,
    InBounds andalso (tile_at(Tiles, IX, IY) =:= floor orelse is_door_pos(Doors, IX, IY)).

-spec door_at(map(), float(), float()) -> false | {door, [map()]}.
door_at(#{doors := Doors}, X, Y) ->
    IX = trunc(X),
    IY = trunc(Y),
    Matching = [D || D <- Doors, maps:get(x, D) =:= IX, maps:get(y, D) =:= IY],
    case Matching of
        [] -> false;
        _ -> {door, Matching}
    end.

%% --- Internal ---

-spec is_boss_room(integer()) -> boolean().
is_boss_room(RoomIdx) ->
    RoomIdx > 0 andalso RoomIdx rem 5 =:= 0.

-spec is_door_pos([map()], integer(), integer()) -> boolean().
is_door_pos([], _X, _Y) -> false;
is_door_pos([#{x := DX, y := DY} | _], X, Y) when DX =:= X, DY =:= Y -> true;
is_door_pos([_ | Rest], X, Y) -> is_door_pos(Rest, X, Y).

-spec pick_room_type(rand:state(), boolean()) -> {atom(), rand:state()}.
pick_room_type(S, true) ->
    {boss, S};
pick_room_type(S, false) ->
    Types = [square, rectangle, lshape, corridor, cross, hall, chamber],
    {Idx, S1} = rand:uniform_s(length(Types), S),
    {lists:nth(Idx, Types), S1}.

-spec generate_tiles(atom(), rand:state()) -> {list(), integer(), integer(), rand:state()}.
generate_tiles(square, S) -> {make_room(8, 8), 8, 8, S};
generate_tiles(rectangle, S) -> {make_room(10, 6), 10, 6, S};
generate_tiles(lshape, S) ->
    Tiles = block_region(make_room(10, 8), 6, 0, 4, 4),
    {Tiles, 10, 8, S};
generate_tiles(corridor, S) -> {make_room(12, 4), 12, 4, S};
generate_tiles(cross, S) ->
    T0 = make_room(10, 10),
    T1 = block_region(T0, 0, 0, 3, 3),
    T2 = block_region(T1, 7, 0, 3, 3),
    T3 = block_region(T2, 0, 7, 3, 3),
    T4 = block_region(T3, 7, 7, 3, 3),
    {T4, 10, 10, S};
generate_tiles(hall, S) ->
    T0 = make_room(14, 6),
    T1 = set_tile(T0, 4, 2, wall),
    T2 = set_tile(T1, 4, 3, wall),
    T3 = set_tile(T2, 9, 2, wall),
    T4 = set_tile(T3, 9, 3, wall),
    {T4, 14, 6, S};
generate_tiles(chamber, S) ->
    T0 = make_room(8, 8),
    T1 = set_tile(T0, 3, 3, wall),
    T2 = set_tile(T1, 4, 3, wall),
    T3 = set_tile(T2, 3, 4, wall),
    T4 = set_tile(T3, 4, 4, wall),
    {T4, 8, 8, S};
generate_tiles(boss, S) -> {make_room(12, 10), 12, 10, S}.

-spec make_room(pos_integer(), pos_integer()) -> list().
make_room(W, H) ->
    [[case X =:= 0 orelse X =:= W - 1 orelse Y =:= 0 orelse Y =:= H - 1 of
        true -> wall;
        false -> floor
    end || X <- lists:seq(0, W - 1)] || Y <- lists:seq(0, H - 1)].

-spec block_region(list(), integer(), integer(), integer(), integer()) -> list().
block_region(Tiles, StartX, StartY, BlockW, BlockH) ->
    W = length(hd(Tiles)),
    H = length(Tiles),
    [[case X >= StartX andalso X < StartX + BlockW andalso
          Y >= StartY andalso Y < StartY + BlockH of
        true -> wall;
        false -> tile_at(Tiles, X, Y)
    end || X <- lists:seq(0, W - 1)] || Y <- lists:seq(0, H - 1)].

-spec generate_doors(atom(), integer(), integer(), rand:state()) -> {[map()], rand:state()}.
generate_doors(boss, W, H, S) ->
    {[#{id => ~"boss_exit", label => ~"The Abyss", tarot => ~"tower", x => W div 2, y => H - 1}], S};
generate_doors(corridor, W, _H, S) ->
    {[#{id => ~"end", label => ~"Continue", tarot => ~"chariot", x => W - 1, y => 2}], S};
generate_doors(_Type, W, H, S) ->
    {Count, S1} = rand:uniform_s(2, S),
    DoorCount = Count + 1,
    Tarots = [~"fool", ~"magician", ~"priestess", ~"empress", ~"emperor",
              ~"hermit", ~"fortune", ~"star", ~"temperance", ~"judgment"],
    Labels = [~"Dark Passage", ~"Lit Hallway", ~"Crumbling Path",
              ~"Hidden Door", ~"Grand Archway", ~"Narrow Crack"],
    Positions = [{W - 1, H div 2}, {W div 2, 0}, {0, H div 2}],
    Doors = lists:map(
        fun(I) ->
            {PX, PY} = lists:nth(min(I, length(Positions)), Positions),
            {TI, S2} = rand:uniform_s(length(Tarots), S1),
            {LI, _S3} = rand:uniform_s(length(Labels), S2),
            #{
                id => iolist_to_binary([~"door_", integer_to_binary(I)]),
                label => lists:nth(LI, Labels),
                tarot => lists:nth(TI, Tarots),
                x => PX,
                y => PY
            }
        end,
        lists:seq(1, min(DoorCount, length(Positions)))
    ),
    {Doors, S1}.

-spec generate_enemies(rand:state(), integer(), pos_integer(), boolean()) -> {[map()], rand:state()}.
generate_enemies(S, _RoomIdx, Floor, true) ->
    generate_boss(S, Floor);
generate_enemies(S, RoomIdx, Floor, false) ->
    Difficulty = 1 + RoomIdx div 3,
    {Count, S1} = rand:uniform_s(Difficulty + 1, S),
    EnemyCount = max(1, Count),
    Types = crowd_crawl_enemies:types(),
    {Enemies, S2} = lists:foldl(
        fun(I, {Acc, Si}) ->
            {Idx, Si1} = rand:uniform_s(length(Types), Si),
            Base = lists:nth(Idx, Types),
            Scaled = crowd_crawl_enemies:scale_for_floor(scale_enemy(Base, Difficulty), Floor),
            EX = 3 + (I - 1) * 2,
            EY = 1 + ((I - 1) rem 2),
            Enemy = Scaled#{x => EX, y => EY, id => I},
            {[Enemy | Acc], Si1}
        end,
        {[], S1},
        lists:seq(1, EnemyCount)
    ),
    {Enemies, S2}.

-spec generate_boss(rand:state(), pos_integer()) -> {[map()], rand:state()}.
generate_boss(S, Floor) ->
    Bosses = crowd_crawl_enemies:boss_types(),
    {Idx, S1} = rand:uniform_s(length(Bosses), S),
    Base = lists:nth(Idx, Bosses),
    Scaled = crowd_crawl_enemies:scale_for_floor(Base, Floor),
    Boss = Scaled#{x => 6, y => 3, id => 0, is_boss => true},
    {[Boss], S1}.

-spec generate_features(rand:state(), list(), integer(), integer(), pos_integer(), boolean()) ->
    {[map()], rand:state()}.
generate_features(S, _Tiles, _W, _H, _Floor, true) ->
    {[], S};
generate_features(S, Tiles, W, H, Floor, false) ->
    {ChestCount, S1} = rand:uniform_s(3, S),
    {Features, S2} = lists:foldl(
        fun(I, {Acc, Si}) ->
            {FX, FY, Si1} = find_random_floor(Si, Tiles, W, H),
            {LootRoll, Si2} = rand:uniform_s(100, Si1),
            LootType = loot_type(LootRoll),
            Feature = #{
                type => chest,
                x => FX, y => FY,
                opened => false,
                loot_type => LootType,
                id => I,
                floor => Floor
            },
            {[Feature | Acc], Si2}
        end,
        {[], S1},
        lists:seq(1, ChestCount)
    ),
    {TrapCount, S3} = rand:uniform_s(2, S2),
    {Features2, S4} = lists:foldl(
        fun(I, {Acc, Si}) ->
            {FX, FY, Si1} = find_random_floor(Si, Tiles, W, H),
            Trap = #{type => trap, x => FX, y => FY, hidden => true, triggered => false, id => 100 + I},
            {[Trap | Acc], Si1}
        end,
        {Features, S3},
        lists:seq(1, TrapCount)
    ),
    {FountainRoll, S5} = rand:uniform_s(100, S4),
    case FountainRoll =< 30 of
        true ->
            {FX, FY, S6} = find_random_floor(S5, Tiles, W, H),
            Fountain = #{type => fountain, x => FX, y => FY, used => false, id => 200},
            {[Fountain | Features2], S6};
        false ->
            {Features2, S5}
    end.

-spec loot_type(integer()) -> atom().
loot_type(Roll) when Roll =< 50 -> gold;
loot_type(Roll) when Roll =< 85 -> item;
loot_type(_) -> trap.

-spec find_random_floor(rand:state(), list(), integer(), integer()) ->
    {integer(), integer(), rand:state()}.
find_random_floor(S, Tiles, W, H) ->
    {X, S1} = rand:uniform_s(W - 2, S),
    {Y, S2} = rand:uniform_s(H - 2, S1),
    case tile_at(Tiles, X, Y) of
        floor -> {X, Y, S2};
        _ -> find_random_floor(S2, Tiles, W, H)
    end.

-spec scale_enemy(map(), integer()) -> map().
scale_enemy(Enemy, Difficulty) ->
    Hp = maps:get(hp, Enemy) + (Difficulty - 1) * 5,
    Atk = maps:get(attack, Enemy) + (Difficulty - 1) * 2,
    Enemy#{hp => Hp, attack => Atk}.

-spec tile_at(list(), integer(), integer()) -> atom().
tile_at(Tiles, X, Y) ->
    lists:nth(X + 1, lists:nth(Y + 1, Tiles)).

-spec find_floor_tile(list(), integer(), integer(), integer(), integer()) -> {integer(), integer()}.
find_floor_tile(Tiles, W, H, StartX, StartY) ->
    case is_floor(Tiles, W, H, StartX, StartY) of
        true -> {StartX, StartY};
        false -> find_floor_spiral(Tiles, W, H, StartX, StartY, 1)
    end.

-spec find_floor_spiral(list(), integer(), integer(), integer(), integer(), integer()) ->
    {integer(), integer()}.
find_floor_spiral(Tiles, W, H, CX, CY, Radius) when Radius < W + H ->
    Candidates = [{CX + DX, CY + DY} ||
        DX <- lists:seq(-Radius, Radius),
        DY <- lists:seq(-Radius, Radius),
        abs(DX) =:= Radius orelse abs(DY) =:= Radius],
    case lists:search(fun({X, Y}) -> is_floor(Tiles, W, H, X, Y) end, Candidates) of
        {value, Pos} -> Pos;
        false -> find_floor_spiral(Tiles, W, H, CX, CY, Radius + 1)
    end;
find_floor_spiral(_Tiles, _W, _H, CX, CY, _Radius) ->
    {CX, CY}.

-spec is_floor(list(), integer(), integer(), integer(), integer()) -> boolean().
is_floor(Tiles, W, H, X, Y) ->
    X > 0 andalso X < W - 1 andalso Y > 0 andalso Y < H - 1 andalso
        tile_at(Tiles, X, Y) =:= floor.

-spec set_tile(list(), integer(), integer(), atom()) -> list().
set_tile(Tiles, X, Y, Value) ->
    Row = lists:nth(Y + 1, Tiles),
    NewRow = list_set(X + 1, Value, Row),
    list_set(Y + 1, NewRow, Tiles).

-spec list_set(pos_integer(), term(), list()) -> list().
list_set(1, Value, [_ | Rest]) -> [Value | Rest];
list_set(N, Value, [H | Rest]) -> [H | list_set(N - 1, Value, Rest)].
