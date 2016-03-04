defmodule LakelandTest do
  use ExUnit.Case
  doctest Lakeland

  @port 8080
  test "echo should work as it is" do
    {:ok, child} = Lakeland.start_listener(:echo, Lakeland.Handler.Echo, [], [num_acceptors: 3, port: @port])
    children = Supervisor.which_children(Lakeland.Supervisor)
    assert children |> List.keymember?(child, 1)

    {:ok, socket} = :gen_tcp.connect('localhost', @port, [active: false])
    data = 'hello'
    assert :ok = :gen_tcp.send(socket, data)
    assert {:ok, ^data} = :gen_tcp.recv(socket, 0)
    :gen_tcp.close(socket)
  end
end
