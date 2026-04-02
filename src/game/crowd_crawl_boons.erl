-module(crowd_crawl_boons).

-export([all/0, get/1, random_options/2, random_by_rarity/2, legendary_drop/1]).

-spec all() -> [map()].
all() ->
    common_boons() ++ rare_boons() ++ legendary_boons().

-spec common_boons() -> [map()].
common_boons() ->
    [
        #{id => ~"heal_potion", label => ~"Healing Potion (30 HP)", tarot => ~"temperance",
          kind => active, effect => {heal, 30}, rarity => common},
        #{id => ~"sharp_blade", label => ~"Sharp Blade (+3 ATK)", tarot => ~"justice",
          kind => passive, effect => {attack, 3}, rarity => common, slot => weapon},
        #{id => ~"iron_shield", label => ~"Iron Shield (+2 DEF)", tarot => ~"emperor",
          kind => passive, effect => {defense, 2}, rarity => common, slot => armor},
        #{id => ~"vitality_ring", label => ~"Vitality Ring (+15 Max HP)", tarot => ~"empress",
          kind => passive, effect => {max_hp, 15}, rarity => common, slot => accessory},
        #{id => ~"smoke_bomb", label => ~"Smoke Bomb (skip counter)", tarot => ~"moon",
          kind => active, effect => smoke_bomb, rarity => common},
        #{id => ~"small_heal", label => ~"Minor Salve (+15 HP)", tarot => ~"star",
          kind => active, effect => {heal, 15}, rarity => common},
        #{id => ~"wooden_club", label => ~"Wooden Club (+2 ATK)", tarot => ~"fool",
          kind => passive, effect => {attack, 2}, rarity => common, slot => weapon},
        #{id => ~"leather_cap", label => ~"Leather Cap (+1 DEF)", tarot => ~"hermit",
          kind => passive, effect => {defense, 1}, rarity => common, slot => armor},
        #{id => ~"lucky_coin", label => ~"Lucky Coin (+1 ATK, +1 DEF)", tarot => ~"fortune",
          kind => passive, effect => {multi, [{attack, 1}, {defense, 1}]}, rarity => common},
        #{id => ~"bread_loaf", label => ~"Bread Loaf (+20 HP)", tarot => ~"hierophant",
          kind => active, effect => {heal, 20}, rarity => common}
    ].

-spec rare_boons() -> [map()].
rare_boons() ->
    [
        #{id => ~"rage_potion", label => ~"Rage Potion (+5 ATK for 3 rooms)", tarot => ~"strength",
          kind => active, effect => {rage, 5, 3}, rarity => rare},
        #{id => ~"war_hammer", label => ~"War Hammer (+5 ATK)", tarot => ~"strength",
          kind => passive, effect => {attack, 5}, rarity => rare, slot => weapon},
        #{id => ~"mystic_robe", label => ~"Mystic Robe (+4 DEF)", tarot => ~"priestess",
          kind => passive, effect => {defense, 4}, rarity => rare, slot => armor},
        #{id => ~"elixir", label => ~"Elixir (+50 HP)", tarot => ~"star",
          kind => active, effect => {heal, 50}, rarity => rare},
        #{id => ~"phoenix_feather", label => ~"Phoenix Feather (+20 Max HP)", tarot => ~"judgment",
          kind => passive, effect => {max_hp, 20}, rarity => rare, slot => accessory},
        #{id => ~"shadow_cloak", label => ~"Shadow Cloak (+5 DEF)", tarot => ~"hermit",
          kind => passive, effect => {defense, 5}, rarity => rare, slot => armor},
        #{id => ~"magic_staff", label => ~"Magic Staff (+4 ATK)", tarot => ~"magician",
          kind => passive, effect => {attack, 4}, rarity => rare, slot => weapon},
        #{id => ~"amulet_of_vigor", label => ~"Amulet of Vigor (+25 Max HP)", tarot => ~"sun",
          kind => passive, effect => {max_hp, 25}, rarity => rare, slot => accessory},
        #{id => ~"silver_dagger", label => ~"Silver Dagger (+6 ATK)", tarot => ~"justice",
          kind => passive, effect => {attack, 6}, rarity => rare, slot => weapon},
        #{id => ~"iron_fortress", label => ~"Iron Fortress (+6 DEF)", tarot => ~"tower",
          kind => passive, effect => {defense, 6}, rarity => rare, slot => armor}
    ].

-spec legendary_boons() -> [map()].
legendary_boons() ->
    [
        #{id => ~"berserker_axe", label => ~"Berserker Axe (+10 ATK, -3 DEF)", tarot => ~"devil",
          kind => passive, effect => {multi, [{attack, 10}, {defense, -3}]}, rarity => legendary, slot => weapon},
        #{id => ~"holy_grail", label => ~"Holy Grail (+40 Max HP, +3 DEF)", tarot => ~"world",
          kind => passive, effect => {multi, [{max_hp, 40}, {defense, 3}]}, rarity => legendary, slot => accessory},
        #{id => ~"excalibur", label => ~"Excalibur (+8 ATK, +3 DEF)", tarot => ~"chariot",
          kind => passive, effect => {multi, [{attack, 8}, {defense, 3}]}, rarity => legendary, slot => weapon},
        #{id => ~"dragon_scale", label => ~"Dragon Scale (+10 DEF)", tarot => ~"emperor",
          kind => passive, effect => {defense, 10}, rarity => legendary, slot => armor},
        #{id => ~"soul_gem", label => ~"Soul Gem (+5 ATK, +30 Max HP)", tarot => ~"death",
          kind => passive, effect => {multi, [{attack, 5}, {max_hp, 30}]}, rarity => legendary, slot => accessory}
    ].

-spec get(binary()) -> map().
get(BoonId) ->
    case lists:keyfind(BoonId, 1, [{maps:get(id, B), B} || B <- all()]) of
        {_, Boon} -> Boon;
        false -> #{id => BoonId, label => ~"Unknown", tarot => ~"fool", kind => passive, effect => none, rarity => common}
    end.

-spec random_options(integer(), pos_integer()) -> [map()].
random_options(Seed, Count) ->
    S = rand:seed_s(exsss, {Seed, Seed * 11, Seed * 17}),
    Pool = common_boons() ++ rare_boons(),
    pick_n(Pool, Count, S, []).

-spec random_by_rarity(integer(), pos_integer()) -> [map()].
random_by_rarity(Seed, Count) ->
    S = rand:seed_s(exsss, {Seed, Seed * 11, Seed * 17}),
    {Roll, S1} = rand:uniform_s(100, S),
    Pool = case Roll of
        R when R =< 60 -> common_boons();
        R when R =< 90 -> rare_boons();
        _ -> legendary_boons()
    end,
    pick_n(Pool, Count, S1, []).

-spec legendary_drop(integer()) -> map().
legendary_drop(Seed) ->
    S = rand:seed_s(exsss, {Seed, Seed * 23, Seed * 31}),
    Legendaries = legendary_boons(),
    {Idx, _} = rand:uniform_s(length(Legendaries), S),
    lists:nth(Idx, Legendaries).

-spec pick_n([map()], non_neg_integer(), rand:state(), [map()]) -> [map()].
pick_n(_All, 0, _S, Acc) ->
    lists:reverse(Acc);
pick_n([], _N, _S, Acc) ->
    lists:reverse(Acc);
pick_n(All, N, S, Acc) ->
    {Idx, S1} = rand:uniform_s(length(All), S),
    Picked = lists:nth(Idx, All),
    Rest = All -- [Picked],
    pick_n(Rest, N - 1, S1, [Picked | Acc]).
