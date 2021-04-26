%%%-------------------------------------------------------------------
%% @doc ss5_proxy public API
%% @end
%%%-------------------------------------------------------------------

-module(ss5_proxy_app).

-behaviour(application).

-export([start/2, stop/1]).


-define(TCP_OPTION,[binary, {packet,0}, {active,false}, {reuseaddr, true}]).
					
-define(DEF_PORT, 9527).  %%默认监听端口
-define(TAB_CONFIG, tab_config).

%%认证方式，0是无需认证 1是gssapi，2是账号密码
-define(AM_NO_AUTH, 0).
-define(AM_GSSAPI, 1).
-define(AM_USERNAME, 2).
-define(AM_INVALID, 16#FF).

%%客户端命令
-define(CMD_CONNECT, 1).	%%目前只支持connect

-define(LOG(X), io:format("{~p,~p}: ~p~n", [?MODULE,?LINE,X])).

start(_StartType, Args) ->
	case start_server(Args) of
    	{no, E} ->
    		io:format("error:~p~n", [E]);
    	_ ->
    		ss5_proxy_sup:start_link()
    end.

stop(_State) ->
    ok.

%% internal functions
start_server(Args) ->
	Sport = init_config(Args),
	?LOG(ets:tab2list(?TAB_CONFIG)),
	?LOG({port, Sport}),
	case gen_tcp:listen(Sport, ?TCP_OPTION) of
		{ok, LSock} ->
			spawn(fun() -> accept(LSock) end);
		E ->
			{no, E}
	end.

init_config(_Args) ->
	_ = ets:new(?TAB_CONFIG, [set, named_table, public]),
	case application:get_env(ss5_proxy, user) of
		undefined ->
			true = ets:insert(?TAB_CONFIG, {user, false});
		{ok, User} ->
			true = ets:insert(?TAB_CONFIG, {user, erlang:list_to_binary(User)}),
			case application:get_env(ss5_proxy, pass) of
				undefined ->
					true = ets:insert(?TAB_CONFIG, {pass, []});
				{ok, Pass} ->
					true = ets:insert(?TAB_CONFIG, {pass, erlang:list_to_binary(Pass)})
			end
	end,
	case application:get_env(ss5_proxy, tcp_port) of
		{ok, Port} ->
			Port;
		undefined ->
			?DEF_PORT
	end.

accept(LSock) ->
	case gen_tcp:accept(LSock) of
		{ok, CSock} ->
			spawn(fun() -> do_start(CSock) end);
		{error, E} -> 
			E
	end,
	accept(LSock).

do_start(CSock) ->
	{ok, {Client, _}} = inet:peername(CSock),
	case ets:lookup(?TAB_CONFIG, Client) of
		[{Client, true}] ->
			do_work(CSock);
		_ ->
			case gen_tcp:recv(CSock, 0) of
				{ok, Data} ->
					case do_auth(Data, CSock) of
						ok ->
							true = ets:insert(?TAB_CONFIG, {Client, true}),
							do_work(CSock);
						Err ->
							% ?LOG(Err),
							Err
					end;
				{error, closed} ->
					gen_tcp:close(CSock);
				Err1 ->
					Err1
			end
	end.

do_work(CSock) ->
	case gen_tcp:recv(CSock, 0) of
		{ok, Data} ->
			case do_conn(Data, CSock) of
				{ok, RSock} ->
					{ok, {{Ip1, Ip2, Ip3, Ip4}, Port}} = inet:peername(CSock),
					gen_tcp:send(CSock, <<5:8, 0:8, 0:8, 1:8, Ip1:8, Ip2:8, Ip3:8, Ip4:8, Port:16>>),
					do_loop(CSock, RSock);
				{no, _} ->
					do_work(CSock);
				ok ->
					do_work(CSock);
				_ ->
					% ?LOG(Err1),
					gen_tcp:send(CSock, <<5:8, 3:8, 0:8, 1:8, 0:32, 0:16>>),	%%目标服务器访问失败
					do_work(CSock)
			end;
		{error, closed} ->
			gen_tcp:close(CSock);
		Err ->
			Err
	end.


do_conn(<<5:8, Cmd:8, _:8, At:8, B/binary>>, _) ->
	if Cmd == 1 ->
			if At == 1 ->
					case B of 
						<<Ip1:8, Ip2:8, Ip3:8, Ip4:8, Rport:16, _/binary>> ->
							Rip = inet_parse:ntoa({Ip1,Ip2,Ip3,Ip4}),
							gen_tcp:connect(Rip, Rport, [binary,{packet,0},{active,false}]);
						_ ->
							{no, <<5:8, 4:8, 0:8, 1:8, 0:32, 0:16>>} %%目标服务器无法访问（ip无效）
					end;
				At == 3 ->
					case B of
						<<L:8, Sname:L/binary, Rport:16, _/binary>> ->
							Rname=erlang:binary_to_list(Sname),
							gen_tcp:connect(Rname, Rport, [binary,{packet,0},{active,false}]);
						_ ->
							{no, <<5:8, 4:8, 0:8, 1:8, 0:32, 0:16>>} %%目标服务器无法访问（主机名无效）
					end;
				At == 4 ->
					{no, <<5:8, 8:8, 0:8, 1:8, 0:32, 0:16>>}	%%不支持ipv6
			end;
		true ->
			{no, <<5:8, 7:8, 0:8, 1:8, 0:32, 0:16>>}	%%不支持非connect命令
	end;

do_conn(<<5:8,1:8,0:8,_/binary>>, CSock) ->
	gen_tcp:send(CSock, <<5:8,?AM_NO_AUTH:8>>);
do_conn(<<5:8,1:8,2:8,_/binary>>, CSock) ->
	gen_tcp:send(CSock, <<5:8,?AM_USERNAME:8>>),
	case gen_tcp:recv(CSock, 0) of
		{ok, Data} ->
			case check_user(Data) of 
				{ok, V} ->
					% ?LOG(V),
					gen_tcp:send(CSock, <<V:8, 0:8>>);
					% do_work(CSock);
				Err1 ->
					% ?LOG(Err1),
					gen_tcp:send(CSock, <<1:8, 1:8>>),
					Err1
			end;
		Err ->
			Err
	end;

do_conn(_, _) ->
	% ?LOG(B),
	{no, wrong_data}.

do_loop(CSock, RSock) ->
	_ = spawn_link(fun() -> r_and_s(RSock, CSock) end),
	r_and_s(CSock, RSock).

r_and_s(CSock, RSock) ->
	case gen_tcp:recv(CSock, 0) of
		{ok, Cdata} ->
			gen_tcp:send(RSock, Cdata),
			r_and_s(CSock, RSock);
		{error, closed} ->
			gen_tcp:close(CSock);
		Err ->
			gen_tcp:send(RSock, Err)
	end.


do_auth(<<5:8, Mod_len:8, Bin:Mod_len/binary, _/binary>>, CSock) ->
	Mlist = get_mods(Mod_len, Bin),
	check_auth(Mlist, CSock);
do_auth(_, _) ->
	ver_error.

get_mods(N, B) when N > 0->
	get_mods(N, B, []);
get_mods(_, _) ->
	[].

get_mods(0, _, L) ->
	L;
get_mods(N, <<M:8, B/binary>>, L) ->
	get_mods(N-1, B, [M|L]).

check_auth(Mlist, CSock) ->
	% ?LOG(Mlist),
	case ets:lookup(?TAB_CONFIG, user) of
		[{user, false}] ->
			case lists:member(?AM_NO_AUTH, Mlist) of
				true ->
					gen_tcp:send(CSock, <<5:8,?AM_NO_AUTH:8>>),
					ok;
				false ->
					gen_tcp:send(CSock, <<5:8,?AM_INVALID:8>>),
					wrong_auth_type
			end;
		_ ->
			case lists:member(?AM_USERNAME, Mlist) of
				true ->
					gen_tcp:send(CSock, <<5:8,?AM_USERNAME:8>>),
					case gen_tcp:recv(CSock, 0) of
						{ok, Data} ->
							case check_user(Data) of 
								{ok, V} ->
									% ?LOG(V),
									gen_tcp:send(CSock, <<V:8, 0:8>>),
									ok;
								Err1 ->
									% ?LOG(Err1),
									gen_tcp:send(CSock, <<1:8, 1:8>>),
									Err1
							end;
						Err ->
							Err
					end;
				false ->
					gen_tcp:send(CSock, <<5:8,?AM_INVALID:8>>),
					wrong_auth_type
			end
	end.

check_user(<<V:8, Ulen:8, U:Ulen/binary, Plen:8, P:Plen/binary, _/binary>>) ->
	case ets:lookup(?TAB_CONFIG, user) of
		[{user, U}] ->
			case ets:lookup(?TAB_CONFIG, pass) of
				[{pass, P}] ->
					{ok, V};
				_ ->
					wrong_pass
			end;
		[{user, false}] ->
			{ok, V};
		_ ->
			wrong_user
	end;
check_user(_) ->
	unkown_wrong.


