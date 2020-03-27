defmodule Scrub do
  import Scrub.BinaryUtils, warn: false
  def vendor, do: "ex"
  def serial_number, do: "pTLC"

  alias Scrub.CIP.ConnectionManager
  alias Scrub.CIP.Symbol
  alias Scrub.CIP.Template
  alias Scrub.Session

  require IEx

  def open_conn(host) do
    with {:ok, session} <- Scrub.Session.start_link(host),
         data <- ConnectionManager.encode_service(:large_forward_open),
         {:ok, resp} <- Session.send_rr_data(session, data),
         {:ok, %{orig_network_id: conn}} <- ConnectionManager.decode(resp) do

      {session, conn}
    end
  end

  def read_tag({session, conn}, tag) when is_binary(tag) do
    with {:ok, tag} <- find_tag({session, conn}, tag) do
      read_tag({session, conn}, tag)
    end
  end

  def read_tag({session, conn}, %{structure: :structured, template_instance: instance} = tag) do
    with {:ok, template_attributes} <- get_template_attributes({session, conn}, instance),
         {:ok, template} <- read_template({session, conn}, tag),
         data <- ConnectionManager.encode_service(:unconnected_send, request_path: tag.name),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do

      ConnectionManager.decode(resp, Map.merge(template_attributes, template))
    end
  end
  def read_tag({session, conn}, %{} = tag) do
    with data <- ConnectionManager.encode_service(:unconnected_send, request_path: tag),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do

      ConnectionManager.decode(resp)
    end
  end

  def read_tag(host, tag) when is_binary(host) do
    open_conn(host)
    |> read_tag(tag)
  end

  def list_tags({session, conn}) do
    with data <- Symbol.encode_service(:get_instance_attribute_list),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do

      decode_tag_list(session, conn, resp)
    end
  end

  def list_tags(host) when is_binary(host) do
    open_conn(host)
    |> list_tags()
  end

  def find_tag({session, conn}, tag) when is_binary(tag) do
    with {:ok, tags} <- list_tags({session, conn}),
      %{} = tag <- Enum.find(tags, & &1.name == tag) do

        {:ok, tag}
    else
      nil -> {:error, :not_found}
    end
  end

  def find_tag(host, tag) when is_binary(host) do
    open_conn(host)
    |> find_tag(tag)
  end

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

  def get_template_attributes({session, conn}, <<template_instance :: binary(2, 8)>>) do
    with data <- Template.encode_service(:get_attribute_list, instance_id: template_instance),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do

      Template.decode(resp)
    end
  end

  def get_template_attributes(host, template_instance) when is_binary(host) do
    open_conn(host)
    |> get_template_attributes(template_instance)
  end

  def read_template({session, conn}, tag) when is_binary(tag) do
    case find_tag({session, conn}, tag) do
      {:ok, tag} -> read_template({session, conn}, tag)
      error -> error
    end
  end

  def read_template({session, conn}, %{template_instance: template_instance}) do
    with {:ok, %{definition_size: size}} <- get_template_attributes({session, conn}, template_instance),
      data <- Template.encode_service(:read_template_service, instance_id: template_instance, bytes: ((size * 4) - 23)),
      {:ok, resp} <- Session.send_unit_data(session, conn, data) do

      Template.decode(resp)
    end
  end

  def read_template(host, tag) when is_binary(host) do
    open_conn(host)
    |> read_template(tag)
  end


end
