## Lakeland

### Description

Lakeland is an copycat of [Ranch](https://github.com/ninenines/ranch)(connection pool of tcp for erlang).
This repo is just for the purpose of learning elixir and erlang.
Many tests are missing, so **do not** use it in production.

### What's the difference.

- Lakeland drops the `remove_connection` functionality of ranch,
- And uses `Lakeland.Connection.Manager`(a gen_server that links a handler supervisor) to manage connections,
  while ranch uses a customized supervisor.
- The arguments of `start_listener` is changed accroding to my own preference.
- Also, fix a bug in ranch, see ninenines/ranch#140.

### How to use

``` shell
$ git clone https://github.com/lerencao/lakeland.git && cd lakeland
$ mix deps.get && mix compile
$ iex -S mix
```

Then in the iex shell, enter the following code to starts a echo server in port 8080.

``` elixir
{:ok, _listener} = Lakeland.start_listener(:echo, Lakeland.Handler.Echo, [], [num_acceptors: 3, port: 8080])
:echo |> Lakeland.get_addr # => {{0, 0, 0, 0}, 8080}
:echo |> Lakeland.get_max_connections # => 1024
:echo |> Lakeland.set_max_connections(2048) # => :ok
:echo |> Lakeland.get_max_connections # => 2048
```

Use `telnet localhost 8080` to echo yourself.

To see the docs, use `mix docs`.

### License

See LICENSE file.
