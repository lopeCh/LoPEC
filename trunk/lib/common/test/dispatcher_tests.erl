%%%-------------------------------------------------------------------
%%% @author Axel Andren <axelandren@gmail.com>
%%% @author Vasilij Savin <vasilij.savin@gmail.com>
%%% @copyright (C) 2009, Axel
%%% @doc
%%%
%%% Contains the unit tests for the dispatcher. 
%%%
%%% @end
%%% Created : 1 Oct 2009 by Axel Andren <axelandren@gmail.com>
%%%-------------------------------------------------------------------
-module(dispatcher_tests).
-include("../../master/include/db.hrl").
-include_lib("eunit/include/eunit.hrl").

init_per_test_case() ->    
    db:start(test).

end_per_test_case() ->
    db:stop().

init_test() ->
    application:start(chronicler),
    application:start(ecg),
    dispatcher:start_link().

task_allocation_test() ->
    init_per_test_case(),
    JobId = db:add_job({raytracer, mapreduce, chabbrik, 0}),
    TaskSpec = {JobId, raytracer, split, "input_path"},
    TaskId =  dispatcher:add_task(TaskSpec),
    
    chronicler:info("GET TASK STARTS HERE"),
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
    %% The most buggy piece of cluster, unfortunately most critical too.
    %% Do not touch it, unles you REALLY know what you are doing.
    %% If something in cluster is not working, this is potentially reason.
    dispatcher:fetch_task(node(), self()),
    receive
        {task_response, Task} ->
            ?assert(Task#task.task_id =:= TaskId),
            ?assertEqual(split, Task#task.type),
            ?assertEqual(JobId, Task#task.job_id);
        Msg ->
            chronicler:error("Wrong message received: ~p", [Msg])  
        after 1000 ->
            chronicler:error("Fetching timed out: ~p", [])
    end,
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    end_per_test_case().

%% This test case is used to verify that request times out
%% when there is no free tasks, so taskFetcher can try again at later time.
timeout_test() ->
    init_per_test_case(),
    dispatcher:fetch_task(node(), self()),
    receive
        Msg ->
            chronicler:error("Unexpected message received: ~p", [Msg])
        after 1000 ->
            ok
    end,
    end_per_test_case().

task_completed_test() ->
    init_per_test_case(),
    JobId = db:add_job({raytracer, mapreduce, chabbrik, 0}),
    AssignedTask = {JobId, raytracer, map, "input data"},
    AId = db:add_task(AssignedTask),
    dispatcher:fetch_task(node(), self()),
    receive
        {task_response, Task} ->
            ?assertEqual(map, Task#task.type),
            ?assertEqual(JobId, Task#task.job_id),
            ?assertEqual(AId, Task#task.task_id),
            ?assertEqual(assigned, (db:get_task(AId))#task.state);
        Msg ->
            chronicler:error("Wrong message received: ~p", [Msg])  
        after 1000 ->
            chronicler:error("Fetching timed out: ~p", [])
    end,
    
    dispatcher:report_task_done(AId),
    DoneTask = db:get_task(AId),
    ?assertEqual(done, DoneTask#task.state),
    end_per_test_case().

end_test() ->
    db:stop(),
    dispatcher:terminate(finished, []).