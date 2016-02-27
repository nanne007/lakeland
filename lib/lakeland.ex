defmodule Lakeland do
  @type max_conns :: non_neg_integer | :infinity
  @type opt :: {:ack_timeout, timeout}
  | {:connection_type, :worker | :supervisor}
  | {:max_connections, max_conns}
  | {:shutdown, timeout | :brutal_kill}
  | {:socket, term}
  @type ref :: term

  @spec start_listener(ref, non_neg_integer, module, Keyword.t, module, Keyword.t) :: Supervisor.on_start_child
  def start_listener(ref, nb_acceptors,
                     transport_mod, transport_opts,
                     protocol_mod, protocol_opts)
  when is_integer(nb_acceptors) and is_atom(transport_mod) and is_atom(protocol_mod) do
    {:module, ^transport_mod} = Code.ensure_loaded(transport_mod)

    ## TODO: Remove in 2.0 and simply require ssl.
    _ = ensure_ssl(transport_mod)

    case function_exported?(transport_mod, :name, 0) do
      false ->
        {:error, :badarg}
      true ->
        import Supervisor.Spec
        listener_sup_args = [ref, nb_acceptors, transport_mod, transport_opts, protocol_mod, protocol_opts]
        child_spec = supervisor(Lakeland.Listener.Supervisor, listener_sup_args,
                                id: {Lakeland.Listener.Supervisor, ref})
        res = Supervisor.start_child(Lakeland.Supervisor, child_spec)
        socket = transport_opts |> Keyword.get(:socket, nil)
        case res do
          {:ok, pid} when socket != nil ->
            ## Give the ownership of the socket to Lakeland.Acceptor.Supervisor
            ## to make sure the socket stays open as long as the listener is alive.
            ## If the socket closes however there will be no way to recover
            ## because we don't know how to open it again.
            children = Supervisor.which_children(pid)
            {_id, acceptor_sup, _type, _module} = children |> List.keyfind(Lakeland.Acceptor.Supervisor, 0)
            ## NOTE: the catch is here because ssl crashes
            ## when changing the controlling process of a listen socket because of a bug.
            ## The bug will be fixed in R16.
            transport_mod.controlling_process(socket, acceptor_sup)
          _ ->
            :ok
        end
        res
    end
  end

  @spec stop_listener(ref) :: :ok | {:error, :not_found}
  def stop_listener(ref) do
    ## TODO: implement it
  end

  defp ensure_ssl(transport_mod) do
    ## TODO: implement it
  end
end
