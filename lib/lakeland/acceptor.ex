### The acceptor of lakeland.
defmodule Lakeland.Acceptor do

  @spec start_link(:inet.socket, module, pid) :: {:ok, pid}
  def start_link(listen_socket, transport, conn_sup) do
    pid = spawn_link(__MODULE__, :loop, [listen_socket, transport, conn_sup])
    {:ok, pid}
  end

  def loop(listen_socket, transport, conn_sup) do
    case transport.accept(listen_socket, :infinity) do
      {:ok, conn_socket} ->
        case transport.controlling_process(conn_socket, conn_sup) do
          :ok ->
            # this call will not return until process has been started
            # and we are below the maximum number of connections
            _res = Lakeland.Connection.Supervisor.start_protocol(conn_sup, conn_socket)
          {:error, _} ->
            transport.close(conn_socket)
        end
        # reduce the accept rate if we run out of file descriptors.
        # we cannot accept anymore anyway, so we might as well wait
        # a little while for the situation to resolve itself.
      {:error, :emfile} ->
        receive do
        after
          100 ->
            :ok
        end
      # we want to crash if the listening socket got closed.
      {:error, reason} when reason != :closed ->
        :ok
    end

    flush()

    __MODULE__.loop(listen_socket, transport, conn_sup)
  end

  defp flush() do
    require Logger
    receive do
      msg ->
        :ok = Logger.error("#{__MODULE__} received unexpected message: #{msg}")
        flush()
    after
      0 ->
        :ok
    end
  end

end
