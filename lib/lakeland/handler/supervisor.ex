defmodule Lakeland.Handler.Supervisor do
  use Supervisor

  def start_link(protocol, conn_type) do
    Supervisor.start_link(__MODULE__, {protocol, conn_type})
  end

  def init({protocol, conn_type}) do
    children = [
      case conn_type do
        :worker ->
          worker(protocol, [], restart: :temporary)
        :supervisor ->
          supervisor(protocol, [], restart: :temporary)
      end
    ]
    supervise_opts = [
      strategy: :simple_one_for_one
    ]
    supervise(children, supervise_opts)
  end

end
