defmodule Lakeland.Server do
  use GenServer
  @moduledoc """
  #{__MODULE__} is an frontend of the lakeland_server ets table.
  """

  @table :lakeland_server

  defstruct monitors: []
  @type t :: %__MODULE__{
    monitors: [{{reference(), pid()}, term()}]
  }

  @doc """
  When started, it's registered as name: `#{__MODULE__}`
  """
  @spec start_link() :: {:ok, pid}
  def start_link() do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  @spec set_new_listener_opts(Lakeland.ref, Lakeland.max_conns, term) :: :ok
  def set_new_listener_opts(ref, max_conns, protocol_opts) do
    :ok = GenServer.call(__MODULE__, {:set_new_listener_opts, ref, max_conns, protocol_opts})
    :ok
  end

  @spec cleanup_listener_opts(Lakeland.ref) :: :ok
  def cleanup_listener_opts(ref) do
    :ets.delete(@table, {:addr, ref})
    :ets.delete(@table, {:max_conns, ref})
    :ets.delete(@table, {:opts, ref})
    # the deletion of :conn_manager is handled by monitoring,
    # see below about the handle of `:DOWN` message.
    :ok
  end

  @spec set_connection_sup(Lakeland.ref, pid) :: :ok
  def set_connection_sup(ref, pid) do
    true = GenServer.call(__MODULE__, {:set_connection_manager, ref, pid})
    :ok
  end

  @spec get_connection_sup(Lakeland.ref) :: pid
  def get_connection_sup(ref) do
    :ets.lookup_element(@table, {:conn_manager, ref}, 2)
  end

  @spec set_addr(Lakeland.ref, {:inet.ip_address, :inet.port_number}) :: :ok
  def set_addr(ref, addr) do
    :ok = GenServer.call(__MODULE__, {:set_addr, ref, addr})
    :ok
  end

  @spec get_addr(Lakeland.ref) :: {:inet.ip_address, :inet.port_number}
  def get_addr(ref) do
    :ets.lookup_element(@table, {:addr, ref}, 2)
  end

  @spec set_max_connections(Lakeland.ref, Lakeland.max_conns) :: :ok
  def set_max_connections(ref, max_conns) do
    :ok = GenServer.call(__MODULE__, {:set_max_conns, ref, max_conns})
    :ok
  end

  @spec get_max_connections(Lakeland.ref) :: Lakeland.max_conns
  def get_max_connections(ref) do
    :ets.lookup_element(@table, {:max_conns, ref}, 2)
  end

  @spec set_protocol_opts(Lakeland.ref, term) :: :ok
  def set_protocol_opts(ref, opts) do
    :ok = GenServer.call(__MODULE__, {:set_opts, ref, opts})
    :ok
  end

  @spec get_protocol_opts(Lakeland.ref) :: term
  def get_protocol_opts(ref) do
    :ets.lookup_element(@table, {:opts, ref}, 2)
  end

  @spec count_connections(Lakeland.ref) :: non_neg_integer
  def count_connections(ref) do
    conn_sup = get_connection_sup(ref)
    Lakeland.Connection.Manager.active_connections(conn_sup)
  end


  # gen_server callback

  def init({}) do
    # recover from ets.
    monitors = for [ref, pid] <- :ets.match(@table, {{:conn_manager, "$1"}, "$2"}) do
      {{Process.monitor(pid), pid}, ref}
    end

    {:ok, %__MODULE__{monitors: monitors}}
  end

  def handle_call({:set_new_listener_opts, ref, max_conns, opts}, _from, state) do
    :ets.insert(@table, {{:max_conns, ref}, max_conns})
    :ets.insert(@table, {{:opts, ref}, opts})
    {:reply, :ok, state}
  end

  def handle_call({:set_connection_manager, ref, pid}, _from, %__MODULE__{monitors: monitors} = state) do
    case :ets.insert_new(@table, {{:conn_manager, ref}, pid}) do
      true ->
        monitor_ref = Process.monitor(pid)
        {:reply, true, %__MODULE__{monitors: [{{monitor_ref, pid}, ref} | monitors]}}
      false ->
        {:reply, false, state}
    end
  end

  def handle_call({:set_addr, ref, addr}, _from, state) do
    true = :ets.insert(@table, {{:addr, ref}, addr})
    {:reply, :ok, state}
  end

  def handle_call({:set_max_conns, ref, max_conns}, _from, state) do
    true = :ets.insert(@table, {{:max_conns, ref}, max_conns})

    # change the max_conns of the corresponding connection supervisor
    conn_sup = get_connection_sup(ref)
    send(conn_sup, {:set_max_conns, max_conns})

    {:reply, :ok, state}
  end

  def handle_call({:set_opts, ref, opts}, _from, state) do
    true = :ets.insert(@table, {{:opts, ref}, opts})

    conn_sup = get_connection_sup(ref)
    send(conn_sup, {:set_opts, opts})

    {:reply, :ok, state}
  end

  def handle_info({:DOWN, monitor_ref, :process, pid, _reason}, %__MODULE__{monitors: monitors}) do
    {{_monitor_ref, _pid}, ref} = monitors |> List.keyfind({monitor_ref, pid}, 0)
    true = :ets.delete(@table, {:conn_manager, ref})
    monitors = monitors |> List.keydelete({monitor_ref, pid}, 0)
    {:noreply, %__MODULE__{monitors: monitors}}
  end

end
