defmodule Lakeland.Handler.Supervisor do
  use Supervisor

  def start_link(handler, conn_type) do
    Supervisor.start_link(__MODULE__, {handler, conn_type})
  end

  def init({handler, conn_type}) do
    children = [
      case conn_type do
        :worker ->
          worker(handler, [], restart: :temporary)
        :supervisor ->
          supervisor(handler, [], restart: :temporary)
      end
    ]
    supervise_opts = [
      strategy: :simple_one_for_one
    ]
    supervise(children, supervise_opts)
  end

end
