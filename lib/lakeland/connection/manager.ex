defmodule Lakeland.Connection.Manager do
  use GenServer

  @type conn_type :: :worker | :supervisor
  @type shutdown :: :brutal_kill | timeout

  defstruct [
#    parent: nil,
    ref: nil,
#    conn_type: nil,
#    shutdown: nil,
    transport: nil,
    protocol: nil,
    protocol_opts: nil,
    sleepers: [],
    handler_sup: nil
#    ack_timeout: nil,
#    max_conns: nil
  ]
  @type t :: %__MODULE__{
#    parent: nil | pid,
    ref: Lakeland.ref,
#    conn_type: conn_type,
#    shutdown: shutdown,
    transport: nil | module,
    protocol: nil | module,
    protocol_opts: term,
    sleepers: [pid],
    handler_sup: pid
 #   ack_timeout: timeout,
 #   max_conns: nil | Lakeland.max_conns
  }

  @spec start_link(Lakeland.ref, conn_type, shutdown, timeout, module, module) :: GenServer.on_start
  def start_link(ref, conn_type, _shutdown, _ack_timeout, transport, protocol) do
    GenServer.start_link(__MODULE__, {ref, conn_type, transport, protocol})
  end

  def start_protocol(manager, socket) do
    caller = Kernel.self
    :ok = manager |> GenServer.call({:start_protocol, caller, socket})
    :ok
  end


  def init({ref, conn_type, transport, protocol}) do
    {:ok, handler_sup} = Supervisor.start_link(Lakeland.Handler.Supervisor, [protocol, conn_type])

    Lakeland.Server.set_connection_sup(ref, Kernel.self)

    _max_conns = Lakeland.Server.get_max_connections(ref)
    protocol_opts = Lakeland.Server.get_protocol_opts(ref)
    state = %__MODULE__{
      ref: ref,
      transport: transport,
      protocol: protocol,
      protocol_opts: protocol_opts,
      sleepers: [],
      handler_sup: handler_sup
    }
    {:ok, state}
  end

  def handle_call({:start_protocol, caller, socket}, _from,
                  %__MODULE__{
                    ref: ref,
                    transport: transport,
                    protocol: protocol,
                    protocol_opts: protocol_opts,
                    handler_sup: handler_sup
                  } = state) do

    case handler_sup |> Supervisor.start_child([ref, socket, transport, protocol_opts]) do
      {:error, reason} = error ->
        require Logger
        :ok = Logger.error("Lakeland listener #{ref} connection handler process start failure; " <>
          "#{protocol}.start_link/4 crashed with reason: #{reason}\n")
        {:reply, error, state}
      {:ok, child} when child != :undefined ->
        case transport.controlling_process(socket, child) do
          :ok ->
            Kernel.send(child, {:shoot, ref, transport, socket})
            {:reply, :ok, state}
          {:error, _reason} = error ->
            transport.close(socket)
            _res = handler_sup |> Supervisor.terminate_child(child)
            {:reply, error, state}
        end
      {:ok, child, _info} when child != :undefined ->
        case transport.controlling_process(socket, child) do
          :ok ->
            Kernel.send(child, {:shoot, ref, transport, socket})

            {:reply, :ok, state}
          {:error, _reason} = error ->
            transport.close(socket)
           _res =  handler_sup |> Supervisor.terminate_child(child)
            {:reply, error, state}
        end
    end
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
