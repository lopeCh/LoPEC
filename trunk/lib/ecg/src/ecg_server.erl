%%%-------------------------------------------------------------------
%%% @author Gustav Simonsson <gusi7871@student.uu.se>
%%% @author Vasilij Savin <vasilij.savin@gmail.com>
%%% @doc
%%% ElectroCardioGram - process that keeps track of all alive 
%%% computational nodes
%%% @end
%%% Created : 29 Sep 2009 by Vasilij Savin 
%%%-------------------------------------------------------------------
-module(ecg_server).
-behaviour(gen_server).
-revision('$Rev$').
-created_by("Vasilij Savin, Gustav Simonsson").
-author("Vasilij Savin, Gustav Simonsson").
-record(state, {}).
-export([accept_message/1]).

%% gen_server callbacks
-export([start_link/0, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

%% ===================================================================
%% External functions
%% ===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Main interface with ECG.
%% ECG waits for 3 types of messages:
%% {nodeup} and {nodedown} are generated by net_kernel.
%% {new_node} notifies that potential new node arrived. ECG then checks
%% if this process is already known and establish connection in case
%% there is no prior connection.
%% Everything else is passed to logger and ignored.
%% @end
%%--------------------------------------------------------------------
accept_message(Msg) ->
    gen_server:cast({global, ?MODULE}, Msg).

%%%===================================================================
%%% Interface Function
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% gen_server callback function.
%% Starting ECG server and initialise it to listen to network messages
%% @end
%%--------------------------------------------------------------------
start_link() ->
    chronicler:info("~w : module started~n", [?MODULE]),
    gen_server:start_link({global, ?MODULE}, ?MODULE, [], []).


%% ====================================================================
%% Server functions
%% ====================================================================

%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------
%% @doc
%% Boots up ECG - cluster heartbeat listener.
%% @end
%%--------------------------------------------------------------------
init(_) ->
    net_kernel:monitor_nodes(true),
    chronicler:info("~w : is up and running!", [?MODULE]),
    {ok, #state{}}.

%% --------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_call(_Request, _From, _State) ->
    chronicler:warning("~w : Unexpected message in handle_call~n", [?MODULE]),
    {noreply, []}.

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling {new_node, <'node'@'hostname'>} message
%% Everything else is logged.
%% If node already registered - it is ignored
%% Returns: {noreply, State}
%% --------------------------------------------------------------------
%% We need to establish connection to new node, if not yet connected
%% This might be obsolete later, depending on comm protocol
handle_cast({new_node, Node}, _) ->
    case lists:member(Node, nodes()) of
        false ->
            chronicler:info("~w : Welcome new node: ~w~n", [?MODULE, Node]),
            net_adm:ping(Node);
        true ->
            ok
    end,
    {noreply, []};
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Logs and discards unexpected messages.
%%
%% @spec handle_cast(Msg, State) ->  {noreply, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(Msg, State) ->
    chronicler:warning("~w : Received unexpected handle_cast call.~n"
                       "Message: ~p~n",
                       [?MODULE, Msg]),
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling {nodeup} and {nodedown} messages sent by
%% net_kernel, when nodes joins cluster or dies.
%% Returns: {noreply, State}
%% --------------------------------------------------------------------
handle_info({nodeup, Node}, _) ->    
    chronicler:info("~w : Welcome new node: ~p~n", [?MODULE, Node]),
    {noreply, []};
handle_info({nodedown, Node}, _) ->
    dispatcher:free_tasks(Node),
    statistican:remove_node(Node),
    chronicler:info("~w : Node ~p just died. :(~n", [?MODULE, Node]),
    {noreply, []};
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Logs and discards unexpected messages.
%%
%% @spec handle_info(Info, State) -> {noreply, State} 
%% @end
%%--------------------------------------------------------------------
handle_info(Info, State) -> 
    chronicler:warning("~w : Received unexpected handle_info call.~n"
                       "Info: ~p~n",
                       [?MODULE, Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%% Logs and discards unexpected messages.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(Reason, _State) -> 
    chronicler:info("~w : Received terminate call.~n"
                    "Reason: ~p~n",
                    [?MODULE, Reason]),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%% Logs and discards unexpected messages.
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(OldVsn, State, Extra) -> 
    chronicler:debug("~w : Received code_change call.~n"
                     "Old version: ~p~n"
                     "Extra: ~p~n",
                     [?MODULE, OldVsn, Extra]),
    {ok, State}.
