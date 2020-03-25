defmodule Scrub do
  def vendor, do: "ex"
  def serial_number, do: "pTLC"

  alias Scrub.CIP.ConnectionManager
  alias Scrub.CIP.Symbol
  alias Scrub.CIP.Template
  alias Scrub.Session

  require IEx

  def read_tag(host, tag) do
    with {:ok, session} <- Scrub.Session.start_link(host),
         data <- ConnectionManager.encode_service(:large_forward_open),
         {:ok, resp} <- Session.send_rr_data(session, data),
         {:ok, %{orig_network_id: conn}} <- ConnectionManager.decode(resp),
         data <- ConnectionManager.encode_service(:unconnected_send, request_path: tag),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do

      ConnectionManager.decode(resp)
    end
  end

  def list_tags(host) do
    with {:ok, session} <- Scrub.Session.start_link(host),
         data <- ConnectionManager.encode_service(:large_forward_open),
         {:ok, resp} <- Session.send_rr_data(session, data),
         {:ok, %{orig_network_id: conn}} <- ConnectionManager.decode(resp),
         data <- Symbol.encode_service(:get_instance_attribute_list),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do

      decode_tag_list(session, conn, resp)
    end
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

  def get_template(host, template_instance) do
    with {:ok, session} <- Scrub.Session.start_link(host),
         data <- ConnectionManager.encode_service(:large_forward_open),
         {:ok, resp} <- Session.send_rr_data(session, data),
         {:ok, %{orig_network_id: conn}} <- ConnectionManager.decode(resp),
         data <- Template.encode_service(:get_attribute_list, instance_id: template_instance),
         {:ok, resp} <- Session.send_unit_data(session, conn, data) do

      Template.decode(resp)
    end
  end

  def get_structure(host, %{instance_id: instance_id, template_instance: template_instance}) do
    with {:ok, %{definition_size: size}} <- get_template(host, template_instance),
      {:ok, session} <- Scrub.Session.start_link(host),
      data <- ConnectionManager.encode_service(:large_forward_open),
      {:ok, resp} <- Session.send_rr_data(session, data),
      {:ok, %{orig_network_id: conn}} <- ConnectionManager.decode(resp),
      data <- Template.encode_service(:read_template_service, instance_id: template_instance, bytes: ((size * 4) - 23)),
      {:ok, resp} <- Session.send_unit_data(session, conn, data) do

      Template.decode(resp)
    end
  end
end
