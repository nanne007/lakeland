defmodule Lakeland do
  @moduledoc """
  Lakeland is socket acceptor pool for TCP protocols.
  This module provide funtions of starting and controlling Lakeland listeners.
  """

  @type max_conns :: non_neg_integer
  @type conn_type :: :worker | :supervisor
  @type shutdown :: timeout | :brutal_kill
  @type opt :: {:num_acceptors, non_neg_integer}
  | {:ack_timeout, timeout}
  | {:connection_type, conn_type}
  | {:max_connections, max_conns}
  | {:shutdown, shutdown}
  | {:socket, term}
  @type ref :: term

  @doc """
  Start listener `ref` which use `handler` with `handler_opts` to deal with socket connection.

  - `hanlder`: a module which should implement `Lakeland.Handler` behavour.
  - `handler_opts`: a `Keyword` options that would be passed to `Lakeland.Handler.start_link/4`.
  - `listener_opts`: a `Keyword` options to controll the behaviour of the listener.
     It support the following options:
     1. `num_acceptors`(default to `100`): the number of connection acceptors.
     2. `ack_timeout`(default to `5000`): timeout for handler to receive `accept_ack`.
     3. `connection_type`(default to `worker`): the type of handler. The handler will be put into listener's supervisor tree.
     4. `max_connections`(default to `1024`): max connections of the listener.
  - `transport`:  a module which need to implement `Lakeland.Transport` behaviour.
     Lakeland contains `Lakeland.Transport.Tcp` which implements the behavour and is used as default.
     Note that the implementation is just a thin wrapper of `:gen_tcp`.
  """
  @spec start_listener(ref, module, Keyword.t, Keyword.t, module) :: Supervisor.on_start_child
  def start_listener(ref, handler, handler_opts, listener_opts, transport \\ Lakeland.Transport.Tcp)
  when is_atom(transport) and is_atom(handler) do
    {:module, ^transport} = Code.ensure_loaded(transport)
    case function_exported?(transport, :name, 0) do
      false ->
        {:error, :badarg}
      true ->
        # set default listener options if not exists.
        listener_opts = listener_opts
        |> Keyword.put_new(:ack_timeout, 5000)
        |> Keyword.put_new(:connection_type, :worker)
        |> Keyword.put_new(:max_connections, 1024)
        |> Keyword.put_new(:shutdown, 5000)
        |> Keyword.put_new(:num_acceptors, 100)

        import Supervisor.Spec
        listener_sup_args = [ref, handler, handler_opts, listener_opts, transport]
        child_spec = supervisor(Lakeland.Listener.Supervisor, listener_sup_args,
                                id: {Lakeland.Listener.Supervisor, ref})
        res = Supervisor.start_child(Lakeland.Supervisor, child_spec)

        socket = listener_opts |> Keyword.get(:socket, nil)
        _ = case res do
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


  @spec stop_listener(ref) :: :ok | {:error, :not_found}
  def stop_listener(ref) do
    case Lakeland.Supervisor |> Supervisor.terminate_child({Lakeland.Listener.Supervisor, ref}) do
      :ok ->
        _res = Lakeland.Supervisor |> Supervisor.delete_child({Lakeland.Listener.Supervisor, ref})
        Lakeland.Server.cleanup_listener_opts(ref)
      {:error, _reason} = error ->
        error
    end
  end



  @spec accept_ack(ref) :: :ok
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
    Lakeland.Server.get_handler_opts(ref)
  end

  @doc """
  Set handler options of listener `ref` to `opts`
  """
  @spec set_handler_opts(ref, term) :: :ok
  def set_handler_opts(ref, opts) do
    Lakeland.Server.set_handler_opts(ref, opts)
  end

end
