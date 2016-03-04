defmodule Lakeland.Listener.Supervisor do
  use Supervisor

  @spec start_link(Lakeland.ref, module, Keyword.t, Keyword.t, module) :: Supervisor.on_start
  def start_link(ref, handler, handler_opts, listener_opts, transport) do
    Supervisor.start_link(__MODULE__, {
          ref, handler, handler_opts, listener_opts, transport
    })
  end


  def init({ref, handler, handler_opts, listener_opts, transport}) do
    # options for Connection.Manager
    ack_timeout = listener_opts |> Keyword.fetch!(:ack_timeout)
    connection_type = listener_opts |> Keyword.fetch!(:connection_type)
    shutdown = listener_opts |> Keyword.fetch!(:shutdown)

    max_connections = listener_opts |> Keyword.fetch!(:max_connections)
    Lakeland.Server.set_new_listener_opts(ref, max_connections, handler_opts)

    # options for Acceptor.Supervisor
    num_of_acceptors = listener_opts |> Keyword.fetch!(:num_acceptors)
    socket = listener_opts |> Keyword.get(:socket, nil)

    transport_opts = listener_opts
    |> Keyword.delete(:ack_timeout)
    |> Keyword.delete(:connection_type)
    |> Keyword.delete(:max_connections)
    |> Keyword.delete(:shutdown)
    |> Keyword.delete(:num_acceptors)
    |> Keyword.delete(:socket)

    children = [
      worker(Lakeland.Connection.Manager, [
            ref, connection_type, shutdown, ack_timeout, transport, handler
          ]),
      supervisor(Lakeland.Acceptor.Supervisor, [
            ref, num_of_acceptors, socket, transport, transport_opts
          ])
    ]

    supervise(children, strategy: :rest_for_one, max_restarts: 1, max_seconds: 5)
  end


end
