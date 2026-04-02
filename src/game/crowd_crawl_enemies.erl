-module(crowd_crawl_enemies).

-export([types/0, boss_types/0, scale_for_floor/2, apply_boss_modifier/2]).

-spec types() -> [map()].
types() ->
    [
        #{name => ~"Slime", hp => 15, attack => 3, defense => 0, sprite => ~"slime", behavior => melee},
        #{name => ~"Bat", hp => 10, attack => 5, defense => 0, sprite => ~"bat", behavior => ranged},
        #{name => ~"Skeleton", hp => 25, attack => 6, defense => 2, sprite => ~"skeleton", behavior => melee},
        #{name => ~"Goblin", hp => 20, attack => 7, defense => 1, sprite => ~"goblin", behavior => ranged},
        #{name => ~"Dark Knight", hp => 40, attack => 10, defense => 5, sprite => ~"knight", behavior => tank},
        #{name => ~"Wraith", hp => 18, attack => 8, defense => 1, sprite => ~"wraith", behavior => ranged},
        #{name => ~"Troll", hp => 50, attack => 8, defense => 3, sprite => ~"troll", behavior => tank},
        #{name => ~"Imp", hp => 12, attack => 6, defense => 0, sprite => ~"imp", behavior => melee},
        #{name => ~"Spider", hp => 14, attack => 9, defense => 0, sprite => ~"spider", behavior => melee},
        #{name => ~"Mummy", hp => 35, attack => 5, defense => 4, sprite => ~"mummy", behavior => tank}
    ].

-spec boss_types() -> [map()].
boss_types() ->
    [
        #{
            name => ~"Dragon", hp => 150, attack => 18, defense => 8,
            sprite => ~"dragon", behavior => ranged,
            boss_ability => fire_breath
        },
        #{
            name => ~"Lich", hp => 120, attack => 15, defense => 5,
            sprite => ~"lich", behavior => ranged,
            boss_ability => summon
        },
        #{
            name => ~"Golem", hp => 200, attack => 20, defense => 15,
            sprite => ~"golem", behavior => tank,
            boss_ability => devastating
        },
        #{
            name => ~"Shadow", hp => 100, attack => 16, defense => 3,
            sprite => ~"shadow", behavior => melee,
            boss_ability => shadow_dodge
        },
        #{
            name => ~"Hydra", hp => 160, attack => 14, defense => 6,
            sprite => ~"hydra", behavior => melee,
            boss_ability => split
        }
    ].

-spec scale_for_floor(map(), pos_integer()) -> map().
scale_for_floor(Enemy, Floor) ->
    Multiplier = 1.0 + (Floor - 1) * 0.2,
    Hp = round(maps:get(hp, Enemy) * Multiplier),
    Atk = round(maps:get(attack, Enemy) * Multiplier),
    Def = round(maps:get(defense, Enemy) * Multiplier),
    Enemy#{hp => Hp, attack => Atk, defense => Def}.

-spec apply_boss_modifier(map(), binary() | none) -> {map(), [map()]}.
apply_boss_modifier(Boss, ~"double_hp") ->
    Hp = maps:get(hp, Boss) * 2,
    {Boss#{hp => Hp}, []};
apply_boss_modifier(Boss, ~"minions") ->
    Minions = [
        #{name => ~"Skeleton Minion", hp => 20, attack => 5, defense => 1,
          sprite => ~"skeleton", behavior => melee, x => 7, y => 3, id => 100},
        #{name => ~"Skeleton Minion", hp => 20, attack => 5, defense => 1,
          sprite => ~"skeleton", behavior => melee, x => 7, y => 5, id => 101}
    ],
    {Boss, Minions};
apply_boss_modifier(Boss, ~"speed") ->
    {Boss#{attacks_per_turn => 2}, []};
apply_boss_modifier(Boss, ~"darkness") ->
    {Boss#{darkness => true}, []};
apply_boss_modifier(Boss, _) ->
    {Boss, []}.
