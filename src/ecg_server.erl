%%%-------------------------------------------------------------------
%%% @author Vasilij Savin, Gustav Simonsson <>
%%% @doc
%%% ElectroCardioGram - process that keeps track of all alive 
%%% computational nodes
%%% @end
%%% Created : 29 Sep 2009 by Vasilij Savin <>
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
    %Debugging output
    %% logger ! {event, self(),
    %%     io_lib:format("Msg received: ~w", [Msg])},
    
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
%% IMPORTANT: 'logger' should be registered process, otherwise
%% ECG will fail.
%% 
%% @end
%%--------------------------------------------------------------------
init(_) ->
    net_kernel:monitor_nodes(true),
    %logger ! {event, self(), "ECG is up and running!"},
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
    io:format("New Node ~n", []),
    %logger ! {event, self(), 
    %    io_lib:format("New Node", [])},
    case lists:member(Node, nodes()) of
        false ->
            net_adm:ping(Node);
        true ->
            ok
    end,
    {noreply, []};
handle_cast(UnrecognisedMessage, _) ->
    io:format("UnrecognisedMessage: ~w ~n", [UnrecognisedMessage]),
    %logger ! {event, self(), 
    %    io_lib:format("UnrecognisedMessage: ~w", [UnrecognisedMessage])},
    {noreply, []}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling {nodeup} and {nodedown} messages sent by
%% net_kernel, when nodes joins cluster or dies.
%% Returns: {noreply, State}
%% --------------------------------------------------------------------
handle_info({nodeup, Node}, _) ->
    io:format("Welcome new node: ~w~n", [Node]),
    %logger ! {event, self(), 
    %    io_lib:format("Welcome new node: ~w", [Node])},
    {noreply, []};
handle_info({nodedown, Node}, _) ->
    % Stub needed to contact Task List API
    % tasklist:free_tasks(Node),
    io:format("Node ~w just died. :()~n", [Node]),
    %logger ! {event, self(),
    %    io_lib:format("Node ~w just died. :()~n", [Node])},
    {noreply, []};
handle_info(UnrecognisedMessage, _) ->
    io:format("~nUnrecognisedMessage: ~w ~n", [UnrecognisedMessage]),
    %logger ! {event, self(), 
    %    io_lib:format("UnrecognisedMessage: ~w", [UnrecognisedMessage])},
    {noreply, []}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(_OldVsn, _State, _Extra) ->
    {ok, []}.
