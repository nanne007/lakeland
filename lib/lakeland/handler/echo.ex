defmodule Lakeland.Handler.Echo do
  def start_link(ref, socket, transport, opts) do
    pid = Kernel.spawn_link(__MODULE__, :init, [ref, socket, transport, opts])
    {:ok, pid}
  end

  def init(ref, socket, transport, _opts) do
    :ok = Lakeland.accept_ack(ref)
    loop(socket, transport)
  end

  defp loop(socket, transport) do
    case transport.recv(socket, 0) do
      {:ok, data} ->
        transport.send(socket, data)
        loop(socket, transport)
      _ ->
        :ok = transport.close(socket)
    end
  end
end
