defmodule Scrub.Session do
  use Connection
  import Scrub.Utils

  require Logger

  alias Scrub.Session.Protocol

  @default_port 44818

  def start_link(host, port \\ @default_port, socket_opts \\ [], timeout \\ 5000)

  def start_link(host, port, socket_opts, timeout) when is_binary(host) do
    start_link(ip_to_tuple!(host), port, socket_opts, timeout)
  end

  def start_link(host, port, socket_opts, timeout) do
    Connection.start_link(__MODULE__, {host, port, socket_opts, timeout})
  end

  @doc """
  2-4.7 SendRRData

  Used for sending unconnected messages.
  """
  def send_rr_data(session, data) do
    Connection.call(session, {:send_rr_data, data})
  end

  @doc """
  2-4.8 SendUnitData

  Used for sending connected messages.
  Requires passing the O->T Network Connection ID
  This Network Connection ID is obtained by using send_rr_data to
  establish a connection to the target's connection manager object.
  """
  def send_unit_data(session, conn, data) do
    Connection.call(session, {:send_unit_data, conn, data})
  end

  def close(session), do: Connection.call(session, :close)

  # Connection behaviour
  @impl true
  def init({host, port, socket_opts, timeout}) do
    enforced_opts = [packet: :raw, mode: :binary, active: false, keepalive: true]
    # :gen_tcp.connect gives priority to options at tail, rather than head.
    socket_opts = Enum.reverse(socket_opts, enforced_opts)

    s = %{
      host: host,
      port: port,
      socket_opts: socket_opts,
      timeout: timeout,
      socket: nil,
      session_handle: nil,
      sequence_number: 1
    }

    {:connect, :init, s}
  end

  @impl true
  def connect(
        _,
        %{socket: nil, host: host, port: port, socket_opts: socket_opts, timeout: timeout} = s
      ) do
    case :gen_tcp.connect(host, port, socket_opts, timeout) do
      {:ok, socket} ->
        register_session(%{s | socket: socket})

      {:error, _} ->
        {:backoff, 1000, s}
    end
  end

  @impl true
  def disconnect(info, %{socket: socket} = s) do
    :ok = :gen_tcp.close(socket)

    case info do
      {:close, from} ->
        Connection.reply(from, :ok)
        {:stop, :normal, %{s | socket: nil}}

      {:error, :closed} ->
        Logger.error("Connection closed")
        {:connect, :reconnect, %{s | socket: nil}}

      {:error, reason} ->
        reason = :inet.format_error(reason)
        Logger.error("Connection error: #{inspect(reason)}")
        {:connect, :reconnect, %{s | socket: nil}}
    end
  end

  @impl true
  def handle_call(_, _, %{socket: nil} = s) do
    {:reply, {:error, :closed}, s}
  end

  @impl true
  def handle_call({:send_rr_data, data}, _from, %{socket: socket} = s) do
    reply = sync_send(socket, Protocol.send_rr_data(s.session_handle, data), s.timeout)
    {:reply, reply, s}
  end

  @impl true
  def handle_call({:send_unit_data, conn, data}, _from, %{socket: socket} = s) do
    sequence_number = s.sequence_number + 1

    reply =
      sync_send(
        socket,
        Protocol.send_unit_data(s.session_handle, conn, sequence_number, data),
        s.timeout
      )

    {:reply, reply, %{s | sequence_number: sequence_number}}
  end

  @impl true
  def handle_call(:close, from, s) do
    unregister_session(s)
    {:disconnect, {:close, from}, s}
  end

  defp register_session(%{socket: socket, timeout: timeout} = s) do
    case sync_send(socket, Protocol.register(), timeout) do
      {:ok, session_handle} ->
        {:ok, %{s | session_handle: session_handle}}

      _error ->
        :gen_tcp.close(socket)
        {:backoff, 1000, %{s | socket: nil}}
    end
  end

  defp unregister_session(%{socket: socket, session_handle: session}) do
    :gen_tcp.send(socket, Protocol.unregister(session))
  end

  defp sync_send(socket, data, timeout) do
    with :ok <- :gen_tcp.send(socket, data) do
      recv(socket, <<>>, timeout)
    end
  end

  defp recv(socket, buffer, timeout) do
    with {:ok, resp} <- :gen_tcp.recv(socket, 0, timeout) do
      resp = buffer <> resp
      case Protocol.decode(resp) do
        :partial -> recv(socket, resp, timeout)
        resp -> resp
      end
    end
  end
end
