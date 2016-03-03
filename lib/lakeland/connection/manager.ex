defmodule Lakeland.Connection.Manager do
  use GenServer

  @type conn_type :: :worker | :supervisor
  @type shutdown :: :brutal_kill | timeout

  defstruct [
#    parent: nil,
    ref: nil,
#    conn_type: nil,
#    shutdown: nil,
    ack_timeout: nil,
    transport: nil,
    protocol: nil,
    protocol_opts: nil,
    max_conns: nil,
    sleepers: [],
    handler_sup: nil
  ]
  @type t :: %__MODULE__{
#    parent: nil | pid,
    ref: Lakeland.ref,
#    conn_type: conn_type,
#    shutdown: shutdown,
    ack_timeout: timeout,
    transport: module,
    protocol: module,
    protocol_opts: term,
    max_conns: Lakeland.max_conns,
    sleepers: [pid],
    handler_sup: pid
  }

  @spec start_link(Lakeland.ref, conn_type, shutdown, timeout, module, module) :: GenServer.on_start
  def start_link(ref, conn_type, _shutdown, ack_timeout, transport, protocol) do
    GenServer.start_link(__MODULE__, {ref, conn_type, ack_timeout, transport, protocol})
  end

  @doc """
  Given the connection `manager`, start a connection handler at given `socket`.
  It is intended to be called from `Lakeland.Acceptor` when accepting a connection.
  """
  @spec start_protocol(pid, :inet.socket) :: :ok | {:error, atom}
  def start_protocol(manager, socket) do
    case manager |> GenServer.call({:start_protocol, socket}) do
      :ok -> :ok
      {:ok, :sleep} ->
        receive do
          ^manager ->
            :ok
        end
      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Return the number of connections managed by the process.
  It delegates to  `count_children` of the linked `Connection.Supervisor`.
  """
  @spec active_connections(pid) :: non_neg_integer
  def active_connections(manager) do
    manager |> GenServer.call(:active_connections)
  end


  def init({ref, conn_type, ack_timeout, transport, protocol}) do
    {:ok, handler_sup} = Supervisor.start_link(Lakeland.Handler.Supervisor, {protocol, conn_type})

    Lakeland.Server.set_connection_sup(ref, Kernel.self)

    max_conns = Lakeland.Server.get_max_connections(ref)
    protocol_opts = Lakeland.Server.get_protocol_opts(ref)
    state = %__MODULE__{
      ref: ref,
      ack_timeout: ack_timeout,
      transport: transport,
      protocol: protocol,
      protocol_opts: protocol_opts,
      max_conns: max_conns,
      sleepers: [],
      handler_sup: handler_sup
    }
    {:ok, state}
  end

  def handle_call(:active_connections, _from,
                  %__MODULE__{
                    handler_sup: handler_sup
                  } = state) do
    conn_num = handler_sup |> Supervisor.count_children |> Map.fetch!(:active)
    {:reply, conn_num, state}
  end

  def handle_call({:start_protocol, socket}, from,
                  %__MODULE__{
                    ref: ref,
                    ack_timeout: ack_timeout,
                    transport: transport,
                    protocol: protocol,
                    protocol_opts: protocol_opts,
                    max_conns: max_conns,
                    sleepers: sleepers,
                    handler_sup: handler_sup
                  } = state) do

    case handler_sup |> Supervisor.start_child([ref, socket, transport, protocol_opts]) do
      {:error, reason} = error ->
        require Logger
        :ok = Logger.error("Lakeland listener #{inspect ref} connection handler process start failure; " <>
          "#{inspect protocol}.start_link/4 crashed with reason: #{inspect reason}\n")
        {:reply, error, state}
      {:ok, child} when child != :undefined ->
        # monitor the handler in order to receive exit signal to release sleeped acceptors
        Process.monitor(child)
        case transport.controlling_process(socket, child) do
          {:error, _reason} = error ->
            transport.close(socket)
            _res = handler_sup |> Supervisor.terminate_child(child)
            {:reply, error, state}
          :ok ->
            Kernel.send(child, {:shoot, ref, transport, socket, ack_timeout})
            if (cur_conns(handler_sup) < max_conns) do
              {:reply, :ok, state}
            else
              {:reply, {:ok, :sleep},
               %{state | sleepers: [from|sleepers]}
              }
            end
        end
      {:ok, child, _info} when child != :undefined ->
        Process.monitor(child)
        case transport.controlling_process(socket, child) do
          {:error, _reason} = error ->
            transport.close(socket)
            _res = handler_sup |> Supervisor.terminate_child(child)
            {:reply, error, state}
          :ok ->
            Kernel.send(child, {:shoot, ref, transport, socket, ack_timeout})
            if (cur_conns(handler_sup) < max_conns) do
              {:reply, :ok, state}
            else
              {:reply, {:ok, :sleep},
               %{state | sleepers: [from | sleepers]}
              }
            end
        end
    end
  end

  def handler_info({:DOWN, _ref, :process, _handler_pid, _reason},
                   %__MODULE__{
                     sleepers: sleepers
                   } = state) when length(sleepers) == 0 do
    ## TODO: report child down message
    {:noreply, state}
  end
  def handler_info({:DOWN, _ref, :process, _handler_pid, _reason},
                   %__MODULE__{
                     sleepers: sleepers
                   } = state) do
    ## TODO: report child down message
    [caller | remained_sleepers] = sleepers
    Kernel.send(caller, Kernel.self)
    {:noreply, %{state | sleepers: remained_sleepers}}
  end


  defp cur_conns(handler_sup) do
    # currently, return the number of active children
    handler_sup |> Supervisor.count_children |> Map.fetch!(:active)
  end



  #   @doc """
  #   set max connections number
  #   """
  #   def handle_call({:set_max_conns, new_max_conns}, _from,
  #                   %__MODULE__{max_conns: max_conns, sleepers: sleepers} = state)
  #   when new_max_conns > max_conns do
  #     for acceptor <- sleepers, do: Kernel.send(acceptor, Kernel.self)
  #     {:reply, :ok, %{state | max_conns: new_max_conns, sleepers: []}}
  #   end
  #   def handle_call({:set_max_conns, new_max_conns}, _from, state) do
  #     {:reply, :ok, %{state | max_conns: new_max_conns}}
  #   end

  #   @doc """
  #   set protocol options
  #   """
  #   def handle_call({:set_protocol_opts, new_protocol_opts}, _from, state) do
  #     {:reply, :ok, %{state | protocol_opts: new_protocol_opts}}
  #   end
  # end

end
