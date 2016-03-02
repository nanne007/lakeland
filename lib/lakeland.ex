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

  @spec accept_ack(Lakeland.ref) :: :ok
  def accept_ack(ref) do
    receive do
      {:shoot, ^ref, transport, socket, ack_timeout} ->
        transport.accept_ack(socket, ack_timeout)
    end
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
