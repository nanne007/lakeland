defmodule Lakeland.ServerTest do
  use ExUnit.Case

  test "lakeland server should start correctly" do
    server_pid = Lakeland.Server |> Process.whereis
    assert server_pid |> is_pid
    assert Supervisor.which_children(Lakeland.Supervisor)
    |> List.keymember?(server_pid, 1)
  end

  test "set_new_listener_opts should work" do
    :ok = Lakeland.Server.set_new_listener_opts(TestHandler, 2048, [test: :test])
    assert 2048 == Lakeland.Server.get_max_connections(TestHandler)
    assert [test: :test] == Lakeland.Server.get_protocol_opts(TestHandler)
  end

  test "cleanup_listener_opts should work" do
    :ok = Lakeland.Server.set_new_listener_opts(TestHandler, 2048, [test: :test])
    assert :ok = Lakeland.Server.cleanup_listener_opts(TestHandler)
  end

  test "set_addr should work" do
    addr = {{127, 0, 0, 1}, 8080}
    :ok = Lakeland.Server.set_addr(TestHandler, addr)
    assert addr == Lakeland.Server.get_addr(TestHandler)
  end

end
