defmodule Lakeland.Acceptor.Supervisor do
  use Supervisor

  @spec start_link(Lakeland.ref, non_neg_integer, :inet.socket | nil, module, Keyword.t) :: Supervisor.on_start
  def start_link(ref, num_of_acceptors, socket, transport, transport_opts) do
    Supervisor.start_link(__MODULE__, {ref, num_of_acceptors, socket, transport, transport_opts})
  end

  def init({ref, num_of_acceptors, socket, transport, transport_opts}) do
    listen_socket = if socket != nil do
      socket
    else
      case transport.listen(transport_opts) do
        {:ok, socket} ->
          socket
        {:error, reason} ->
          require Logger
          :ok = Logger.error("Failed to start listener #{inspect ref} " <>
            "in #{inspect transport}.listen(#{inspect transport_opts}) " <>
            "for reason #{inspect reason} (#{:inet.format_error(reason)})")
          exit({:listen_error, ref, reason})
      end
    end

    {:ok, addr} = transport.sockname(listen_socket)
    Lakeland.Server.set_addr(ref, addr)
    conn_manager = Lakeland.Server.get_connection_manager(ref)

    children = for n <- Range.new(1, num_of_acceptors) do
      worker(Lakeland.Acceptor, [listen_socket, transport, conn_manager],
             id: {Lakeland.Acceptor, self, n}, shutdown: :brutal_kill)
    end
    options = [strategy: :one_for_one, max_restarts: 1, max_seconds: 5]
    supervise(children, options)
  end

end
