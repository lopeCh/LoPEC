{application, slave,
    [{description, "Clusterbusters node client - A distributed high performance
                    low power cluster"},
    {vsn, "0.1"},
    {modules, [
        clientApp,
        clientSupervisor
            ]},
    {registered, []},
    {applications, [kernel, stdlib, chronicler, common]},
    {mod, {clientApp,[]}}
    ]}.