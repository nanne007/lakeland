defmodule Lakeland.Supervisor do
  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    :lakeland_server = :ets.new(:lakeland_server, [:ordered_set, :public, :named_table])
    children = [
      worker(Lakeland.Server, [])
    ]
    supervise_opts = [strategy: :one_for_one, max_restarts: 1, max_seconds: 5]
    supervise(children, supervise_opts)
  end

end
