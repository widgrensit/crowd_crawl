-module(crowd_crawl_boons).

-export([all/0, get/1, random_options/2]).

-spec all() -> [map()].
all() ->
    [
        #{id => ~"heal_potion", label => ~"Healing Potion (+25 HP)", tarot => ~"temperance", effect => {hp, 25}},
        #{id => ~"sharp_blade", label => ~"Sharp Blade (+3 ATK)", tarot => ~"justice", effect => {attack, 3}},
        #{id => ~"iron_shield", label => ~"Iron Shield (+2 DEF)", tarot => ~"emperor", effect => {defense, 2}},
        #{id => ~"vitality_ring", label => ~"Vitality Ring (+15 Max HP)", tarot => ~"empress", effect => {max_hp, 15}},
        #{id => ~"war_hammer", label => ~"War Hammer (+5 ATK)", tarot => ~"strength", effect => {attack, 5}},
        #{id => ~"mystic_robe", label => ~"Mystic Robe (+3 DEF)", tarot => ~"priestess", effect => {defense, 3}},
        #{id => ~"elixir", label => ~"Elixir (+50 HP)", tarot => ~"star", effect => {hp, 50}},
        #{id => ~"berserker_axe", label => ~"Berserker Axe (+8 ATK, -2 DEF)", tarot => ~"devil", effect => {attack, 8}},
        #{id => ~"holy_water", label => ~"Holy Water (+30 HP)", tarot => ~"hierophant", effect => {hp, 30}},
        #{id => ~"lucky_charm", label => ~"Lucky Charm (+1 ATK, +1 DEF)", tarot => ~"fortune", effect => {attack, 1}},
        #{id => ~"phoenix_feather", label => ~"Phoenix Feather (+20 Max HP)", tarot => ~"judgment", effect => {max_hp, 20}},
        #{id => ~"shadow_cloak", label => ~"Shadow Cloak (+4 DEF)", tarot => ~"hermit", effect => {defense, 4}},
        #{id => ~"magic_staff", label => ~"Magic Staff (+4 ATK)", tarot => ~"magician", effect => {attack, 4}}
    ].

-spec get(binary()) -> map().
get(BoonId) ->
    case lists:keyfind(BoonId, 1, [{maps:get(id, B), B} || B <- all()]) of
        {_, Boon} -> Boon;
        false -> #{id => BoonId, label => ~"Unknown", tarot => ~"fool", effect => none}
    end.

-spec random_options(integer(), pos_integer()) -> [map()].
random_options(Seed, Count) ->
    S = rand:seed_s(exsss, {Seed, Seed * 11, Seed * 17}),
    All = all(),
    pick_n(All, Count, S, []).

pick_n(_All, 0, _S, Acc) ->
    lists:reverse(Acc);
pick_n([], _N, _S, Acc) ->
    lists:reverse(Acc);
pick_n(All, N, S, Acc) ->
    {Idx, S1} = rand:uniform_s(length(All), S),
    Picked = lists:nth(Idx, All),
    Rest = All -- [Picked],
    pick_n(Rest, N - 1, S1, [Picked | Acc]).
