defmodule Scrub do
  def vendor, do: "ex"
  def serial_number, do: "pTLC"

  alias Scrub.CIP.ConnectionManager
  alias Scrub.Session

  def open_session(host) do
    Scrub.Session.start_link(host)
  end

  # def open_conn(host) when is_binary(host), do: open_session!(host) |> open_conn()
  def open_conn(session) do
    payload = ConnectionManager.encode_service(:large_forward_open)

    with {:ok, resp} <- Session.send_rr_data(session, payload),
         {:ok, conn} <- ConnectionManager.decode(resp) do
      {session, conn}
    end
  end

  def check_conn_status(session) do
    Session.status(session)
  end

  def close_conn({session, conn}) do
    payload = ConnectionManager.encode_service(:forward_close, conn: conn)

    with {:ok, resp} <- Session.send_rr_data(session, payload) do
      ConnectionManager.decode(resp)
    end
  end

  def close_session(session) do
    Scrub.Session.close(session)
  end

  def read_metadata(session) do
    case Session.get_tags_metadata(session) do
      {:ok, metadata} ->
        {:ok, metadata}

      error ->
        error
    end
  end

  @spec bulk_read_tags(pid(), [binary() | [binary() | non_neg_integer()]]) ::
          {:ok, [any | {:error, binary}]} | {:error, any}
  def bulk_read_tags(session, [_path | _rest] = tag_list) do
    with {session, conn} <- open_conn(session),
         data <- ConnectionManager.encode_service(:multiple_service_request, tag_list: tag_list),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do
      close_conn({session, conn})
      ConnectionManager.decode(resp)
    end
  end

  # Read a complex member. The list is an ordered mix of options.
  # example:  "Struct.Member[13]"  ->  ["Struct", "Member", 13]
  # integers: considered to be array elements
  # strings: considered to be structure members.
  # This is outlined in the request path examples for Logix 5000 Controllers Data Access page 65
  @spec read_tag(pid(), [binary() | non_neg_integer()]) ::
          {:ok, any} | {:error, any}
  def read_tag(session, [tag | _rest] = nested_member) when is_binary(tag) do
    # ensure tag metadata is valid
    case Session.get_tag_metadata(session, tag) do
      {:ok, _} ->
        with {session, conn} <- open_conn(session),
             data <-
               ConnectionManager.encode_service(:read_tag_service, request_path: nested_member),
             {:ok, resp} <- Session.send_unit_data(session, conn, data) do
          close_conn({session, conn})
          ConnectionManager.decode(resp)
        end

      {:error, _} = error ->
        error
    end
  end

  def read_tag(session, tag) when is_binary(tag) do
    case Session.get_tag_metadata(session, tag) do
      {:ok, tag} ->
        read_tag(session, tag)

      error ->
        error
    end
  end

  def read_tag(session, %{structure: :structured, template: template} = tag) do
    with {session, conn} <- open_conn(session),
         data <- ConnectionManager.encode_service(:read_tag_service, request_path: tag.name),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do
      close_conn({session, conn})
      ConnectionManager.decode(resp, template)
    end
  end

  def read_tag(session, %{array_dims: dims, array_length: [h | t]} = tag) when dims > 0 do
    elements = Enum.reduce(t, h, &(&1 * &2))

    with {session, conn} <- open_conn(session),
         data <-
           ConnectionManager.encode_service(:read_tag_service,
             request_path: tag.name,
             read_elements: elements
           ),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do
      close_conn({session, conn})
      ConnectionManager.decode(resp, tag)
    end
  end

  def read_tag(session, %{} = tag) do
    with {session, conn} <- open_conn(session),
         data <- ConnectionManager.encode_service(:read_tag_service, request_path: tag.name),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do
      close_conn({session, conn})
      ConnectionManager.decode(resp)
    end
  end

  def read_template_instance(session, template_instance) do
    with {s, conn} <- Scrub.open_conn(session),
         data <-
           Scrub.CIP.Template.encode_service(:get_attribute_list, instance_id: template_instance),
         {:ok, resp} <- Scrub.Session.send_unit_data(s, conn, data),
         {:ok, template_attributes} <- Scrub.CIP.Template.decode(resp) do
      template = read_template_chunks(s, conn, template_instance, template_attributes)
      Scrub.close_conn({s, conn})
      template
    else
      error ->
        {:error, error}
    end
  end

  def read_template_attr(session, template_instance) do
    with {s, conn} <- Scrub.open_conn(session),
         data <-
           Scrub.CIP.Template.encode_service(:get_attribute_list, instance_id: template_instance),
         {:ok, resp} <- Scrub.Session.send_unit_data(s, conn, data),
         {:ok, template_attributes} <- Scrub.CIP.Template.decode(resp) do
      Scrub.close_conn({s, conn})
      template_attributes
    else
      error ->
        {:error, error}
    end
  end

  defp read_template_chunks(s, conn, template_instance, template_attributes, acc \\ <<>>) do
    offset = byte_size(acc)
    bytes = template_attributes.definition_size * 4 - 23 - offset

    with data <-
           Scrub.CIP.Template.encode_service(:read_template_service,
             instance_id: template_instance,
             bytes: bytes,
             offset: offset
           ),
         {:ok, resp} <- Scrub.Session.send_unit_data(s, conn, data),
         {:ok, template} <- Scrub.CIP.Template.decode(resp, template_attributes, acc) do
      template
    else
      {:partial_data, data} ->
        read_template_chunks(s, conn, template_instance, template_attributes, data)

      {:error, _} = err ->
        err
    end
  end

  def inspect(binary) do
    IO.inspect(binary, limit: :infinity, base: :hex)
  end
end
