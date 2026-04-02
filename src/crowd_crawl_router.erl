-module(crowd_crawl_router).
-behaviour(nova_router).

-export([routes/1]).

-spec routes(atom()) -> [map()].
routes(_Environment) ->
    [
        #{
            prefix => ~"/api/v1/crowd_crawl",
            security => fun asobi_auth_plugin:verify/1,
            plugins => [
                {pre_request, nova_correlation_plugin, #{}}
            ],
            routes => [
                {~"/match", fun crowd_crawl_match_controller:create/1, #{methods => [post]}}
            ]
        },
        #{
            prefix => ~"",
            security => false,
            routes => [
                {~"/health", fun(_) -> {status, 200} end, #{methods => [get]}},
                {"/assets/[...]", "assets"}
            ]
        }
    ].
