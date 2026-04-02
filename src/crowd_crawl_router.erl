-module(crowd_crawl_router).
-behaviour(nova_router).

-export([routes/1]).

-spec routes(atom()) -> [map()].
routes(_Environment) ->
    [
        #{
            prefix => ~"",
            security => false,
            routes => [
                {~"/health", fun(_) -> {status, 200} end, #{methods => [get]}},
                {"/assets/[...]", "assets"}
            ]
        }
    ].
