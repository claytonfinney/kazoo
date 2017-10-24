%%%%-------------------------------------------------------------------
%%% @copyright (C) 2010-2017, 2600Hz
%%% @doc
%%% monitors usurp_control
%%% @end
%%%
%%% @contributors
%%%-------------------------------------------------------------------
-module(ecallmgr_usurp_monitor).
-behaviour(gen_listener).

-compile({no_auto_import,[register/2]}).

%% API
-export([start_link/0]).

-export([register/1, register/2]).

%% gen_listener callbacks
-export([init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_info/2
        ,handle_event/2
        ,terminate/2
        ,code_change/3
        ]).

-include("ecallmgr.hrl").

-define(SERVER, ?MODULE).

-type state() :: map().

-record(cache, {call_id :: ne_binary()
               ,pid :: pid()
               }).
-type cache() :: #cache{}.

-define(BINDINGS, [{'call', [{'restrict_to', [<<"usurp_control">>]}
                            ,'federate'
                            ]}
                  ]).
-define(RESPONDERS, []).
-define(QUEUE_NAME, <<>>).
-define(QUEUE_OPTIONS, []).
-define(CONSUME_OPTIONS, []).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Starts the server
%%--------------------------------------------------------------------
-spec start_link() -> startlink_ret().
start_link() ->
    gen_listener:start_link({'local', ?SERVER}, ?MODULE,
                            [{'responders', ?RESPONDERS}
                            ,{'bindings', ?BINDINGS}
                            ,{'queue_name', ?QUEUE_NAME}
                            ,{'queue_options', ?QUEUE_OPTIONS}
                            ,{'consume_options', ?CONSUME_OPTIONS}
                            ], []).

%%%===================================================================
%%% gen_listener callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%% @end
%%--------------------------------------------------------------------
-spec init([]) -> {'ok', state()}.
init([]) ->
    kz_util:put_callid(?SERVER),
    lager:debug("starting usurp monitor"),
    {'ok', #{calls => ets:new('calls', ['set', {'keypos', #cache.call_id}])
            ,pids => ets:new('pids', ['set', {'keypos', #cache.pid}])
            }}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec handle_call(any(), pid_ref(), state()) -> handle_call_ret_state(state()).
handle_call(_Request, _From, State) ->
    {'reply', {'error', 'not_implemented'}, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(any(), state()) -> handle_cast_ret_state(state()).
handle_cast({register, CallId, Pid}, State) ->
    {'noreply', handle_register(#cache{call_id=CallId, pid=Pid}, State)};
handle_cast(_, State) ->
    {'noreply', State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec handle_info(any(), state()) -> handle_info_ret_state(state()).
handle_info({'DOWN', _Ref, 'process', Pid, _Reason}, State) ->
    {'noreply', handle_unregister(Pid, State)};
handle_info(_Msg, State) ->
    lager:debug("unhandled message: ~p", [_Msg]),
    {'noreply', State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Allows listener to pass options to handlers
%%
%% @spec handle_event(JObj, State) -> {reply, Options}
%% @end
%%--------------------------------------------------------------------
-spec handle_event(kz_json:object(), state()) -> gen_listener:handle_event_return().
handle_event(JObj, #{calls := Calls}) ->
    kz_util:put_callid(JObj),
    _ = case ets:lookup(Calls, kz_call_event:call_id(JObj)) of
            [#cache{pid=Pid}] -> Pid ! {'usurp_control', kz_call_event:fetch_id(JObj), JObj};
            _ -> 'ok'
        end,
    'ignore'.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_listener when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_listener terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec terminate(any(), state()) -> 'ok'.
terminate(_Reason, _State) -> 'ok'.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec code_change(any(), state(), any()) -> {'ok', state()}.
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.

-spec register(ne_binary()) -> 'ok'.
register(CallId) ->
    register(CallId, self()).

-spec register(ne_binary(), pid()) -> 'ok'.
register(CallId, Pid) ->
    gen_listener:cast(?SERVER, {register, CallId, Pid}).

-spec handle_register(cache(), state()) -> state().
handle_register(#cache{pid=Pid}=Cache, #{calls := Calls, pids := Pids} = State) ->
    _ = ets:insert(Calls, Cache),
    _ = ets:insert(Pids, Cache),    
    _ = erlang:monitor(process, Pid),
    State.

-spec handle_unregister(pid(), state()) -> state().
handle_unregister(Pid, #{pids := Pids} = State) ->
    case ets:lookup(Pids, Pid) of
        [#cache{}=Cache] -> unregister(Cache, State);
        _ -> State
    end.

-spec unregister(cache(), state()) -> state().
unregister(#cache{}=Cache, #{calls := Calls, pids := Pids} = State) ->
    _ = ets:delete(Calls, Cache),
    _ = ets:delete(Pids, Cache),
    State.