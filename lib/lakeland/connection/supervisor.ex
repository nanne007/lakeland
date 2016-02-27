defmodule Lakeland.Connection.Supervisor do
  @type conn_type :: :worker | :supervisor
  @type shutdown :: :brutal_kill | timeout

  defstruct [
    parent: nil,
    ref: nil,
    conn_type: nil,
    shutdown: nil,
    transport: nil,
    protocol: nil,
    opts: nil,
    ack_timeout: nil,
    max_conns: nil
  ]
  @type t :: %__MODULE__{
    parent: nil | pid,
    ref: Lakeland.ref,
    conn_type: conn_type,
    shutdown: shutdown,
    transport: nil | module,
    protocol: nil | module,
    opts: term,
    ack_timeout: timeout,
    max_conns: nil | Lakeland.max_conns
  }

  @spec start_link(Lakeland.ref, conn_type, shutdown, module, timeout, module) :: {:ok, pid}
  def start_link(ref, connection_type, shutdown, transport, ack_timeout, protocol) do
    :proc_lib.start_link(__MODULE__, :init,
                         [self, ref, connection_type, shutdown, transport, ack_timeout, protocol])
  end

  def start_protocol(conn_sup, socket) do
    ## used in Lakeland.Acceptor
    send conn_sup, {__MODULE__, :start_protocol, self, socket}
    receive do
      ^conn_sup ->
        :ok
    end
  end


  def active_connections(conn_sup) do
    ## used in Lakeland.Server.count_connections
    monitor_ref = Process.monitor(conn_sup)
    Process.send(conn_sup, {__MODULE__, :active_connections, self, monitor_ref}, [:noconnect])
    receive do
      {^monitor_ref, ret} ->
        Process.demonitor(monitor_ref, [:flush])
        ret
      {:DOWN, ^monitor_ref, _, _, :noconnection} ->
        Kernel.exit({:nodedown, Kernel.node(conn_sup)})
      {:DOWN, ^monitor_ref, _, _, reason} ->
        Kernel.exit(reason)
    after
      5000 ->
        Process.demonitor(monitor_ref, [:flush])
        Kernel.exit(:timeout)
    end
  end

  ## supervisor internals

  def init(parent, ref, connection_type, shutdown, transport, ack_timeout, protocol) do
    Process.flag(:trap_exit, true)
    :ok = Lakeland.Server.set_connection_sup(ref, self)
    max_connections = Lakeland.Server.get_max_connections(ref)
    opts = LakeLand.Server.get_protocol_options(ref)
    :ok = :proc_lib.init_ack(parent, {:ok, self})
    loop(%__MODULE__{
          parent: parent,
          ref: ref,
          conn_type: connection_type,
          shutdown: shutdown,
          transport: transport,
          protocol: protocol,
          ack_timeout: ack_timeout,
          opts: opts,
          max_conns: max_connections
     }, 0, 0, [])
  end

  defp loop(%__MODULE__{
          parent: parent,
          ref: ref,
          conn_type: connection_type,
          shutdown: shutdown,
          transport: transport,
          protocol: protocol,
          ack_timeout: ack_timeout,
          opts: opts,
          max_conns: max_connections
        } = state, cur_conns, num_of_children, sleepers) do
    receive do
      {__MODULE__, :start_protocol, to, socket} ->
        try do
          protocol.start_link(ref, socket, transport, opts)
        rescue
          error ->
            require Logger
            Logger.error("Lakeland listener #{ref} connection process start failure; #{protocol}.start_link/4 returned: #{error}\n")
            loop(state, cur_conns, num_of_children, sleepers)
        else
          {:ok, pid} ->
            shoot(state, cur_conns, num_of_children, sleepers, to, socket, pid, pid)
          {:ok, sup_pid, protocol_pid} when connection_type == :supervisor ->
            shoot(state, cur_conns, num_of_children, sleepers, to, socket, sup_pid, protocol_pid)
          ret ->
            send(to, self)
            require Logger
            Logger.error("Lakeland listener #{ref} connection process start failure; #{protocol}.start_link/4 returned: #{ret}")
            transport.close(socket)
            loop(state, cur_conns, num_of_children, sleepers)
        end
      {__MODULE__, :active_connections, to, monitor_ref} ->
        Kernel.send(to, {monitor_ref, cur_conns})
        loop(state, cur_conns, num_of_children, sleepers)
      # remove a connection from the count of the connections.
      {:remove_connection, ^ref} ->
        loop(state, cur_conns - 1, num_of_children, sleepers)
      # upgrade the max number of connections allowed concurrently.
      # We resume all sleeping acceptors if the number increases.
      {:set_max_conns, new_max_conns} when new_max_conns > max_connections ->
        for acceptor <- sleepers, do: Kernel.send(acceptor, Kernel.self)
        loop(%{state | max_conns: new_max_conns}, cur_conns, num_of_children, [])
      {:set_max_conns, new_max_conns} ->
        loop(%{state | max_conns: new_max_conns}, cur_conns, num_of_children, sleepers)
      {:set_opts, new_opts} ->
        loop(%{state | opts: new_opts}, cur_conns, num_of_children, sleepers)
      {:EXIT, ^parent, reason} ->
        terminate(state, reason, num_of_children)
      {:EXIT, child_pid, reason} when length(sleepers) == 0 ->
        report_error(ref, protocol, child_pid, reason)
        Process.delete(child_pid)
        loop(state, cur_conns - 1, num_of_children - 1, sleepers)
      {:EXIT, child_pid, reason} -> # resume a sleeping acceptor
        report_error(ref, protocol, child_pid, reason)
        Process.delete(child_pid)
        [acceptor | remained_sleepers] = sleepers
        Kernel.send(acceptor, Kernel.self)
        loop(state, cur_conns - 1, num_of_children - 1, remained_sleepers)
      {:system, from, req} ->
        :sys.handle_system_msg(req, from, parent, __MODULE__, [], {state, cur_conns, num_of_children, sleepers})

      {:'$gen_call', {to, tag}, :which_children} ->
        children = for child_pid <- Process.get_keys(true), do: {protocol, child_pid, connection_type, [protocol]}
        Kernel.send(to, {tag, children})
        loop(state, cur_conns, num_of_children, sleepers)
      {:'$gen_call', {to, tag}, :count_children} ->
        counts = case connection_type do
                   :worker -> [{:supervisors, 0}, {:workers, num_of_children}]
                   :supervisor -> [{:supervisors, num_of_children}, {:workers, 0}]
                 end
        counts = [{:specs, 1}, {:active, num_of_children} | counts]
        ## TODO: verify the type of counts
        Kernel.send(to, {tag, counts})
        loop(state, cur_conns, num_of_children, sleepers)
      {:'$gen_call', {to, tag}, _} ->
        Kernel.send(to, {tag, {:error, __MODULE__}})
        loop(state, cur_conns, num_of_children, sleepers)
      msg ->
        require Logger
        Logger.error("Lakeland listener #{ref} received unexpected message #{msg}\n")
    end

  end



  def system_continue(_, _, {state, cur_conns, num_of_children, sleepers}) do
    loop(state, cur_conns, num_of_children, sleepers)
  end
  def system_terminate(reason, _, _, {state, _cur_conns, num_of_children, _sleepers}) do
    terminate(state, reason, num_of_children)
  end
  def system_code_change(misc, _, _, _) do
    {:ok, misc}
  end

  def report_error(_ref, _protocol, _pid, :normal), do: :ok
  def report_error(_ref, _protocol, _pid, :shutdown), do: :ok
  def report_error(_ref, _protocol, _pid, {:shutdown, _}), do: :ok
  def report_error(ref, protocol, pid, reason) do
    require Logger
    Logger.error("Lakeland listener #{ref} has connection process started with #{protocol}.start_link/4 at #{pid} exit with reason: #{reason}\n")
  end

    defp shoot(%__MODULE__{
            ref: ref,
            transport: transport,
            ack_timeout: ack_timeout,
            max_conns: max_conns
         } = state, cur_conns, num_of_children, sleepers, to, socket, sup_pid, protocol_pid) do
    case transport.controlling_process(socket, protocol_pid) do
      :ok ->
        Kernel.send(protocol_pid, {:shoot, ref, transport, socket, ack_timeout})
        Process.put(sup_pid, true)
        new_cur_conns = cur_conns + 1
        if new_cur_conns < max_conns do
          Kernel.send(to, Kernel.self)
          loop(state, new_cur_conns, num_of_children + 1, sleepers)
        else
          loop(state, new_cur_conns, num_of_children + 1, [to|sleepers])
        end
      {:error, _reason} ->
        transport.close(socket)
        Process.exit(sup_pid, :kill)
        loop(state, cur_conns, num_of_children, sleepers)
    end
  end

  ## kill all children and then exit.we unlink first to avoid
  ## getting a message for each child getting killed.
  defp terminate(%__MODULE__{shutdown: :brutal_kill}, reason, _num_of_children) do
    children_pids = Process.get_keys(true)
    for child <- children_pids do
      Process.unlink(child)
      Process.exit(child, :kill)
    end
    Kernel.exit(reason)
  end
  ## Attempt to gracefully shutdown all children.
  defp terminate(%__MODULE__{shutdown: shutdown}, reason, num_of_children) do
    shutdown_children()
    if shutdown == :infinity do
      :ok
    else
      Kernel.self |> Process.send_after(:kill, shutdown)
    end
    wait_children(num_of_children)
  end

  defp shutdown_children() do
    children_pids = Process.get_keys(true)
    for child <- children_pids do
      Process.monitor(child)
      Process.unlink(child)
      Process.exit(child, :shutdown)
    end
    :ok
  end

  defp wait_children(0), do: :ok
  defp wait_children(num_of_children) do
    receive do
      {:DOWN, _, :process, pid, _} ->
        Process.delete(pid)
        wait_children(num_of_children - 1)
      # timeout, kill the left children
      :kill ->
        left_children_pids = Process.get_keys(true)
        for child <- left_children_pids, do: Process.exit(child, :kill)
        :ok
    end
  end


end
