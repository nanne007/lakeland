defmodule Lakeland.Acceptor.Supervisor do
  use Supervisor

  @spec start_link(Lakeland.ref, non_neg_integer, module, Keyword.t) :: Supervisor.on_start
  def start_link(ref, num_of_acceptors, transport, transport_opts) do
    Supervisor.start_link(__MODULE__, {ref, num_of_acceptors, transport, transport_opts})
  end

  def init({ref, num_of_acceptors, transport, transport_opts}) do
    listen_socket = case transport_opts |> Keyword.fetch(:socket) do
                      {:ok, socket} ->
                        socket
                      :error ->
                        transport_opts = transport_opts
                        |> Keyword.delete(:max_connections)
                        |> Keyword.delete(:ack_timeout)
                        |> Keyword.delete(:connection_type)
                        |> Keyword.delete(:shutdown)
                        |> Keyword.delete(:socket)

                        case transport.listen(transport_opts) do
                          {:ok, socket} ->
                            socket
                          {:error, reason} ->
                            listen_error(ref, transport, transport_opts, reason)
                        end
                    end
    {:ok, addr} = transport.sockname(listen_socket)
    Lakeland.Server.set_addr(ref, addr)
    conn_sup = Lakeland.Server.get_connection_sup(ref)

    children = for n <- Range.new(1, num_of_acceptors) do
      worker(Lakeland.Acceptor, [listen_socket, transport, conn_sup], id: {Lakeland.Acceptor, self, n}, shutdown: :brutal_kill)
    end
    options = [strategy: :one_for_one, max_restarts: 1, max_seconds: 5]
    supervise(children, options)
  end

  defp listen_error(ref, transport, transport_opts, reason) do
    require Logger
    :ok = Logger.error("Failed to start Lakeland listener #{ref} in #{transport}.listen(#{transport_opts}) for reason #{reason} (#{:inet.format_error(reason)})")
    exit({:listen_error, ref, reason})
  end

end
