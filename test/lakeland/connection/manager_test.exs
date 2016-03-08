defmodule Lakeland.Connection.ManagerTest do
  use ExUnit.Case

  @num_acceptors 3
  @port 8080
  setup do
    {:ok, _listener} = Lakeland.start_listener(:echo, Lakeland.Handler.Echo, [],
                                               [num_acceptors: @num_acceptors, port: @port])

    on_exit fn ->
      Lakeland.stop_listener(:echo)
    end

    :ok
  end


  test "Manager should get active connections" do
    manager = Lakeland.Server.get_connection_manager(:echo)
    assert 0 == manager |> Lakeland.Connection.Manager.active_connections
    random_num = 1..100 |> Enum.random
    sockets = for _n <- 1..random_num do
      {:ok, socket} = :gen_tcp.connect('localhost', @port, [active: false])
      socket
    end

    # sleep for 100 ms to give lakeland a chance to add handler to sup
    receive do
    after
      100 -> :ok
    end

    assert length(sockets) == manager |> Lakeland.Connection.Manager.active_connections

    for socket <- sockets, do: :gen_tcp.close(socket)
  end

end
