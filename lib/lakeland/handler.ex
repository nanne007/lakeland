defmodule Lakeland.Handler do
  use Behaviour

  @callback start_link(Lakeland.ref, :inet.socket, module, Keyword.t) :: {:ok, pid}
end
