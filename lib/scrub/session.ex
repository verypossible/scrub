


# defmodule Scrub.Query do
#   defstruct [:statement, :statement_id]
#   defimpl DBConnection.Query do
#     def parse(query, _opts) do
#       query
#     end

#     def describe(query, _opts) do
#       query


#     end
#     def encode(_query, params, _opts) do
#       params
#     end

#     def decode(_query, result, _opts) do
#       result
#     end

#   end


# end


defmodule Scrub.Session do
  use DBConnection
  # import Scrub.Utils

  require Logger
  require IEx
  alias Scrub.Session.Protocol
  alias Scrub.CIP.{ConnectionManager, Template, Symbol}

  defmodule Query do
    defstruct [:query]
  end
  @default_port 44818
  @default_pool_size 1

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



  def start_link(host, port \\ @default_port, socket_opts \\ [], timeout \\ 15000, pool_size \\ @default_pool_size)

  # def start_link(host, port, socket_opts, timeout) when is_binary(host) do
  #   IO.inspect(startlink: "test")
  #   start_link(host, port, socket_opts, timeout)
  # end

  def start_link(host, port, opts, timeout, pool_size) do

    opts = [hostname: host, port: port, timeout: timeout, pool_size: pool_size] ++ opts
    IO.inspect(startlink: opts)
    DBConnection.start_link(__MODULE__, opts)
  end

  def get_tag_metadata(session, tag) do
    case DBConnection.execute(session, %Query{query: :get_tag_metadata}, tag) do
      {:ok, _query, result} ->

        {:ok,result}
      {:error, _} = err -> err
    end

  end
  def old_get_tag_metadata(session, tag) do
    GenServer.call(session, {:get_tag_metadata, tag})
  end

  def old_get_tag_metadata(session) do
    GenServer.call(session, :get_tag_metadata)
  end

  @doc """
  2-4.7 SendRRData

  Used for sending unconnected messages.
  """
  def old_send_rr_data(session, data) do
    Connection.call(session, {:send_rr_data, data})
  end

  def send_rr_data(session, data) do

    case DBConnection.execute(session, %Query{query: :send_rr_data}, data) do
      {:ok, _query, result} ->
        {:ok,result}
      {:error, _} = err -> err
    end

  end


  def mrag_send(conn, data) do

    case DBConnection.execute(conn, %Query{query: :send_rr_data}, data) do
      {:ok, query, state} ->
        {:ok,state}
      {:error, _} = err -> err
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
      {:error, _} = err -> err
    end
  end
  def old_send_unit_data(session, conn, data) do
    Connection.call(session, {:send_unit_data, conn, data})
  end


  def old_close(session), do: Connection.call(session, :close)

  def close(session) do
    case DBConnection.close(session, %Query{query: :close}) do
      {:ok, result} ->
        {:ok,result}
      {:error, _} = err -> err
    end

  end
  # Connection behaviour

  @spec init({any, any, any, any}) ::
          {:connect, :init,
           %{
             buffer: <<>>,
             from: nil,
             host: any,
             port: any,
             sequence_number: 1,
             session_handle: nil,
             socket: nil,
             socket_opts: [any],
             tag_metadata: [],
             timeout: any
           }}
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

  # DBConnection behaviour

  @impl true
  def connect(opts) do
    host = Keyword.fetch!(opts, :hostname) |> String.to_charlist()
    port = Keyword.fetch!(opts, :port)
    timeout = Keyword.get(opts, :connect_timeout, 5_000)

    enforced_opts = [packet: :raw, mode: :binary, active: false, keepalive: true]
    socket_opts = Keyword.get(opts, :socket_options, [])
    socket_opts = Enum.reverse(socket_opts, enforced_opts)
    IO.inspect enforced_opts
    IO.inspect socket_opts
    IO.inspect host: host
    IO.inspect port: port
    case :gen_tcp.connect(host, port, socket_opts, timeout) do
      {:ok, sock} ->
        IO.inspect sock: sock
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
        # {:ok, state}

      {:error, reason} ->
        {:error, Scrub.Session.Error.exception({:connect, reason})}
    end

  end

  def connect_old(
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

  defp handshake(state) do
    with {:ok, state} <- register_session(state),
         {:ok, state} <- fetch_metadata(state),
         {:ok, state} <- fetch_structure_templates(state) do
      :inet.setopts(state.socket, [{:active, false}])
      {:ok, state}
    end
  end

  @impl true
  def handle_begin(opts, state) do
    IO.inspect handle_begin: opts
    IEx.pry
    {:ok, :ok, state}
  end

  @impl true
  def disconnect(err, state) do
    IO.inspect disconnect: "err: #{err}, state: #{state}"
    IEx.pry
    :ok
  end

  @impl true
  def checkin(state) do
    IEx.pry
    {:ok, state}
  end

  @impl true
  def checkout(state) do
    IO.inspect checkout: ""
    {:ok, state}
  end

  @impl true
  def ping(state) do

    {:ok, state}
  end
  @impl true
  def handle_prepare(%Query{query: query}, _opts, _state) do
    IO.inspect handle_prepare: query

  end

  @impl true
  def handle_execute(%Query{query: :send} = query, data, otherdata,  state) do
    IO.inspect handle_execute: query
    IO.inspect data: data
    IO.inspect otherdata: otherdata
    # IO.inspect state: state
    data = "Melvin"
    %Query{query: :send}
    {:ok, query, data, state}
    # case :gen_tcp.send(sock, data) do
    #   :ok ->
    #     # A result is always required for handle_query/3
    #     {:ok, query, :ok, state}

    #   {:error, reason} ->
    #     {:disconnect, Scrub.Session.Error.exception({:send, reason}), state}
    # end
  end

  @impl true
  def handle_execute(%Query{query: :send_rr_data} = query, data, _, %{socket: socket, timeout: timeout} = state) do

    case sync_send(socket, Protocol.send_rr_data(state.session_handle, data), timeout ) do
    {:ok, data} ->
      {:ok, query, data, state}
    {:error, reason} ->
      {:disconnect, Scrub.Session.Error.exception({:send_rr_data, reason}), state}
    end
  end

  @impl true
  def handle_execute(%Query{query: :send_unit_data} = query, {conn, data} , _, %{socket: socket, timeout: timeout, session_handle: session_handle} = state) do

    sequence_number = (state.sequence_number + 1)
    case sync_send(socket, Protocol.send_unit_data(session_handle, conn, state.sequence_number, data), timeout) do
      {:ok, data} ->

        %{state | sequence_number: sequence_number}
        {:ok, query, data, state}
      {:error, reason} ->
        {:disconnect, Scrub.Session.Error.exception({:send_unit_data, reason}), state}
      end


  end

  @impl true
  def handle_execute(%Query{query: :get_tag_metadata} = query, tag, _, %{tag_metadata: tags} = state) do
    reply =
      case Enum.find(tags, & &1.name == tag) do
        nil ->
          {:error, :no_tag_found}

        metadata ->
          metadata
      end
    {:ok, query, reply, state}

  end


  @impl true
  def handle_close(%Query{query: :close} = _query, _opts, state ) do
    resp = unregister_session(state)
    IO.inspect resp: resp
    {:ok, nil, state}
  end


  def old_disconnect(info, %{socket: socket} = s) do
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






  # @impl true
  # def handle_call({:send_rr_data, data}, from, s) do
  #   do_send_rr_data(s, data)
  #   {:noreply, %{s | from: from}}
  # end


  @impl true
  def handle_call(_, _, %{socket: nil} = s) do
    {:reply, {:error, :closed}, s}
  end



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

  defp unregister_session(%{socket: socket, session_handle: session, timeout: timeout}) do
    sync_send(socket, Protocol.unregister(session), timeout)
  end

  defp old_unregister_session(%{socket: socket, session_handle: session}) do
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
    IO.inspect sync_send: socket
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
        # IO.inspect id

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


defimpl DBConnection.Query, for: Scrub.Session.Query do
  alias Scrub.Session.Query

  def parse(%Query{query: tag} = query, _) when tag in [:send, :recv] do
    IO.puts parse: "#{query}, tag #{tag}"
    query
  end

  def describe(query, _), do: query

  def encode(%Query{query: :send}, data, s) when is_binary(data) do
    IO.inspect encode: "data:#{data}, state:#{s}"
    data
  end

  def encode(%Query{query: tag}, data, s)  when tag in [:send_rr_data, :close,:get_tag_metadata, :send_unit_data] do
    IO.inspect encode: "data:#{data}"
    data
  end


  def encode(%Query{query: :recv}, [_bytes, _timeout] = args, _) do

    args
  end



  def decode(_, result, state) do
    # IO.inspect decode: "#{result}, #{state}"
    result
  end
end


end
