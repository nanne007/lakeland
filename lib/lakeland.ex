defmodule Lakeland do
  @type max_conns :: non_neg_integer | :infinity
  @type opt :: {:ack_timeout, timeout}
  | {:connection_type, :worker | :supervisor}
  | {:max_connections, max_conns}
  | {:shutdown, timeout | :brutal_kill}
  | {:socket, term}
  @type ref :: term

  @doc """
  Start listener `ref` with `nb_acceptors`.
  """
  @spec start_listener(ref, non_neg_integer, module, Keyword.t, module, Keyword.t) :: Supervisor.on_start_child
  def start_listener(ref, nb_acceptors,
                     transport, transport_opts,
                     protocol, protocol_opts)
  when is_integer(nb_acceptors) and is_atom(transport) and is_atom(protocol) do
    {:module, ^transport} = Code.ensure_loaded(transport)

    ## TODO: Remove in 2.0 and simply require ssl.
    _ = ensure_ssl(transport)

    case function_exported?(transport, :name, 0) do
      false ->
        {:error, :badarg}
      true ->
        socket = transport_opts |> Keyword.get(:socket, nil)
        child_spec = child_spec(ref, nb_acceptors, transport, transport_opts, protocol, protocol_opts)

        res = Supervisor.start_child(Lakeland.Supervisor, child_spec)
        case res do
          {:ok, pid} when socket != nil ->
            ## Give the ownership of the socket to Lakeland.Acceptor.Supervisor
            ## to make sure the socket stays open as long as the listener is alive.
            ## If the socket closes however there will be no way to recover
            ## because we don't know how to open it again.
            {_id, acceptor_sup, _type, _module} =
              pid |> Supervisor.which_children() |> List.keyfind(Lakeland.Acceptor.Supervisor, 0)
            ## NOTE: when changing the controlling process of a listen socket because of a bug.
            ## only deal with the happy path.
            :ok = transport.controlling_process(socket, acceptor_sup)
          _ ->
            :ok
        end
        res
    end
  end


  @spec stop_listener(Lakeland.ref) :: :ok | {:error, :not_found}
  def stop_listener(ref) do
    case Lakeland.Supervisor |> Supervisor.terminate_child({Lakeland.Listener.Supervisor, ref}) do
      :ok ->
        _res = Lakeland.Supervisor |> Supervisor.delete_child({Lakeland.Listener.Supervisor, ref})
        Lakeland.Server.cleanup_listener_opts(ref)
      {:error, _reason} = error ->
        error
    end
  end



  @spec accept_ack(Lakeland.ref) :: :ok
  def accept_ack(ref) do
    receive do
      {:shoot, ^ref, transport, socket, ack_timeout} ->
        transport.accept_ack(socket, ack_timeout)
    end
  end

  @doc """
  Get the address which the listener `ref` listens on
  """
  @spec get_addr(ref) :: {:inet.ip_address, :inet.port_number}
  def get_addr(ref) do
    Lakeland.Server.get_addr(ref)
  end

  @doc """
  Get the max connection number of listener `ref`.
  """
  @spec get_max_connections(ref) :: non_neg_integer
  def get_max_connections(ref) do
    Lakeland.Server.get_max_connections(ref)
  end

  @doc """
  Set the max connection number of listern `ref` to `max_conns`.
  It can be set in `transport_opts` through `:max_connections` key.
  If not set, it defaults to `1024`.
  """
  @spec set_max_connections(ref, non_neg_integer) :: :ok
  def set_max_connections(ref, max_conns) do
    Lakeland.Server.set_max_connections(ref, max_conns)
  end

  @doc """
  Get handler options of listener `ref`
  """
  @spec get_handler_opts(ref) :: term
  def get_handler_opts(ref) do
    Lakeland.Server.get_protocol_opts(ref)
  end

  @doc """
  Set handler options of listener `ref` to `opts`
  """
  @spec set_handler_opts(ref, term) :: :ok
  def set_handler_opts(ref, opts) do
    Lakeland.Server.set_protocol_opts(ref, opts)
  end


  defp child_spec(ref, num_of_acceptors, transport, transport_opts, protocol, protocol_opts) do
    import Supervisor.Spec
    listener_sup_args = [ref, num_of_acceptors, transport, transport_opts, protocol, protocol_opts]
    supervisor(Lakeland.Listener.Supervisor, listener_sup_args,
                            id: {Lakeland.Listener.Supervisor, ref})
  end


  defp ensure_ssl(_transport) do
    :ok
  end
end
