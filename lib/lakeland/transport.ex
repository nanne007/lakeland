defmodule Lakeland.Transport do
  @typep socket :: term
  @typep opts :: term
  @type sendfile_opts :: [chunk_size: non_neg_integer]

  @callback name() :: atom
  @callback secure() :: boolean
  @callback messages() :: {atom, atom, atom}
  @callback listen(opts) :: {:ok, socket} | {:error, atom}
  @callback accept(socket, timeout) :: {:ok, socket} | {:error, :closed | :timeout | atom}
  @callback accept_ack(socket, timeout) :: :ok
  @callback connect(String.t, :inet.port_number, opts) :: {:ok, socket} | {:error, atom}
  @callback connect(String.t, :inet.port_number, opts, timeout) :: {:ok, socket} | {:error, atom}
  @callback recv(socket, non_neg_integer, timeout) :: {:ok, term} | {:error, :closed | :timeout | atom}
  @callback send(socket, iodata) :: :ok | {:error, atom}
  @callback sendfile(socket, Path.t | File.io_device) :: {:ok, non_neg_integer} | {:error, atom}
  @callback sendfile(socket, Path.t | File.io_device, non_neg_integer, non_neg_integer) :: {:ok, non_neg_integer} | {:error, atom}
  @callback sendfile(socket, Path.t | File.io_device, non_neg_integer, non_neg_integer, sendfile_opts) :: {:ok, non_neg_integer} | {:error, atom}
  @callback setopts(socket, opts) :: :ok | {:error, atom}
  @callback controlling_process(socket, pid) :: :ok | {:error, :closed | :not_owner | atom}
  @callback peername(socket) :: {:ok, {:inet.ip_address, :inet.port_number}} | {:error, atom}
  @callback sockname(socket) :: {:ok, {:inet.ip_address, :inet.port_number}} | {:error, atom}
  @callback shutdown(socket, :read | :write | :read_write) :: :ok | {:error, atom}
  @callback close(socket) :: :ok

  @doc """
  A fallback for transports that don't have a native sendfile implementation.
  Note that the ordering of arguments is different from :file.sendfile/5 and
  that this function accepts either a raw file or a file name.
  """
  @spec sendfile(module, socket, Path.t | File.io_device, non_neg_integer, non_neg_integer, sendfile_opts) :: {:ok, non_neg_integer} | {:error, atom}
  def sendfile(transport, socket, filename, offset, bytes, opts)
  when is_list(filename) or is_atom(filename) or is_binary(filename) do
    chunk_size = chunk_size(opts)

    case File.open(filename, [:read, :raw, :binary]) do
      {:ok, rawfile} ->
        try do
          # readjust the position if not from the beginning
          if offset != 0 do
            {:ok, ^offset} = :file.position(rawfile, {:bof, offset})
            :ok
          end

          sendfile_loop(transport, socket, rawfile, bytes, 0, chunk_size)
        after
          :ok = File.close(rawfile)
        end
      {:error, _reason} = error ->
        error
    end
  end
  def sendfile(transport, socket, rawfile, offset, bytes, opts) do
    chunk_size = chunk_size(opts)

    {:ok, initial} = :file.position(rawfile, {:cur, 0})
    if initial != offset do
      {:ok, ^offset} = :file.position(rawfile, {:bof, offset})
      :ok
    end

    case sendfile_loop(transport, socket, rawfile, bytes, 0, chunk_size) do
      {:ok, _sent} = result ->
        {:ok, ^initial} = :file.position(rawfile, {:bof, initial})
        result
      {:error, _reason} = error ->
        error
    end
  end


  defp sendfile_loop(_transport, _socket, _rawfile, sent, sent, _chunk_size) when sent != 0 do
    # all requested data has been read and sent, return number of bytes sent.
    {:ok, sent}
  end
  defp sendfile_loop(transport, socket, rawfile, bytes, sent, chunk_size) do
    read_size = read_size(bytes, sent, chunk_size)
    case IO.read(rawfile, read_size) do
      :eof ->
        {:ok, sent}
      {:error, _reason} = error ->
        error
      data ->
        case transport.send(socket, data) do
          {:error, _reason} = error ->
            error
          :ok ->
            sent = IO.iodata_length(data) + sent
            sendfile_loop(transport, socket, rawfile, bytes, sent, chunk_size)
        end
    end
  end


  defp read_size(0, _sent, chunk_size), do: chunk_size
  defp read_size(bytes, sent, chunk_size) do
    Kernel.min(bytes - sent, chunk_size)
  end




  @default_chunk_size 0x1FFF
  @spec chunk_size(sendfile_opts) :: pos_integer
  defp chunk_size(opts) do
    # default to @default_chunk_size when key not found
    case Keyword.get(opts, :chunk_size,  @default_chunk_size) do
      {:chunk_size, 0} ->
        @default_chunk_size
      {:chunk_size, chunk_size} when is_integer(chunk_size) and chunk_size > 0 ->
        chunk_size
    end
  end

end
