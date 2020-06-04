defmodule Scrub.Session do
  use DBConnection
  # import Scrub.Utils

  require Logger
  alias Scrub.Session.Protocol
  alias Scrub.CIP.{ConnectionManager, Template, Symbol}

  defmodule Query do
    defstruct [:query]
  end

  @default_port 44818
  @default_pool_size 1
  @default_idle_interval 50_000

  defmodule Error do
    defexception [:function, :reason, :message]

    def exception({function, reason}) do
      message = "#{function} error: #{format_error(reason)}"
      %Error{function: function, reason: reason, message: message}
    end

    defp format_error(:closed), do: "closed"
    defp format_error(:timeout), do: "timeout"
    defp format_error(reason), do: :inet.format_error(reason)
  end

  def start_link(
        host,
        port \\ @default_port,
        socket_opts \\ [],
        timeout \\ 15000,
        pool_size \\ @default_pool_size,
        idle_interval \\ @default_idle_interval
      )

  def start_link(host, port, opts, timeout, pool_size, idle_interval) do
    opts =
      [
        hostname: host,
        port: port,
        timeout: timeout,
        pool_size: pool_size,
        idle_interval: idle_interval
      ] ++ opts

    DBConnection.start_link(__MODULE__, opts)
  end

  def get_tags_metadata(session) do
    case DBConnection.execute(session, %Query{query: :get_all_tags_metadata}, <<>>) do
      {:ok, _query, {:error, err}} ->
        {:error, err}

      {:ok, _query, result} ->
        {:ok, result}

      {:error, _} = err ->
        err
    end
  end

  def get_tag_metadata(session, tag) do
    case DBConnection.execute(session, %Query{query: :get_tag_metadata}, tag) do
      {:ok, _query, {:error, err}} ->
        {:error, err}

      {:ok, _query, result} ->
        {:ok, result}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  2-4.7 SendRRData

  Used for sending unconnected messages.
  """
  def send_rr_data(session, data) do
    case DBConnection.execute(session, %Query{query: :send_rr_data}, data) do
      {:ok, _query, result} ->
        {:ok, result}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  2-4.8 SendUnitData

  Used for sending connected messages.
  Requires passing the O->T Network Connection ID
  This Network Connection ID is obtained by using send_rr_data to
  establish a connection to the target's connection manager object.
  """

  def send_unit_data(session, conn, data) do
    case DBConnection.execute(session, %Query{query: :send_unit_data}, {conn, data}) do
      {:ok, _query, result} ->
        {:ok, result}

      {:error, _} = err ->
        err
    end
  end

  def close(session) do
    case DBConnection.close(session, %Query{query: :close}) do
      {:ok, result} ->
        {:ok, result}

      {:error, _} = err ->
        err
    end
  end

  def status(session) do
    DBConnection.status(session)
  end

  # DBConnection behaviour

  @impl true
  def connect(opts) do
    host = Keyword.fetch!(opts, :hostname) |> String.to_charlist()
    port = Keyword.fetch!(opts, :port)
    timeout = Keyword.get(opts, :connect_timeout, 5_000)

    enforced_opts = [packet: :raw, mode: :binary, active: false, keepalive: true]
    socket_opts = Keyword.get(opts, :socket_options, [])
    socket_opts = Enum.reverse(socket_opts, enforced_opts)

    case :gen_tcp.connect(host, port, socket_opts, timeout) do
      {:ok, sock} ->
        state = %{
          socket: sock,
          host: host,
          port: port,
          socket_opts: socket_opts,
          timeout: timeout,
          session_handle: nil,
          tag_metadata: [],
          sequence_number: 1,
          buffer: <<>>
        }

        handshake(state)

      {:error, reason} ->
        {:error, Scrub.Session.Error.exception({:connect, reason})}
    end
  end

  defp handshake(state) do
    with {:ok, state} <- register_session(state),
         {:ok, state} <- fetch_metadata(state),
         {:ok, state} <- fetch_structure_templates(state) do
      Logger.debug("Handshake complete")
      {:ok, state}
    end
  end

  @impl true
  def handle_begin(_opts, state) do
    {:ok, :ok, state}
  end

  @impl true
  def disconnect(_err, %{socket: socket} = state) do
    # IO.inspect disconnect: "err: #{err}, state: #{state}"
    :ok = :gen_tcp.close(socket)
    _ = flush(<<>>, state)
    :ok
  end

  @impl true
  def checkin(state) do
    {:ok, state}
  end

  @impl true
  def checkout(state) do
    {:ok, state}
  end

  @impl true
  def ping(state) do
    with {:ok, state} <- handshake(state) do
      {:ok, state}
    else
      _error ->
        {:disconnect, Scrub.Session.Error.exception({:ping, :timeout}), state}
    end
  end

  @impl true
  def handle_prepare(query, _opts, state) do
    {:ok, query, state}
  end

  @impl true
  def handle_execute(
        %Query{query: :send_rr_data} = query,
        data,
        _,
        %{socket: socket, timeout: timeout} = state
      ) do
    case sync_send(socket, Protocol.send_rr_data(state.session_handle, data), timeout) do
      {:ok, data} ->
        {:ok, query, data, state}

      {:error, reason} ->
        {:disconnect, Scrub.Session.Error.exception({:send_rr_data, reason}), state}
    end
  end

  @impl true
  def handle_execute(
        %Query{query: :send_unit_data} = query,
        {conn, data},
        _,
        %{socket: socket, timeout: timeout, session_handle: session_handle} = state
      ) do
    sequence_number = state.sequence_number + 1

    case sync_send(
           socket,
           Protocol.send_unit_data(session_handle, conn, state.sequence_number, data),
           timeout
         ) do
      {:ok, data} ->
        state = %{state | sequence_number: sequence_number}
        {:ok, query, data, state}

      {:error, reason} ->
        {:disconnect, Scrub.Session.Error.exception({:send_unit_data, reason}), state}
    end
  end

  @impl true
  def handle_execute(
        %Query{query: :get_all_tags_metadata} = query,
        _data,
        _opts,
        %{tag_metadata: reply} = state
      ) do
    {:ok, query, reply, state}
  end

  @impl true
  def handle_execute(
        %Query{query: :get_tag_metadata} = query,
        tag,
        _,
        %{tag_metadata: tags} = state
      ) do
    reply =
      case Enum.find(tags, &(&1.name == tag)) do
        nil ->
          {:error, :no_tag_found}

        metadata ->
          metadata
      end

    {:ok, query, reply, state}
  end

  @impl true
  def handle_commit(_opts, state) do
    # currently unused but required by DBConnection
    {:ok, :ok, state}
  end

  @impl true
  def handle_deallocate(_query, _cursor, _opts, state) do
    {:ok, :ok, state}
  end

  @impl true
  def handle_declare(query, _params, _opts, state) do
    {:ok, query, :ok, state}
  end

  @impl true
  def handle_fetch(_query, _cursor, _opts, state) do
    {:cont, :ok, state}
  end

  @impl true
  def handle_rollback(_opts, state) do
    {:ok, :ok, state}
  end

  @impl true
  def handle_status(_opts, state) do
    {:idle, state}
  end

  @impl true
  def handle_close(%Query{query: :close} = _query, _opts, state) do
    _resp = unregister_session(state)
    {:ok, nil, state}
  end

  defp register_session(%{socket: socket, timeout: timeout} = s) do
    with {:ok, session_handle} <- sync_send(socket, Protocol.register(), timeout) do
      {:ok, %{s | session_handle: session_handle}}
    else
      error ->
        Logger.error("Error: #{inspect(error)}")
        :gen_tcp.close(socket)
        {:backoff, 1000, %{s | socket: nil}}
    end
  end

  defp unregister_session(%{socket: socket, session_handle: session, timeout: timeout}) do
    sync_send(socket, Protocol.unregister(session), timeout)
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
        Logger.error("Error: #{inspect(error)}")
        :gen_tcp.close(socket)
        {:backoff, 1000, %{s | socket: nil}}
    end
  end

  defp fetch_metadata(s) do
    Logger.debug("fetch metadata not empty")
    {:ok, s}
  end

  # matches that tag_metadata has a head and a tail
  defp fetch_structure_templates(%{tag_metadata: tags} = s) do
    case Enum.any?(tags, fn item -> Map.has_key?(item, :template) end) do
      false ->
        do_fetch_structure_templates(s)

      _ ->
        {:ok, s}
    end
  end

  defp do_fetch_structure_templates(%{tag_metadata: [_ | _] = tags, socket: socket} = s) do
    tags = Symbol.filter(tags)
    {structures, tags} = Enum.split_with(tags, &(&1.structure == :structured))

    with data <- ConnectionManager.encode_service(:large_forward_open),
         _ <- do_send_rr_data(s, data),
         {:ok, resp} <- read_recv(socket, <<>>, s.timeout),
         {:ok, conn} <- ConnectionManager.decode(resp) do
      {structures, s} =
        Enum.reduce(structures, {structures, s}, fn %{template_instance: template_instance} =
                                                      structure,
                                                    {structures, s} ->
          data = Template.encode_service(:get_attribute_list, instance_id: template_instance)
          s = do_send_unit_data(s, conn, data)

          with {:ok, resp} <- read_recv(s.socket, <<>>, s.timeout),
               {:ok, template_attributes} <- Template.decode(resp),
               data <-
                 Template.encode_service(:read_template_service,
                   instance_id: template_instance,
                   bytes: template_attributes.definition_size * 4 - 23
                 ),
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
        Logger.error("Error: #{inspect(error)}")
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
    sequence_number = s.sequence_number + 1

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
        [%{instance_id: id} | _] = Enum.sort(new_tags, &(&1.instance_id > &2.instance_id))
        # IO.inspect id

        data = Symbol.encode_service(:get_instance_attribute_list, instance_id: id + 1)
        s = do_send_unit_data(s, conn, data)
        {:ok, resp} = read_recv(s.socket, <<>>, s.timeout)

        decode_tag_list(s, conn, resp, new_tags ++ tags)

      {:ok, %{status: :success, tags: new_tags}} ->
        {:ok, Enum.sort(new_tags ++ tags, &(&1.instance_id > &2.instance_id))}

      error ->
        error
    end
  end

  defp flush(buffer, %{socket: socket} = state) do
    receive do
      {:tcp, ^socket, data} ->
        {:ok, {socket, buffer <> data}}

      {:tcp_closed, ^socket} ->
        {:disconnect, Scrub.Session.Error.exception({:recv, :closed}), state}

      {:tcp_error, ^socket, reason} ->
        {:disconnect, Scrub.Session.Error.exception({:recv, reason}), state}
    after
      0 ->
        # There might not be any socket messages.
        {:ok, state}
    end
  end

  defimpl DBConnection.Query, for: Scrub.Session.Query do
    alias Scrub.Session.Query

    def parse(%Query{query: tag} = query, _) when tag in [:send, :recv] do
      Logger.debug("parse: #{inspect(query)}, tag #{inspect(tag)}")
      query
    end

    def describe(query, _), do: query

    def encode(%Query{query: :send}, data, s) when is_binary(data) do
      IO.inspect(encode: "data:#{data}, state:#{s}")
      data
    end

    def encode(%Query{query: tag}, data, _s)
        when tag in [
               :send_rr_data,
               :close,
               :get_tag_metadata,
               :get_all_tags_metadata,
               :send_unit_data
             ] do
      data
    end

    def encode(%Query{query: :recv}, [_bytes, _timeout] = args, _) do
      args
    end

    def decode(_, result, _state) do
      result
    end
  end
end
