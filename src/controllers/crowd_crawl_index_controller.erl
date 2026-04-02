-module(crowd_crawl_index_controller).

-export([index/1]).

-spec index(cowboy_req:req()) -> {sendfile, integer(), binary()}.
index(_Req) ->
    Path = filename:join(code:priv_dir(crowd_crawl), "static/index.html"),
    {sendfile, 200, #{~"content-type" => ~"text/html"}, Path, #{}}.
