defmodule Lakeland.Listener.Supervisor do
  use Supervisor

  @spec start_link(Lakeland.ref, non_neg_integer, module, Keyword.t, module, Keyword.t) :: Supervisor.on_start
  def start_link(ref, num_of_acceptors, transport, transport_opts, protocol, protocol_opts) do
    max_connections = transport_opts |> Keyword.get(:max_connections, 1024)
    Lakeland.Server.set_new_listener_opts(ref, max_connections, protocol_opts)
    Supervisor.start_link(__MODULE__, {
          ref, num_of_acceptors, transport, transport_opts, protocol
    })
  end


  def init({ref, num_of_acceptors, transport, transport_opts, protocol}) do
    ack_timeout = transport_opts |> Keyword.get(:ack_timeout, 5000)
    connection_type = transport_opts |> Keyword.get(:connection_type, :worker)
    shutdown = transport_opts |> Keyword.get(:shutdown, 5000)

    children = [
      worker(Lakeland.Connection.Manager, [
            ref, connection_type, shutdown, ack_timeout,transport, protocol
          ]),
      supervisor(Lakeland.Acceptor.Supervisor, [
            ref, num_of_acceptors, transport, transport_opts
          ])
    ]

    supervise(children, strategy: :rest_for_one, max_restarts: 1, max_seconds: 5)
  end


end
