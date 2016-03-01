defmodule Lakeland.Transport.Tcp do
  require Logger
  @behaviour Lakeland.Transport

  @type opt :: {:backlog, non_neg_integer}
  | {:buffer, non_neg_integer}
  | {:delay_send, boolean}
  | {:dontroute, boolean}
  | {:exit_on_close, boolean}
  | {:fd, non_neg_integer}
  | {:high_msgq_watermark, non_neg_integer}
  | {:high_watermark, non_neg_integer}
  | :inet
  | :inet6
  | {:ip, :inet.ip_address}
  | {:keepalive, boolean}
  | {:linger, {boolean, non_neg_integer}}
  | {:low_msgq_watermark, non_neg_integer}
  | {:low_watermark, non_neg_integer}
  | {:nodelay, boolean}
  | {:port, :inet.port_number}
  | {:priority, integer}
  | {:raw, non_neg_integer, non_neg_integer, binary}
  | {:recbuf, non_neg_integer}
  | {:send_timeout, timeout}
  | {:send_timeout_close, boolean}
  | {:sndbuf, non_neg_integer}
  | {:tos, integer}


  def name, do: :tcp
  def secure, do: false
  def messages, do: {:tcp, :tcp_closed, :tcp_error}

  ## 'inet' and 'inet6' are also allowed but they are handled
  ## specifically as they do not have 2-tuple equivalents.
  ##
  ## The 4-tuple 'raw' option is also handled specifically.
  @allowed_listen_option_keys	[
    :backlog,
    :buffer,
    :delay_send,
    :dontroute,
    :exit_on_close,
    :fd,
    :high_msgq_watermark,
    :high_watermark,
    :ip,
    :keepalive,
    :linger,
    :low_msgq_watermark,
    :low_watermark,
    :nodelay,
    :port,
    :priority,
    :recbuf,
    :send_timeout,
    :send_timeout_close,
    :sndbuf,
    :tos
  ]

  @spec listen([opt]) :: {:ok, :inet.socket} | {:error, atom}
  def listen(opts) do
    opts = opts
    |> Keyword.put_new(:backlog, 1024)
    |> Keyword.put_new(:nodelay, true)
    |> Keyword.put_new(:send_timeout, 30000)
    |> Keyword.put_new(:send_timeout_close, true)

    ## We set the port to 0 because it is given in the Opts directly.
    ## The port in the options takes precedence over the one in the
    ## first argument.
    listen_options = filter_options(opts, @allowed_listen_option_keys, [:binary, {:active, false}, {:packet, :raw}, {:reuseaddr, true}])
    :gen_tcp.listen(0, listen_options)
  end

  @spec accept(:inet.socket, timeout) :: {:ok, :inet.socket} | {:error, :closed | :timeout | atom}
  def accept(listen_socket, timeout) do
    :gen_tcp.accept(listen_socket, timeout)
  end

  @spec accept_ack(:inet.socket, timeout) :: :ok
  def accept_ack(_socket, _timeout), do: :ok

  @spec connect(:inet.ip_address | :inet.hostname, :inet.port_number, term, timeout) :: {:ok, :inet.socket} | {:error, atom}
  def connect(host, port, opts, timeout \\ :infinity) do
    :gen_tcp.connect(host, port, opts ++ [:binary, {:active, false}, {:packet, :raw}], timeout)
  end

  @spec recv(:inet.socket, non_neg_integer, timeout)
  :: {:ok, term} | {:error, :closed | atom}
  def recv(socket, length, timeout \\ :infinity) do
    :gen_tcp.recv(socket, length, timeout)
  end

  @spec send(:inet.socket, iodata) :: :ok | {:error, :closed | atom}
  def send(socket, packet) do
    :gen_tcp.send(socket, packet)
  end

  @spec sendfile(:inet.socket, Path.t | File.io_device, non_neg_integer, non_neg_integer, Lakeland.Transport.sendfile_opts)
  :: {:ok, non_neg_integer} | {:error, atom}
  def sendfile(socket, file_or_path, offset \\ 0, bytes \\ 0, opts \\ [])
  def sendfile(socket, file_path, offset, bytes, opts)
  when is_binary(file_path) or is_list(file_path) do # for Path.t(:unicode.chardata), list or binary
    case File.open(file_path, [:read, :raw, :binary]) do
      {:ok, rawfile} ->
        try do
          sendfile(socket, rawfile, offset, bytes, opts)
        after
          :ok = File.close(rawfile)
        end
      {:error, _reason} = error ->
        error
    end
  end
  @default_chunk_size 0x1FFF
  def sendfile(socket, rawfile, offset, bytes, opts) do
    opts = opts |> Keyword.put_new(:chunk_size, @default_chunk_size)
    try do
      :file.sendfile(rawfile, socket, offset, bytes, opts)
    catch
      ## file:sendfile/5 might fail by throwing a
      ## {badmatch, {error, enotconn}}. This is because its
      ## implementation fails with a badmatch in
      ## prim_file:sendfile/10 if the socket is not connected.
      :error, {:badmatch, {:error, :enotconn}} ->
        {:error, :closed}
    end
  end

  @spec setopts(:inet.socket, list) :: :ok | {:error, atom}
  def setopts(socket, opts) do
    :inet.setopts(socket, opts)
  end

  @spec controlling_process(:inet.socket, pid) :: :ok | {:error, :closed | :not_owner | atom}
  def controlling_process(socket, pid) do
    :gen_tcp.controlling_process(socket, pid)
  end

  @spec peername(:inet.socket) :: {:ok, {:inet.ip_address, :inet.port_number}} | {:error, atom}
  def peername(socket) do
    :inet.peername(socket)
  end

  @spec sockname(:inet.socket) :: {:ok, {:inet.ip_address, :inet.port_number}} | {:error, atom}
  def sockname(socket) do
    :inet.sockname(socket)
  end

  @spec shutdown(:inet.socket, :read | :write | :read_write) :: :ok | {:error, atom}
  def shutdown(socket, how) do
    :gen_tcp.shutdown(socket, how)
  end

  @spec close(:inet.socket) :: :ok
  def close(socket) do
    :gen_tcp.close(socket)
  end



  def filter_options(user_opts, allowed_keys, default_opts) do
    allowed_opts = filter_user_options(user_opts, allowed_keys, [])
    default_opts |> Enum.reduce(allowed_opts, fn (opt, acc) ->
      case opt do
        {key, _value} ->
          acc |> List.keystore(key, 0, opt)
        _opt ->
          [opt | acc]
      end
    end)
  end


  ## 2-tuple options
  defp filter_user_options([{key, _value} = opt | tail], allowed_keys, acc) do
    case allowed_keys |> Enum.member?(key) do
      true ->
        filter_user_options(tail, allowed_keys, [opt | acc])
      false ->
        _ = Logger.warn("Transport options #{Kernel.inspect opt} unknown or invalid.\n")
        filter_user_options(tail, allowed_keys, acc)
    end
  end
  ## Special options forms
  defp filter_user_options([:inet | tail], allowed_keys, acc) do
    filter_user_options(tail, allowed_keys, [:inet | acc])
  end
  defp filter_user_options([:inet6 | tail], allowed_keys, acc) do
    filter_user_options(tail, allowed_keys, [:inet6 | acc])
  end
  defp filter_user_options([{:raw, _, _, _} = opt | tail], allowed_keys, acc) do
    filter_user_options(tail, allowed_keys, [opt | acc])
  end
  defp filter_user_options([opt | tail], allowed_keys, acc) do
    _ = Logger.warn("Transport options #{opt} unknown or invalid.\n")
    filter_user_options(tail, allowed_keys, acc)
  end
  defp filter_user_options([], _allowed_keys, acc), do: Enum.reverse(acc)



end
