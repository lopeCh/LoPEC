%%%-------------------------------------------------------------------
%%% @author Vasilij Savin <>
%%% @copyright (C) 2009, Vasilij Savin
%%% @doc
%%% 
%%% @end
%%% Created : Oct 5, 2009 by Vasilij Savin <>
%%%-------------------------------------------------------------------

-module(ecgApp).
-behaviour(application).

%% --------------------------------------------------------------------
%% Behavioural exports
%% --------------------------------------------------------------------
-export([ start/2, stop/1 ]).

%% --------------------------------------------------------------------
%% Internal exports
%% --------------------------------------------------------------------
-export([]).

%% ====================================================================!
%% External functions
%% ====================================================================!
%% --------------------------------------------------------------------
%% Func: start/2
%% Returns: {ok, Pid}        |
%%          {ok, Pid, State} |
%%          {error, Reason}
%% --------------------------------------------------------------------
start(_Type, _StartArgs) ->
    io:format("Starting ECG Application~n", []),
    Result = ecgSupervisor:start_link(),
    io:format("Response from supervisor: ~w ~n", [Result]),
    case Result of
	{ok, Pid} ->
        io:format("Started ECG Application~n", []),
	    {ok, Pid};
	Error ->
	    Error
    end.

%% --------------------------------------------------------------------
%% Func: stop/1
%% Returns: any
%% --------------------------------------------------------------------
stop(_State) ->
    ok.