defmodule Scrub do
  import Scrub.BinaryUtils, warn: false
  def vendor, do: "ex"
  def serial_number, do: "pTLC"

  alias Scrub.CIP.ConnectionManager
  alias Scrub.Session
  alias Scrub.CIP.Symbol
  require IEx
  require Logger

  def open_session(host) do
    Scrub.Session.start_link(host)
  end

  def open_conn(host) when is_binary(host), do: open_session(host) |> open_conn()
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
      {:ok, metadata}  ->

        {:ok, filter_template_data(metadata)}
      error ->
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
         data <- ConnectionManager.encode_service(:unconnected_send, request_path: tag.name),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do
      close_conn({session, conn})
      ConnectionManager.decode(resp, template)
    end
  end

  def read_tag(session, %{array_dims: dims, array_length: [h | t]} = tag) when dims > 0 do
    elements = Enum.reduce(t, h, &(&1 * &2))

    with {session, conn} <- open_conn(session),
         data <-
           ConnectionManager.encode_service(:unconnected_send,
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
         data <- ConnectionManager.encode_service(:unconnected_send, request_path: tag.name),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do
      close_conn({session, conn})
      ConnectionManager.decode(resp)
    end
  end

  def filter_template_data(tags) do
    tags
    |> Enum.reject(fn (item) ->
        is_structure_type(item)
        end )
  end

  def is_structure_type(%{structure: :atomic}) do
    false
  end

  def is_structure_type(_x) do
    true
  end
  # def read_tag(host, tag) when is_binary(host) do
  #   open_conn(host)
  #   |> read_tag(tag)
  # end

  def list_tags({session, conn}) do

    with data <- Symbol.encode_service(:get_instance_attribute_list),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do

      {:ok, tags} = decode_tag_list(session, conn, resp)
      Enum.each(Scrub.CIP.Symbol.filter(tags), fn item ->
        if Map.has_key?(item, :type) do
           "name: #{IO.inspect(item.name)} type: #{IO.inspect(item.type)}"
        else
          "------------------"
        end
      end)

      {:ok,tags}
    end
  end

  def list_tags(host) when is_binary(host) do
    open_conn(host)
    |> list_tags()
  end

  # def find_tag({session, conn}, tag) when is_binary(tag) do
  #   with {:ok, tags} <- list_tags({session, conn}),
  #     %{} = tag <- Enum.find(tags, & &1.name == tag) do

  #       {:ok, tag}
  #   else
  #     nil -> {:error, :not_found}
  #   end
  # end

  # def find_tag(host, tag) when is_binary(host) do
  #   open_conn(host)
  #   |> find_tag(tag)
  # end

  defp decode_tag_list(session, conn, binary_resp, tags \\ []) do
    case Symbol.decode(binary_resp) do
      {:ok, %{status: :too_much_data, tags: new_tags}} ->
        [%{instance_id: id} | _] = Enum.sort(new_tags, & &1.instance_id > &2.instance_id)

        data = Symbol.encode_service(:get_instance_attribute_list, instance_id: (id + 1))
        {:ok, resp} = Session.send_unit_data(session, conn, data)

        decode_tag_list(session, conn, resp, new_tags ++ tags)

      {:ok, %{status: :success, tags: new_tags}} ->
        {:ok, Enum.sort(new_tags ++ tags, & &1.instance_id > &2.instance_id)}

      error ->
        error
    end
  end

  # def read_template_attributes({session, conn}, <<template_instance :: binary(2, 8)>>) do
  #   with data <- Template.encode_service(:get_attribute_list, instance_id: template_instance),
  #        {:ok, resp} <- Session.send_unit_data(session, conn, data) do

  #     Template.decode(resp)
  #   end
  # end

  # def read_template_attributes(host, template_instance) when is_binary(host) do
  #   open_conn(host)
  #   |> read_template_attributes(template_instance)
  # end

  # def read_template({session, conn}, tag) when is_binary(tag) do
  #   case find_tag({session, conn}, tag) do
  #     {:ok, tag} -> read_template({session, conn}, tag)
  #     error -> error
  #   end
  # end

  # def read_template({session, conn}, %{template_instance: template_instance}) do
  #   with {:ok, %{definition_size: size}} <- read_template_attributes({session, conn}, template_instance),
  #     data <- Template.encode_service(:read_template_service, instance_id: template_instance, bytes: ((size * 4) - 23)),
  #     {:ok, resp} <- Session.send_unit_data(session, conn, data) do

  #     Template.decode(resp)
  #   end
  # end

  # def read_template(host, tag) when is_binary(host) do
  #   open_conn(host)
  #   |> read_template(tag)
  # end

  def inspect(binary) do
    IO.inspect(binary, limit: :infinity, base: :hex)
  end
end
