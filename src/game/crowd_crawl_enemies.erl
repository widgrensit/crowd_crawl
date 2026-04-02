-module(crowd_crawl_enemies).

-export([types/0]).

-spec types() -> [map()].
types() ->
    [
        #{name => ~"Slime", hp => 15, attack => 3, defense => 0, sprite => ~"slime"},
        #{name => ~"Bat", hp => 10, attack => 5, defense => 0, sprite => ~"bat"},
        #{name => ~"Skeleton", hp => 25, attack => 6, defense => 2, sprite => ~"skeleton"},
        #{name => ~"Goblin", hp => 20, attack => 7, defense => 1, sprite => ~"goblin"},
        #{name => ~"Dark Knight", hp => 40, attack => 10, defense => 5, sprite => ~"knight"}
    ].
