defmodule Scrub.Session do
  use Connection
  import Scrub.Utils

  require Logger

  alias Scrub.Session.Protocol
  alias Scrub.CIP.{ConnectionManager, Template, Symbol}

  @default_port 44818

  def start_link(host, port \\ @default_port, socket_opts \\ [], timeout \\ 15000)

  def start_link(host, port, socket_opts, timeout) when is_binary(host) do
    start_link(ip_to_tuple!(host), port, socket_opts, timeout)
  end

  def start_link(host, port, socket_opts, timeout) do
    Connection.start_link(__MODULE__, {host, port, socket_opts, timeout})
  end

  def get_tag_metadata(session, tag) do
    GenServer.call(session, {:get_tag_metadata, tag})
  end

  def get_tag_metadata(session) do
    GenServer.call(session, :get_tag_metadata)
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
      sequence_number: 1,
      buffer: <<>>,
      from: nil,
      tag_metadata: []
    }

    {:connect, :init, s}
  end

  @impl true
  def connect(
        _,
        %{socket: nil, host: host, port: port, socket_opts: socket_opts, timeout: timeout} = s
      ) do
    with {:ok, socket} <- :gen_tcp.connect(host, port, socket_opts, timeout),
         s <- Map.put(s, :socket, socket),
         {:ok, s} <- register_session(s),
         {:ok, s} <- fetch_metadata(s),
         {:ok, s} <- fetch_structure_templates(s) do

      :inet.setopts(socket, [{:active, true}])
      {:ok, s}
    else
      {:error, _} ->
        {:backoff, 1000, s}

      {:backoff, _, _} = backoff ->
        backoff
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
  def handle_call({:get_tag_metadata, tag}, _from, %{tag_metadata: tags} = s) do
    reply =
      case Enum.find(tags, & &1.name == tag) do
        nil ->
          {:error, :no_tag_found}

        metadata ->
          {:ok, metadata}
      end
    {:reply, reply, s}
  end

  @impl true
  def handle_call(:get_tag_metadata, _from, %{tag_metadata: tags} = s) do
    {:reply, {:ok, tags}, s}
  end

  @impl true
  def handle_call({:send_rr_data, data}, from, s) do
    do_send_rr_data(s, data)
    {:noreply, %{s | from: from}}
  end

  @impl true
  def handle_call({:send_unit_data, conn, data}, from, s) do
    s = do_send_unit_data(s, conn, data)
    {:noreply, %{s | from: from}}
  end

  @impl true
  def handle_call(:close, from, s) do
    unregister_session(s)
    {:disconnect, {:close, from}, s}
  end

  @impl true
  def handle_info({:tcp, _port, data}, %{buffer: buffer} = s) do
    data = buffer <> data
    s =
      case Protocol.decode(data) do
        :partial ->
          %{s | buffer: data}
        resp ->
          GenServer.reply(s.from, resp)
          %{s | from: nil, buffer: <<>>}
      end
    {:noreply, s}
  end

  def handle_info({:tcp_closed, _from}, s) do
    {:disconnect, {:error, :closed}, s}
  end

  defp register_session(%{socket: socket, timeout: timeout} = s) do
    with {:ok, session_handle} <- sync_send(socket, Protocol.register(), timeout) do

        {:ok, %{s | session_handle: session_handle}}
    else
      error ->
        IO.puts "Error: #{inspect error}"
        :gen_tcp.close(socket)
        {:backoff, 1000, %{s | socket: nil}}
    end
  end

  defp unregister_session(%{socket: socket, session_handle: session}) do
    :gen_tcp.send(socket, Protocol.unregister(session))
  end

  defp fetch_metadata(%{tag_metadata: [], socket: socket} = s) do
    with data <- ConnectionManager.encode_service(:large_forward_open),
         _ <- do_send_rr_data(s, data),
         {:ok, resp} <- read_recv(socket, <<>>, s.timeout),
         {:ok, conn} <- ConnectionManager.decode(resp),
         data <- Symbol.encode_service(:get_instance_attribute_list),
         s <- do_send_unit_data(s, conn, data),
         {:ok, resp} <- read_recv(socket, <<>>, s.timeout),
         {:ok, tags} <- decode_tag_list(s, conn, resp),
         :ok <- close_conn(s, conn) do

        {:ok, %{s | tag_metadata: tags}}
    else
      error ->
        IO.puts "Error: #{inspect error}"
        :gen_tcp.close(socket)
        {:backoff, 1000, %{s | socket: nil}}
    end
  end

  defp fetch_metadata(s) do
    IO.puts("fetch metadata not empty")
    {:ok, s}
  end
  #matches that tag_metadata has a head and a tail
  defp fetch_structure_templates(%{tag_metadata: tags} = s) do

    IO.puts "checking for template"
    IO.inspect length(tags)
    case Enum.any?(tags, fn(item) -> Map.has_key?(item, :template) end) do
      false ->
        do_fetch_structure_templates(s)
      _ ->
        {:ok, s}
    end

  end
  defp do_fetch_structure_templates(%{tag_metadata: [_ | _] = tags, socket: socket} = s) do
    tags = Symbol.filter(tags)
    {structures, tags} = Enum.split_with(tags, & &1.structure == :structured)

    with data <- ConnectionManager.encode_service(:large_forward_open),
         _ <- do_send_rr_data(s, data),
         {:ok, resp} <- read_recv(socket, <<>>, s.timeout),
         {:ok, conn} <- ConnectionManager.decode(resp) do

        {structures, s} =
          Enum.reduce(structures, {structures, s}, fn(%{template_instance: template_instance} = structure, {structures, s}) ->
            data = Template.encode_service(:get_attribute_list, instance_id: template_instance)
            s = do_send_unit_data(s, conn, data)

            with {:ok, resp} <- read_recv(s.socket, <<>>, s.timeout),
                {:ok, template_attributes} <- Template.decode(resp),
                data <- Template.encode_service(:read_template_service, instance_id: template_instance, bytes: ((template_attributes.definition_size * 4) - 23)),
                s <- do_send_unit_data(s, conn, data),
                {:ok, resp} <- read_recv(socket, <<>>, s.timeout),
                {:ok, template} <- Template.decode(resp) do
                template = Map.merge(template_attributes, template)
                {[Map.put(structure, :template, template) | structures], s}
            else
              _ ->
                {structures, s}
            end
          end)

        close_conn(s, conn)
        {:ok, %{s | tag_metadata: tags ++ structures}}
    else
      error ->
        IO.puts "Error: #{inspect error}"
        :gen_tcp.close(socket)
        {:backoff, 1000, %{s | socket: nil}}
    end
  end


  defp close_conn(s, conn) do
    with data = ConnectionManager.encode_service(:forward_close, conn: conn),
         _ <- do_send_rr_data(s, data),
         {:ok, _resp} <- read_recv(s.socket, <<>>, s.timeout) do
      :ok
    else
      _e -> :error
    end
  end

  defp do_send_rr_data(s, data) do
    async_send(s.socket, Protocol.send_rr_data(s.session_handle, data))
  end

  defp do_send_unit_data(s, conn, data) do
    sequence_number = (s.sequence_number + 1)
    async_send(
      s.socket,
      Protocol.send_unit_data(s.session_handle, conn, s.sequence_number, data)
    )
    %{s | sequence_number: sequence_number}
  end

  defp sync_send(socket, data, timeout) do
    with :ok <- :gen_tcp.send(socket, data) do
      read_recv(socket, <<>>, timeout)
    end
  end

  defp async_send(socket, data) do
    :gen_tcp.send(socket, data)
  end

  defp read_recv(socket, buffer, timeout) do
    with {:ok, resp} <- :gen_tcp.recv(socket, 0, timeout) do
      resp = buffer <> resp
      case Protocol.decode(resp) do
        :partial -> read_recv(socket, resp, timeout)
        resp -> resp
      end
    end
  end

  defp decode_tag_list(s, conn, binary_resp, tags \\ []) do
    case Symbol.decode(binary_resp) do
      {:ok, %{status: :too_much_data, tags: new_tags}} ->
        [%{instance_id: id} | _] = Enum.sort(new_tags, & &1.instance_id > &2.instance_id)
        IO.inspect id

        data = Symbol.encode_service(:get_instance_attribute_list, instance_id: (id + 1))
        s = do_send_unit_data(s, conn, data)
        {:ok, resp} = read_recv(s.socket, <<>>, s.timeout)

        decode_tag_list(s, conn, resp, new_tags ++ tags)

      {:ok, %{status: :success, tags: new_tags}} ->
        {:ok, Enum.sort(new_tags ++ tags, & &1.instance_id > &2.instance_id)}

      error ->
        error
    end
  end
end
