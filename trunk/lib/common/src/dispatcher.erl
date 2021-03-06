%%%-------------------------------------------------------------------
%%% @author Axel Andren <axelandren@gmail.com>
%%% @author Vasilij Savin <vasilij.savin@gmail.com>
%%% @copyright (C) 2009, Axel Andren
%%% @doc
%%%
%%% Interfaces with the database. Can take requests for tasks, marking
%%% a task as done, adding tasks or jobs, and free tasks assigned to
%%% nodes (by un-assigning them).
%%%
%%% @end
%%% Created : 30 Sep 2009 by Axel Andren
%%%-------------------------------------------------------------------
-module(dispatcher).
-behaviour(gen_server).
-include("../../master/include/db.hrl").
-include("../../master/include/global.hrl").

%% API
-export([start_link/0,
         add_job/2,
         add_task/1,
         add_storage_key/3,
         stop_job/1,
         cancel_job/1,
         fetch_task/2,
         report_task_done/2,
         report_task_done/1,
         free_tasks/1,
	     task_failed/2,
         get_split_amount/0,
         get_user_from_job/1
        ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, find_task/2]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({global, ?MODULE}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Adds specified task to the database task list.
%% <pre>
%% TaskSpec is a tuple:
%% {
%%      JobId,
%%      ProgramName,
%%      Type - atoms 'map', 'reduce', 'finalize' or 'split' are
%%                  accepted at the moment (without quote marks '')
%%      Path - input file name
%% }
%% </pre>
%% @spec add_task(TaskSpec) -> TaskID
%% @end
%%--------------------------------------------------------------------
add_task(TaskSpec) ->
    gen_server:call({global, ?MODULE}, {add_task, TaskSpec}).

%%--------------------------------------------------------------------
%% @doc
%% Frees all tasks assigned to Node in master task list
%%
%% @spec free_tasks(NodeID) -> ok
%% @end
%%--------------------------------------------------------------------
free_tasks(NodeId) ->
    gen_server:cast({global, ?MODULE}, {free_tasks, NodeId}).

%%--------------------------------------------------------------------
%% @doc
%% Stops a job. A stopping job is halted before completion and stays
%% in that state until its resumed
%%
%% @spec stop_job(JobId) -> ok
%% @end
%%--------------------------------------------------------------------
stop_job(JobId) ->
    chronicler:debug("~w : Stopping job~n", [?MODULE]),
    gen_server:call({global, ?MODULE}, {stop_job, JobId}).

%%--------------------------------------------------------------------
%% @doc
%% Cancels a job. Its the same as for stop_job/1 but the job will also
%% be removed from the database.
%%
%% @spec cancel_job(JobId) -> ok
%% @end
%%--------------------------------------------------------------------
cancel_job(JobId) ->
    chronicler:debug("~w : Canceling job~n", [?MODULE]),
    gen_server:call({global, ?MODULE}, {cancel_job, JobId}).

%%--------------------------------------------------------------------
%% @doc
%% Adds specified job to the database job list, add it to the bg job
%% list instead iff IsBGJob.
%% <pre>
%% JobSpec is a tuple:
%% {
%%      ProgramName,
%%      ProblemType (map reduce only accepted now)
%%      Owner
%%      Priority - not implemented at the moment
%% }
%% </pre>
%% @spec add_job(JobSpec, IsBGJob) -> JobID
%% @end
%%--------------------------------------------------------------------
add_job(JobSpec, false) ->
    gen_server:call({global, ?MODULE}, {add_job, JobSpec});
add_job(JobSpec, true) ->
    gen_server:call({global, ?MODULE}, {add_bg_job, JobSpec}).

%%--------------------------------------------------------------------
%% @doc
%% Sends a message to the caller with the first available task.
%% If no task is available a {task_response, no_task} message is returned
%%
%% @spec fetch_task(NodeID, PID) -> ok
%% @end
%%--------------------------------------------------------------------
fetch_task(NodeId, PID) ->
    gen_server:cast({global, ?MODULE}, {task_request, NodeId, PID}).

%%--------------------------------------------------------------------
%% @doc
%% Marks the task as being completely done. The results should be
%% posted on storage before calling this method.
%%
%% @spec report_task_done(TaskID) -> ok
%% @end
%%--------------------------------------------------------------------
report_task_done(TaskId) ->
    gen_server:call({global, ?MODULE}, {task_done, TaskId, no_task}).

%%--------------------------------------------------------------------
%% @doc
%% Like report_task_done/1 except the node can ask to generate another
%% task by providing a TaskSpec
%%
%% @spec report_task_done(TaskID, TaskSpec) -> ok
%% @end
%%--------------------------------------------------------------------
report_task_done(TaskId, TaskSpec) ->
    gen_server:call({global, ?MODULE}, {task_done, TaskId, TaskSpec}).

%%--------------------------------------------------------------------
%% @doc
%% Increases the task restart counter for the job and makes the
%% task free. If the threshold for the max task restarts is reached
%% for the job the job will be stopped.
%%
%% @spec task_failed(JobId, TaskType) -> ok | {ok, stopped}
%% @end
%%--------------------------------------------------------------------
task_failed(JobId, TaskType) ->
    gen_server:call({global, ?MODULE},
                    {task_failed, JobId, node(), TaskType}).

%%--------------------------------------------------------------------
%% @doc
%% Returns the amount of splits to be done.
%%
%% @spec get_split_amount() -> Amount::integer()
%% @end
%%--------------------------------------------------------------------
get_split_amount() ->
    gen_server:call({global, ?MODULE}, get_split_amount).

%%--------------------------------------------------------------------
%% @doc
%% Returns the user associated with the job
%%
%% @spec get_user_from_job(JobId) -> User
%% @end
%%--------------------------------------------------------------------
get_user_from_job(JobId) ->
    gen_server:call({global, ?MODULE}, {get_user_from_job, JobId}).

%%--------------------------------------------------------------------
%% @doc
%%
%% Add Key to Bucket in the storage key table in the db
%%
%% @spec add_storage_key(Job, Bucket::binary(), Key::binary()) -> ok | {error, Error}
%% @end
%%--------------------------------------------------------------------
add_storage_key(Job, Bucket, Key) ->
    gen_server:call({global, ?MODULE}, {add_storage_key, Job, Bucket, Key}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initiates the server. Currently no special setup is needed.
%%
%% @spec init(Args) -> {ok, State}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    chronicler:info("~p: Server started~n", [?MODULE]),
    {ok, no_state}.

%%--------------------------------------------------------------------
%% @doc
%% Expects task requests from nodes, and passes such requests to the
%% find_task function.
%%
%% @spec handle_cast({task_request, NodeId, From}, State) ->
%%                                                    {noreply, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({task_request, NodeId, From}, State) ->
    spawn(?MODULE, find_task, [From, NodeId]),
    {noreply, State};
%%--------------------------------------------------------------------
%% @doc
%% Un-assigns all tasks assigned to the specified node.
%%
%% @spec handle_cast({free_tasks, NodeId}, State) ->  {noreply, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({free_tasks, NodeId}, State) ->
    Jobs = db:free_tasks(NodeId),
    chronicler:debug("Node ~p freed the tasks: ~p", [NodeId, Jobs]),
    examiner:report_free(Jobs),
    {noreply, State};
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Logs and discards unexpected messages.
%%
%% @spec handle_cast(Msg, State) ->  {noreply, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(Msg, State) ->
    chronicler:debug("~w:Received unexpected handle_cast call.~n"
                       "Message: ~p~n",
                       [?MODULE, Msg]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @doc
%% Marks a specified task as done in the database.
%%
%% @spec handle_call({task_done, TaskId, no_task}, From, State) ->
%%                                   {reply, ok, State}
%% @end
%%--------------------------------------------------------------------
handle_call({task_done, TaskId, no_task}, _From, State) ->
    mark_done(TaskId),
    {reply, ok, State};

%%--------------------------------------------------------------------
%% @doc
%% Marks a specified task as done in the database and adds a
%% (different) specified task to the database
%%
%% @spec handle_call({task_done, TaskId, TaskSpec}, From, State) ->
%%                                   {reply, NewTaskId, State}
%% @end
%%--------------------------------------------------------------------
handle_call({task_done, TaskId, TaskSpec}, _From, State) ->
    chronicler:debug("?MODULE: TaskSpec: ~p", [TaskSpec]),
    mark_done(TaskId),
    Reply = create_task(TaskSpec),
    {reply, Reply, State};

%%--------------------------------------------------------------------
%% @doc
%% Adds a specified task to the database
%%
%% @spec handle_call({create_task, TaskSpec}, From, State) ->
%%                                   {reply, NewTaskID, State}
%% @end
%%--------------------------------------------------------------------
handle_call({add_task, TaskSpec}, _From, State) ->
    Reply = create_task(TaskSpec),
    {reply, Reply, State};

%%--------------------------------------------------------------------
%% @doc
%% Stops a job.
%%
%% @spec handle_call({stop_job, JobId}, From, State) ->
%%                                   {reply, ok, State}
%% @end
%%--------------------------------------------------------------------
handle_call({stop_job, JobId}, _From, State) ->
    NodeList = db:stop_job(JobId),
    stop_nodes(NodeList),
    {reply, ok, State};

%%--------------------------------------------------------------------
%% @doc
%% Cancels a job.
%%
%% @spec handle_call({cancel_job, JobId}, From, State) ->
%%                                   {reply, ok, State}
%% @end
%%--------------------------------------------------------------------
handle_call({cancel_job, JobId}, _From, State) ->
    NodeList = db:cancel_job(JobId),
    %% This sends a message "stop" to all nodes. This message will be
    %% caught in taskFetcher on the slave-side.
    lists:foreach(fun (X) -> global:send(X, stop_job) end, NodeList),
    {reply, ok, State};

%%--------------------------------------------------------------------
%% @doc
%% Adds a specified job to the database
%%
%% @spec handle_call({add_job, JobSpec}, From, State) ->
%%                                   {reply, NewJobID, State}
%% @end
%%--------------------------------------------------------------------
handle_call({add_job, JobSpec}, _From, State) ->
    NewJobId = db:add_job(JobSpec),
    case NewJobId of
        {error, Error} ->
            chronicler:error(fix_me_need_user_id, Error),
            {reply, {error, Error}, State};
        _ ->
            examiner:insert(NewJobId),
            {reply, NewJobId, State}
    end;

%%--------------------------------------------------------------------
%% @doc
%% Adds a specified background job to the database
%%
%% @spec handle_call({add_bg_job, JobSpec}, From, State) ->
%%                                   {reply, NewJobID, State}
%% @end
%%--------------------------------------------------------------------
handle_call({add_bg_job, JobSpec}, _From, State) ->
    NewJobId = db:add_bg_job(JobSpec),
    case NewJobId of
        {error, Error} ->
            chronicler:error(Error),
            {reply, {error, Error}, State};
        _ ->
            examiner:insert(NewJobId),
            {reply, NewJobId, State}
    end;

%%--------------------------------------------------------------------
%% @doc
%% Restarts task if job isn't over-restarted, in that case it
%% stops the job.
%%
%% @spec handle_call({task_failed, JobId, Node}, From, State) ->
%%                                   {reply, ok, State} |
%%                                   {reply, {ok, stopped}, state}
%% @end
%%--------------------------------------------------------------------
handle_call({task_failed, JobId, Node, TaskType}, _From, State) ->
    Result = db:increment_task_restarts(JobId),
    {ok, Max_Restarts} =
        configparser:read_config("/etc/lopec.conf",
                                 max_restarts),
    if
	Result < Max_Restarts ->
	    db:free_tasks(Node),
            examiner:report_free([{JobId, TaskType}]),
	    {reply, ok, State};
	Result >= Max_Restarts ->
	    db:stop_job(JobId),
            chronicler:user_info(fix_me_need_user_id, "Job ~p stopped, reason: "
                                 "Too many task restarts", [JobId]),
            examiner:remove(JobId),
	    {reply, {ok, stopped}, State}
    end;

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns the amount of files to split to.
%%
%% @spec handle_call(get_split_amount, From, State) ->  {Amount, State}
%% @end
%%--------------------------------------------------------------------
handle_call(get_split_amount, _From, State) ->
    {reply, erlang:length(erlang:nodes()) * 2, State};

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns the user associated with the Job
%%
%% @spec handle_call({get_user_from_job, JobId, From, State) ->  User
%%                                                    | {error, Reason}
%% @end
%%--------------------------------------------------------------------
handle_call({get_user_from_job, JobId}, _From, State) ->
    {reply, db:get_user_from_job(JobId), State};

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Adds Key to Bucket in the storage_key table in db
%%
%% @spec handle_call({add_storage_key, Bucket, Key}, _From, State) ->
%%           {reply, Reply, State}
%%           Reply = ok | {error, Error}
%% @end
%%--------------------------------------------------------------------
handle_call({add_storage_key, Job, Bucket, Key}, _From, State) ->
    {reply, db:add_storage_key(Job, Bucket, Key), State};

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Logs and discards unexpected messages.
%%
%% @spec handle_call(Msg, From, State) ->  {noreply, State}
%% @end
%%--------------------------------------------------------------------
handle_call(Msg, From, State) ->
    chronicler:debug("~w:Received unexpected handle_call call.~n"
                       "Message: ~p~n"
                       "From: ~p~n",
                       [?MODULE, Msg, From]),
    {noreply, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Sends a message to given PID with the first found task in the DB,
%% and tells the ECG to register this new node with that PID. If no
%% task is found a {task_response, no_task} is returned.
%%
%% @spec find_task(RequesterPID, NodeId) -> ok | db:assign_task()
%% @end
%%--------------------------------------------------------------------
find_task(RequesterPID, NodeId) ->
    FreeTask = db:fetch_task(NodeId),
    case FreeTask of
        no_task ->
            chronicler:debug("~p: Found no tasks.~n",[?MODULE]),
            RequesterPID ! {task_response, no_task},
            ok;
        {Task, NodesToKill} ->
            stop_nodes(NodesToKill),
            chronicler:debug("~p: Found task ~p.~n",
                             [?MODULE, Task#task.task_id]),
            {Bucket, _Key} = Task#task.path,
            {ok, Keys} = db:list_keys(Bucket),
            TaskResponse = {Task#task.task_id,
                            Task#task.job_id,
                            Task#task.program_name,
                            Task#task.type,
                            {Bucket, lists:sort(Keys)}},
            RequesterPID ! {task_response, TaskResponse},
            ecg_server:accept_message({new_node, NodeId}),
            chronicler:debug("Examiner in find_task: ~p",
                             [examiner:get_progress(Task#task.job_id)]),
            examiner:report_assigned(Task#task.job_id, Task#task.type)
    end.

mark_done(TaskId) ->
    db:mark_done(TaskId),
    Task = db:get_task(TaskId),
    examiner:report_done(Task#task.job_id, Task#task.type).

create_task(TaskSpec) ->
    chronicler:debug("TaskSpec: ~p", [TaskSpec]),
    case db:add_task(TaskSpec) of
        {error, job_not_in_db} ->
            chronicler:debug("?MODULE: Job does not exist in DB", []),
            {error, job_not_in_db};
        {ok, task_exists} ->
            chronicler:debug("?MODULE: Duplicate task was not created", []),
            {ok, task_exists};
        {ok, {NewTaskId, NodeToKill}} ->
            Task = db:get_task(NewTaskId),
            examiner:report_created(Task#task.job_id, Task#task.type),
            stop_nodes(NodeToKill),
            NewTaskId
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% Globally sends stop to all nodes in NodeList
%%
%% @spec stop_nodes(NodeList) -> ok
%% @end
%%--------------------------------------------------------------------
stop_nodes(NodeList) ->
    chronicler:debug("~w: Killing nodes ~p", [?MODULE, NodeList]),
    % @todo Why do we free tasks here and in the db?
    % Only for the list to examiner?
    lists:foreach(fun (Node) -> global:send(Node, stop_job),
                                TaskList = db:free_tasks(Node),
                                examiner:report_free(TaskList) end,
                  NodeList).

%%%===================================================================
%%% Not implemented stuff
%%%===================================================================

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
    chronicler:debug("~w:Received terminate call.~n"
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
    chronicler:debug("~w:Received code_change call.~n"
                     "Old version: ~p~n"
                     "Extra: ~p~n",
                     [?MODULE, OldVsn, Extra]),
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Logs and discards unexpected messages.
%%
%% @spec handle_info(Info, State) -> {noreply, State}
%% @end
%%--------------------------------------------------------------------
handle_info(Info, State) ->
    chronicler:debug("~w:Received unexpected handle_info call.~n"
                       "Info: ~p~n",
                       [?MODULE, Info]),
    {noreply, State}.
