-module(crowd_crawl_dungeon).

-export([generate/2, walkable/3, door_at/3]).

-spec generate(integer(), integer()) -> map().
generate(Seed, RoomIdx) ->
    S = rand:seed_s(exsss, {Seed, Seed * 7 + RoomIdx, Seed * 13 + RoomIdx * 3}),
    {Type, S1} = pick_room_type(S, RoomIdx),
    {Tiles, Width, Height, S2} = generate_tiles(Type, S1),
    {Doors, S3} = generate_doors(Type, Width, Height, S2),
    {Enemies, _S4} = generate_enemies(S3, RoomIdx),
    #{
        type => Type,
        tiles => Tiles,
        width => Width,
        height => Height,
        doors => Doors,
        enemies => Enemies,
        room_index => RoomIdx
    }.

-spec walkable(map(), float(), float()) -> boolean().
walkable(#{tiles := Tiles, width := W, height := H}, X, Y) ->
    IX = trunc(X),
    IY = trunc(Y),
    IX >= 0 andalso IX < W andalso IY >= 0 andalso IY < H andalso
        tile_at(Tiles, IX, IY) =:= floor.

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

pick_room_type(S, RoomIdx) when RoomIdx rem 5 =:= 4 ->
    {boss, S};
pick_room_type(S, _RoomIdx) ->
    Types = [square, rectangle, lshape, corridor],
    {Idx, S1} = rand:uniform_s(length(Types), S),
    {lists:nth(Idx, Types), S1}.

generate_tiles(square, S) -> {make_room(8, 8), 8, 8, S};
generate_tiles(rectangle, S) -> {make_room(10, 6), 10, 6, S};
generate_tiles(lshape, S) ->
    Tiles = block_region(make_room(10, 8), 6, 0, 4, 4),
    {Tiles, 10, 8, S};
generate_tiles(corridor, S) -> {make_room(12, 4), 12, 4, S};
generate_tiles(boss, S) -> {make_room(12, 10), 12, 10, S}.

make_room(W, H) ->
    [[case X =:= 0 orelse X =:= W - 1 orelse Y =:= 0 orelse Y =:= H - 1 of
        true -> wall;
        false -> floor
    end || X <- lists:seq(0, W - 1)] || Y <- lists:seq(0, H - 1)].

block_region(Tiles, StartX, StartY, BlockW, BlockH) ->
    W = length(hd(Tiles)),
    H = length(Tiles),
    [[case X >= StartX andalso X < StartX + BlockW andalso
          Y >= StartY andalso Y < StartY + BlockH of
        true -> wall;
        false -> tile_at(Tiles, X, Y)
    end || X <- lists:seq(0, W - 1)] || Y <- lists:seq(0, H - 1)].

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

generate_enemies(S, RoomIdx) ->
    Difficulty = 1 + RoomIdx div 3,
    {Count, S1} = rand:uniform_s(Difficulty + 1, S),
    EnemyCount = max(1, Count),
    Types = crowd_crawl_enemies:types(),
    {Enemies, S2} = lists:foldl(
        fun(_, {Acc, Si}) ->
            {Idx, Si1} = rand:uniform_s(length(Types), Si),
            Base = lists:nth(Idx, Types),
            Scaled = scale_enemy(Base, Difficulty),
            {[Scaled | Acc], Si1}
        end,
        {[], S1},
        lists:seq(1, EnemyCount)
    ),
    {Enemies, S2}.

scale_enemy(Enemy, Difficulty) ->
    Hp = maps:get(hp, Enemy) + (Difficulty - 1) * 5,
    Atk = maps:get(attack, Enemy) + (Difficulty - 1) * 2,
    Enemy#{hp => Hp, attack => Atk}.

tile_at(Tiles, X, Y) ->
    lists:nth(X + 1, lists:nth(Y + 1, Tiles)).
