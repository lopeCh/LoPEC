%%% File    : heartbeat.erl
%%% Author  : Axel <>
%%% Description : Implementation of node heartbeat process
%%% Created : 28 Sep 2009 by Axel <>

-module(heartbeat).
-include_lib("eunit/include/eunit.hrl").
-export([init/1, start_link/1]).

-revision('$Rev$').
-created("Date: Monday, September 28 2009").
-created_by("axelandren@gmail.com").
-modified('$LastChangedDate').
-modified_by("axelandren@gmail.com").
-description("Heartbeat process sends a message to electrocardiogram
process every so often (see definition of CARDIAC_FREQUENCY below) to
signal that the node the heartbeat process belongs to is still alive.").


-define(CARDIAC_FREQUENCY, 1000). % 1000 = 1 second

start_link(ECG_PID) ->
    {ok, spawn_link(?MODULE, init, [ECG_PID])}.

% TODO: find out if we need to manually terminate the heartbeat process

init(ECG_PID) ->
    loop(ECG_PID).


loop(ECG_PID) ->
    timer:sleep(?CARDIAC_FREQUENCY),
    ECG_PID ! {heartbeat, self()},
    % TODO: find out if ECGs need more items in the heartbeat messages
    loop(ECG_PID).
% TODO: we don't check if we receive (erroneous) messages, and it's hard to
% add without hurting the time-critical aspect


loop_test() ->
    start_link(self()),
    receive
        {heartbeat, PID} ->
            io:format("Got a heartbeat from PID ~p!~n", [PID]) 
    after (2 * ?CARDIAC_FREQUENCY) ->
            exit("Didn't get a heartbeat within 2 heartbeat timers.")
    end,
    
    receive
        {heartbeat, PID2} ->
            io:format("Got another heartbeat from PID ~p!~n", [PID2]) 
    after (2 * ?CARDIAC_FREQUENCY) ->
            exit("Didn't get a second heartbeat within 2 heartbeat timers.")
    end.
