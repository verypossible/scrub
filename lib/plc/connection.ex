defmodule PLC.Connection do
  use Connection
  import PLC.Utils

  alias PLC.Session

  @default_port 44818

  def start_link(host, port \\ @default_port, socket_opts \\ [], timeout \\ 5000)
  def start_link(host, port, socket_opts, timeout) when is_binary(host) do
    start_link(ip_to_tuple!(host), port, socket_opts, timeout)
  end

  def start_link(host, port, socket_opts, timeout) do
    Connection.start_link(__MODULE__, {host, port, socket_opts, timeout})
  end

  def send(conn, data), do: Connection.call(conn, {:send, data})

  def recv(conn, bytes, timeout \\ 3000) do
    Connection.call(conn, {:recv, bytes, timeout})
  end

  def close(conn), do: Connection.call(conn, :close)

  def init({host, port, socket_opts, timeout}) do
    enforced_opts = [packet: :raw, mode: :binary, active: false]
    # :gen_tcp.connect gives priority to options at tail, rather than head.
    socket_opts = Enum.reverse(socket_opts, enforced_opts)

    s = %{host: host, port: port, socket_opts: socket_opts, timeout: timeout, sock: nil, session_handle: nil}
    {:connect, :init, s}
  end

  def connect(_, %{sock: nil, host: host, port: port, socket_opts: socket_opts,
  timeout: timeout} = s) do
    case :gen_tcp.connect(host, port, socket_opts, timeout) do
      {:ok, sock} ->
        register_session(%{s | sock: sock})

      {:error, _} ->
        {:backoff, 1000, s}
    end
  end

  def disconnect(info, %{sock: sock} = s) do
    :ok = :gen_tcp.close(sock)
    case info do
      {:close, from} ->
        Connection.reply(from, :ok)
      {:error, :closed} ->
        :error_logger.format("Connection closed~n", [])
      {:error, reason} ->
        reason = :inet.format_error(reason)
        :error_logger.format("Connection error: ~s~n", [reason])
    end
    {:connect, :reconnect, %{s | sock: nil}}
  end

  def handle_call(_, _, %{sock: nil} = s) do
    {:reply, {:error, :closed}, s}
  end

  def handle_call({:send, data}, _, %{sock: sock} = s) do
    case :gen_tcp.send(sock, data) do
      :ok ->
        {:reply, :ok, s}
      {:error, _} = error ->
        {:disconnect, error, error, s}
    end
  end

  def handle_call({:recv, bytes, timeout}, _, %{sock: sock} = s) do
    case :gen_tcp.recv(sock, bytes, timeout) do
      {:ok, _} = ok ->
        {:reply, ok, s}
      {:error, :timeout} = timeout ->
        {:reply, timeout, s}
      {:error, _} = error ->
        {:disconnect, error, error, s}
    end
  end

  def handle_call(:close, from, s) do
    {:disconnect, {:close, from}, s}
  end

  def register_session(%{sock: sock} = s) do
    with :ok <- :gen_tcp.send(sock, Session.register()),
         {:ok, packet} <- :gen_tcp.recv(sock, 0, :infinity),
         {:ok, session_handle} <- Session.register_reply(packet) do

        IO.puts "Session_handle: #{inspect session_handle}"
        {:ok, %{s | session_handle: session_handle}}
    else
      error ->
        IO.inspect error
        :gen_tcp.close(sock)
        {:backoff, 1000, %{s | sock: nil}}
    end
  end

  def unregister_session(%{sock: sock} = s) do

  end
end
