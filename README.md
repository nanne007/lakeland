## Lakeland

### Description

Lakeland is an copycat of [Ranch](https://github.com/ninenines/ranch)(connection pool of tcp for erlang).
For now, this repo is just for the purpose of learning elixir and erlang and any sugguestion is appreciated.

### What it implements.

Lakeland drop the `remove_connection` functionality of ranch.
And use `Lakeland.Connection.Manager`(a gen_server linked with a supervisor) to manage connections. (Ranch uses a customized supervisor).
I also adjust the `start_listener` args to my own preference.


### How to use

The following code starts a echo server in port 8080.

```
{:ok, _listener} = Lakeland.start_listener(:echo, Lakeland.Handler.Echo, [], [num_acceptors: 3, port: 8080])
:echo |> Lakeland.get_addr # => {{0, 0, 0, 0}, 8080}
:echo |> Lakeland.get_max_connections # => 1024
:echo |> Lakeland.set_max_connections(2048) # => :ok
:echo |> Lakeland.get_max_connections # => 2048
```

Use `telnet localhost 8080` to echo yourself.


### How to build

Lakeland is an elixir mix project.
After cloning it, you can simply run `mix deps.get` and `mix compile`.
To see the docs, use `mix docs`.

### License

See LICENSE file.
