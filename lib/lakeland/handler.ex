defmodule Lakeland.Handler do
  use Behaviour

  @callback start_link(ref :: Lakeland.ref, socket :: :inet.socket, transport :: module, opts :: Keyword.t) :: {:ok, pid}
end
