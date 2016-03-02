defmodule LakelandTest do
  use ExUnit.Case
  doctest Lakeland

  defmodule Echo.Handler do
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

  @port 8080
  test "echo should work as it is" do
    {:ok, child} = Lakeland.start_listener(Echo, 3, Lakeland.Transport.Tcp, [port: @port], Echo.Handler, [])
    children = Supervisor.which_children(Lakeland.Supervisor)
    assert children |> List.keymember?(child, 1)

    {:ok, socket} = :gen_tcp.connect('localhost', @port, [active: false])
    data = 'hello'
    assert :ok = :gen_tcp.send(socket, data)
    assert {:ok, ^data} = :gen_tcp.recv(socket, 0)
    :gen_tcp.close(socket)
  end
end
