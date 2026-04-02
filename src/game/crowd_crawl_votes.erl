-module(crowd_crawl_votes).

-export([boon_pick/2, path_choice/1, buff_nerf/0, boss_modifier/0, mercy/0]).

-spec boon_pick(integer(), integer()) -> map().
boon_pick(Seed, RoomIdx) ->
    Boons = crowd_crawl_boons:random_options(Seed + RoomIdx, 3),
    #{
        template => ~"boon_pick",
        options => [#{id => maps:get(id, B), label => maps:get(label, B), tarot => maps:get(tarot, B)} || B <- Boons],
        window_ms => 15000,
        method => ~"plurality",
        visibility => ~"live"
    }.

-spec path_choice([map()]) -> map().
path_choice(Doors) ->
    #{
        template => ~"path_choice",
        options => [#{id => maps:get(id, D), label => maps:get(label, D), tarot => maps:get(tarot, D)} || D <- Doors],
        window_ms => 20000,
        method => ~"approval",
        visibility => ~"live"
    }.

-spec buff_nerf() -> map().
buff_nerf() ->
    #{
        template => ~"buff_nerf",
        options => [
            #{id => ~"buff", label => ~"Bless the Hero (+2 ATK)", tarot => ~"sun"},
            #{id => ~"nerf", label => ~"Curse the Hero (tougher enemies)", tarot => ~"devil"}
        ],
        window_ms => 15000,
        method => ~"weighted",
        visibility => ~"live"
    }.

-spec boss_modifier() -> map().
boss_modifier() ->
    #{
        template => ~"boss_modifier",
        options => [
            #{id => ~"double_hp", label => ~"Double Boss HP", tarot => ~"strength"},
            #{id => ~"minions", label => ~"Summon Minions", tarot => ~"tower"},
            #{id => ~"darkness", label => ~"Lights Out", tarot => ~"moon"},
            #{id => ~"speed", label => ~"Speed Boost", tarot => ~"chariot"}
        ],
        window_ms => 25000,
        method => ~"ranked",
        visibility => ~"hidden"
    }.

-spec mercy() -> map().
mercy() ->
    #{
        template => ~"mercy_vote",
        options => [
            #{id => ~"revive", label => ~"Revive the Hero!", tarot => ~"sun"},
            #{id => ~"perish", label => ~"Let Them Fall", tarot => ~"death"}
        ],
        window_ms => 20000,
        method => ~"plurality",
        visibility => ~"live",
        require_supermajority => true,
        supermajority => 0.75
    }.
