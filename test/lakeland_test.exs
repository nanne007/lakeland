defmodule LakelandTest do
  use ExUnit.Case
  doctest Lakeland

  @ref :echo
  @handler Lakeland.Handler.Echo
  @handler_opts []
  @port 8080
  @num_acceptors 3

  setup do
    {:ok, _child} = Lakeland.start_listener(@ref, @handler, @handler_opts,
                                           [num_acceptors: @num_acceptors, port: @port])

    on_exit fn ->
      :ok = Lakeland.stop_listener(@ref)
    end

    :ok
  end

  test "listener should work" do
    {:ok, socket} = :gen_tcp.connect('localhost', @port, [active: false])
    data = 'hello'
    assert :ok = :gen_tcp.send(socket, data)
    assert {:ok, ^data} = :gen_tcp.recv(socket, 0)
    :gen_tcp.close(socket)
  end


  test "Lakeland should handler listener config correctly" do
    assert {_addr, @port} = Lakeland.get_addr(@ref)
  end

  test "Lakenland should get max connections of a listener" do
    assert 1024 == Lakeland.get_max_connections(@ref)
  end

  test "Lakenland should set max connections of a listener" do
    assert :ok == Lakeland.set_max_connections(@ref, 2048)
    assert 2048 == Lakeland.get_max_connections(@ref)
  end

  test "Lakeland should get handler opts of a listener" do
    assert @handler_opts == Lakeland.get_handler_opts(@ref)
  end

  test "Lakeland should set handler opts of a listener" do
    assert :ok == Lakeland.set_handler_opts(@ref, [one: 1])
    assert [one: 1] == Lakeland.get_handler_opts(@ref)
  end
end
