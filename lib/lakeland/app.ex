defmodule Lakeland.App do
  use Application

  def start(_type, _args) do
    consider_profiling()
    Lakeland.Supervisor.start_link()
  end

  @spec profile_output() :: :ok
  def profile_output() do
    :eprof.stop_profiling()
    :eprof.log("procs.profile")
    :eprof.analyze(:procs)
    :eprof.log("total.profile")
    :eprof.analyze(:total)
  end

  defp consider_profiling() do
    case Application.get_env(__MODULE__, :profile) do
      {:ok, true} ->
        {:ok, _} = :eprof.start()
        :eprof.start_profiling([self])
      _ ->
        :not_profiling
    end
  end
end
