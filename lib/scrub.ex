defmodule Scrub do
  def vendor, do: "ex"
  def serial_number, do: "pTLC"

  alias Scrub.CIP.ConnectionManager
  alias Scrub.Session

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
end
