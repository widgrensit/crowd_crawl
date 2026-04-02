-module(crowd_crawl_match_controller).

-export([create/1]).

-spec create(cowboy_req:req()) -> {json, integer(), map(), map()}.
create(#{auth_data := #{player_id := _PlayerId}} = _Req) ->
    Config = #{
        game_module => crowd_crawl_game,
        min_players => 1,
        max_players => 100,
        tick_rate => 200
    },
    case asobi_match_sup:start_match(Config) of
        {ok, Pid} ->
            Info = asobi_match_server:get_info(Pid),
            {json, 200, #{}, Info};
        {error, Reason} ->
            {json, 500, #{}, #{error => Reason}}
    end.
